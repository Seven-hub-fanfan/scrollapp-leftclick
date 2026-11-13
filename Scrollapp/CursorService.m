// Independently implemented native cursor service. No third-party engine code.
// The service owns the WindowServer connection and the recovery journal. kqueue
// watches the app's lifetime and stdin: it restores even after SIGKILL of the app.
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import "CursorRaster.h"
#include <dlfcn.h>
#include <sys/event.h>
#include <sys/file.h>
#include <unistd.h>
#include <math.h>

static int (*connectionID)(void);
static CGError (*copyNamed)(int, char *, CGSize *, CGPoint *, NSUInteger *, CGFloat *, CFArrayRef *);
static CGError (*copyCore)(int, int, CFArrayRef *, CGSize *, CGPoint *, NSUInteger *, CGFloat *);
static CGError (*namedSize)(int, char *, size_t *);
static CGError (*registerImages)(int, char *, bool, bool, CGSize, CGPoint, NSUInteger, CGFloat, CFArrayRef, int *);
static CGError (*removeNamed)(int, char *, bool);
static CGError (*unregisterCore)(int);
static int cid;
static NSString *journalPath;
static NSDictionary *journal;
static NSDictionary *activePlan;
static NSDictionary *lastRestoration;
static NSDictionary *installFailure;
static BOOL recoveryRequired;
static NSString *backupError;
static NSString *stage = @"startup";

static BOOL save(id value, NSString *path);
static NSDictionary *load(NSString *path);

static void emit(NSDictionary *value) {
    NSMutableDictionary *response = value.mutableCopy;
    response[@"recoveryRequired"] = @(recoveryRequired);
    if (journalPath && (value[@"error"] || [value[@"warnings"] count])) {
        NSString *path = [journalPath stringByAppendingString:@".diagnostics"];
        NSMutableArray *events = [load(path)[@"events"] mutableCopy] ?: [NSMutableArray array];
        [events addObject:@{@"time":@([[NSDate date] timeIntervalSince1970]),
            @"stage":stage, @"response":response}];
        while (events.count > 12) [events removeObjectAtIndex:0];
        save(@{@"events":events}, path);
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingSortedKeys error:nil];
    puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
}
static BOOL save(id value, NSString *path) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
static NSDictionary *load(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    id value = data ? [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static CGImageRef decode(NSData *data) {
    if (![data isKindOfClass:NSData.class]) return NULL;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NULL;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    return image;
}
static NSData *encode(CGImageRef image) {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (!destination) return nil;
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return ok ? data : nil;
}
static NSString *pixelHash(CGImageRef image) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image);
    CGContextRelease(context);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}
static NSArray *imagesFor(NSDictionary *descriptor) {
    if (![descriptor isKindOfClass:NSDictionary.class] ||
        ![descriptor[@"Representations"] isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSData *data in descriptor[@"Representations"]) {
        CGImageRef image = decode(data);
        if (!image) return nil;
        [result addObject:CFBridgingRelease(image)];
    }
    return result;
}
static NSDictionary *describe(CGSize size, CGPoint spot, NSUInteger frames, CGFloat duration, CFArrayRef images) {
    NSMutableArray *pngs = [NSMutableArray array], *hashes = [NSMutableArray array];
    for (id value in (__bridge NSArray *)images) {
        CGImageRef image = (__bridge CGImageRef)value;
        NSData *png = encode(image);
        NSString *hash = pixelHash(image);
        if (!png || !hash) return nil;
        [pngs addObject:png]; [hashes addObject:hash];
    }
    return @{@"PointsWide":@(size.width), @"PointsHigh":@(size.height),
        @"HotSpotX":@(spot.x), @"HotSpotY":@(spot.y), @"FrameCount":@(frames),
        @"FrameDuration":@(duration), @"Representations":pngs, @"PixelHashes":hashes};
}
static NSDictionary *readNamed(NSString *name) {
    CGSize size = CGSizeZero; CGPoint spot = CGPointZero;
    NSUInteger frames = 0; CGFloat duration = 0; CFArrayRef images = NULL;
    CGError error = copyNamed(cid, (char *)name.UTF8String, &size, &spot, &frames, &duration, &images);
    NSDictionary *result = !error && images ? describe(size, spot, frames, duration, images) : nil;
    if (images) CFRelease(images);
    return result;
}
static NSDictionary *readCore(int index) {
    CGSize size = CGSizeZero; CGPoint spot = CGPointZero;
    NSUInteger frames = 0; CGFloat duration = 0; CFArrayRef images = NULL;
    CGError error = copyCore(cid, index, &images, &size, &spot, &frames, &duration);
    NSDictionary *result = !error && images ? describe(size, spot, frames, duration, images) : nil;
    if (images) CFRelease(images);
    return result;
}
static NSDictionary *metadata(NSDictionary *descriptor) {
    NSMutableDictionary *result = descriptor.mutableCopy;
    [result removeObjectForKey:@"Representations"];
    return result;
}
static BOOL matches(NSDictionary *expected, NSDictionary *actual) {
    if (!expected || !actual) return NO;
    NSArray *images = imagesFor(expected);
    if (!images.count) return NO;
    NSDictionary *normalized = describe(
        CGSizeMake([expected[@"PointsWide"] doubleValue], [expected[@"PointsHigh"] doubleValue]),
        CGPointMake([expected[@"HotSpotX"] doubleValue], [expected[@"HotSpotY"] doubleValue]),
        [expected[@"FrameCount"] unsignedIntegerValue], [expected[@"FrameDuration"] doubleValue],
        (__bridge CFArrayRef)images);
    return normalized && [metadata(normalized) isEqual:metadata(actual)];
}
static CGError install(NSString *name, NSDictionary *descriptor, BOOL global) {
    NSArray *images = imagesFor(descriptor);
    if (!images.count) return kCGErrorFailure;
    int seed = 0;
    return registerImages(cid, (char *)name.UTF8String, global, global,
        CGSizeMake([descriptor[@"PointsWide"] doubleValue], [descriptor[@"PointsHigh"] doubleValue]),
        CGPointMake([descriptor[@"HotSpotX"] doubleValue], [descriptor[@"HotSpotY"] doubleValue]),
        [descriptor[@"FrameCount"] unsignedIntegerValue], [descriptor[@"FrameDuration"] doubleValue],
        (__bridge CFArrayRef)images, &seed);
}
static BOOL supportedName(id name) {
    if (![name isKindOfClass:NSString.class]) return NO;
    if ([@[@"Arrow", @"ArrowCtx", @"ArrowS", @"IBeam", @"IBeamS", @"IBeamXOR",
           @"Alias", @"Copy", @"Move"] containsObject:
         [name stringByReplacingOccurrencesOfString:@"com.apple.coregraphics." withString:@""]] &&
        [name hasPrefix:@"com.apple.coregraphics."]) return YES;
    if (![name hasPrefix:@"com.apple.cursor."]) return NO;
    NSString *suffix = [name substringFromIndex:[@"com.apple.cursor." length]];
    int index = suffix.intValue;
    return [suffix isEqual:@(index).stringValue] && index >= 2 && index <= 43 &&
        index != 4 && index != 6 && index != 25 && index != 39;
}
static NSArray *knownNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *suffix in @[@"Arrow", @"ArrowCtx", @"ArrowS", @"IBeam", @"IBeamS",
                               @"IBeamXOR", @"Alias", @"Copy", @"Move"])
        [names addObject:[@"com.apple.coregraphics." stringByAppendingString:suffix]];
    for (int i = 2; i <= 43; i++) {
        NSString *name = [NSString stringWithFormat:@"com.apple.cursor.%d", i];
        if (supportedName(name)) [names addObject:name];
    }
    return names;
}
// Backups include native animations; they are not restricted to static theme
// metadata. Check their structure before attempting any writes during recovery.
static BOOL validBackup(NSDictionary *value) {
    if (![value[@"Version"] isEqual:@1] ||
        ![value[@"Names"] isKindOfClass:NSDictionary.class] || [value[@"Names"] count] > 128 ||
        ![value[@"CoreImages"] isKindOfClass:NSDictionary.class]) return NO;
    for (id name in value[@"Names"]) {
        NSDictionary *entry = value[@"Names"][name];
        if (!supportedName(name) || ![entry isKindOfClass:NSDictionary.class] ||
            ![entry[@"Registered"] isKindOfClass:NSNumber.class]) return NO;
        if (![entry[@"Registered"] boolValue]) continue;
        NSDictionary *d = entry[@"Original"];
        if (![d isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY", @"FrameCount", @"FrameDuration"])
            if (![d[key] isKindOfClass:NSNumber.class] || !isfinite([d[key] doubleValue])) return NO;
        if ([d[@"PointsWide"] doubleValue] <= 0 || [d[@"PointsHigh"] doubleValue] <= 0 ||
            [d[@"PointsWide"] doubleValue] > 512 || [d[@"PointsHigh"] doubleValue] > 512 ||
            [d[@"FrameCount"] integerValue] < 1 || [d[@"FrameCount"] integerValue] > 256) return NO;
        NSArray *pngs = d[@"Representations"];
        if (![pngs isKindOfClass:NSArray.class] || !pngs.count || pngs.count > 8) return NO;
        for (id png in pngs)
            if (![png isKindOfClass:NSData.class] || [png length] > 16777216) return NO;
        if (!imagesFor(d).count) return NO;
    }
    for (id index in value[@"CoreImages"]) {
        if (![index isKindOfClass:NSString.class] ||
            ![index isEqual:@([index intValue]).stringValue] || [index intValue] < 0 || [index intValue] >= 128 ||
            ![value[@"CoreImages"][index] isKindOfClass:NSDictionary.class]) return NO;
    }
    return YES;
}
static NSString *archiveBackup(void) {
    NSString *directory = [[journalPath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"recovery-archives"];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:nil]) return nil;
    NSString *path = [directory stringByAppendingPathComponent:
        [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"]];
    return [fm copyItemAtPath:journalPath toPath:path error:nil] ? path.lastPathComponent : nil;
}
static BOOL clearBackup(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:journalPath] && ![fm removeItemAtPath:journalPath error:nil]) return NO;
    journal = nil; activePlan = nil; backupError = nil; recoveryRequired = NO;
    return YES;
}
static void exportSystemImages(void) {
    if (recoveryRequired || journal) return;
    NSDictionary *sources = @{@"arrow":@[@"com.apple.coregraphics.Arrow", @7],
        @"text":@[@"com.apple.coregraphics.IBeam", @26], @"link":@[@"", @13],
        @"grab":@[@"", @11], @"crosshair":@[@"", @20], @"horizontal":@[@"", @27],
        @"vertical":@[@"", @22], @"diagonalRight":@[@"", @29], @"diagonalLeft":@[@"", @33],
        @"unavailable":@[@"", @3], @"help":@[@"", @13], @"zoomIn":@[@"", @42], @"zoomOut":@[@"", @43]};
    NSMutableDictionary *roles = [NSMutableDictionary dictionary];
    for (NSString *role in sources) {
        NSArray *source = sources[role];
        NSDictionary *d = [source[0] length] ? readNamed(source[0]) : nil;
        d = d ?: readCore([source[1] intValue]);
        if (d) roles[role] = d;
    }
    save(@{@"Roles":roles}, [[journalPath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"system-cursors.plist"]);
}
// Bound the full payload and decoded image dimensions before any system writes.
// v1 permits static images only. Wait and Empty retain their system semantics.
static NSString *validate(NSDictionary *plan) {
    if (![plan isKindOfClass:NSDictionary.class] || !plan.count || plan.count > 128) return @"invalidPayload";
    if (plan[@"com.apple.coregraphics.Wait"] || plan[@"com.apple.coregraphics.Empty"] ||
        plan[@"com.apple.cursor.4"] || plan[@"com.apple.cursor.25"]) return @"reservedCursor";
    for (NSString *name in plan) {
        if (![name isKindOfClass:NSString.class] ||
            !([name hasPrefix:@"com.apple.coregraphics."] || [name hasPrefix:@"com.apple.cursor."])) return @"invalidName";
        NSDictionary *d = plan[name];
        if (![d isKindOfClass:NSDictionary.class]) return @"invalidPayload";
        if ([d[@"RestoreOriginal"] isEqual:@YES] && d.count == 1) continue;
        for (NSString *key in @[@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY", @"FrameCount", @"FrameDuration"])
            if (![d[key] isKindOfClass:NSNumber.class] || !isfinite([d[key] doubleValue])) return @"invalidMetadata";
        double w = [d[@"PointsWide"] doubleValue], h = [d[@"PointsHigh"] doubleValue];
        double x = [d[@"HotSpotX"] doubleValue], y = [d[@"HotSpotY"] doubleValue];
        if (w < 1 || w > 512 || h < 1 || h > 512 || x < 0 || y < 0 || x >= w || y >= h ||
            [d[@"FrameCount"] integerValue] != 1 || [d[@"FrameDuration"] doubleValue] != 0) return @"invalidMetadata";
        NSArray *representations = d[@"Representations"];
        if (![representations isKindOfClass:NSArray.class] ||
            representations.count < 2 || representations.count > 6) return @"invalidImages";
        NSInteger previousWidth = 0;
        for (NSUInteger i = 0; i < representations.count; i++) {
            NSData *data = representations[i];
            if (![data isKindOfClass:NSData.class] || data.length > 4194304) return @"invalidImages";
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
            if (source) CFRelease(source);
            NSInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
            NSInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
            if (width <= previousWidth || width > 2048 || height < 1 || height > 2048 ||
                fabs((double)width / w - (double)height / h) > 0.000001) return @"invalidImages";
            if (i < 2 && (width != (NSInteger)(w * (i + 1)) ||
                          height != (NSInteger)(h * (i + 1)))) return @"invalidImages";
            previousWidth = width;
        }
        if (!imagesFor(d)) return @"invalidImages";
    }
    return nil;
}
static NSDictionary *snapshot(NSDictionary *plan) {
    // Warm core caches first, then take the named baseline (same restore order).
    NSMutableDictionary *cores = [NSMutableDictionary dictionary], *names = [NSMutableDictionary dictionary];
    for (int i = 0; i < 128; i++) {
        NSDictionary *d = readCore(i);
        if (d) cores[@(i).stringValue] = d;
    }
    for (NSString *name in plan) {
        size_t bytes = 0;
        CGError error = namedSize(cid, (char *)name.UTF8String, &bytes);
        BOOL registered = !error && bytes > 0;
        NSDictionary *original = registered ? readNamed(name) : nil;
        if (registered && !original) return nil;
        names[name] = original ? @{@"Registered":@YES, @"Original":original} : @{@"Registered":@NO};
    }
    return @{@"Version":@1, @"Names":names, @"CoreImages":cores};
}
static BOOL preflight(NSDictionary *names) {
    // Verify original animation/metadata can be written back before replacing it.
    for (NSString *name in names) {
        NSDictionary *original = names[name][@"Original"];
        if (!original) continue;
        NSString *temporary = [@"com.scrollapp.preflight." stringByAppendingString:name];
        CGError error = install(temporary, original, NO);
        BOOL ok = !error && matches(original, readNamed(temporary));
        removeNamed(cid, (char *)temporary.UTF8String, false);
        if (!ok) return NO;
    }
    return YES;
}
static NSDictionary *restore(void) {
    if (backupError) { recoveryRequired = YES; return @{@"ok":@NO, @"error":backupError}; }
    if (!journal) { recoveryRequired = NO; return @{@"ok":@YES, @"restored":@0}; }
    NSMutableArray *failures = [NSMutableArray array], *warnings = [NSMutableArray array];
    NSDictionary *names = journal[@"Names"];
    for (NSString *name in names) {
        NSDictionary *entry = names[name];
        CGError error = [entry[@"Registered"] boolValue] ? install(name, entry[@"Original"], YES) :
            removeNamed(cid, (char *)name.UTF8String, false);
        // Removing an already absent registration is harmless; verify below.
        if (error && [entry[@"Registered"] boolValue])
            [failures addObject:@{@"name":name, @"stage":@"installOriginal", @"code":@(error)}];
    }
    CGError cacheError = unregisterCore(cid);
    if (cacheError) [failures addObject:@{@"name":@"coreCache", @"stage":@"clearCache", @"code":@(cacheError)}];
    for (NSString *index in journal[@"CoreImages"]) {
        if (!matches(journal[@"CoreImages"][index], readCore(index.intValue)))
            [warnings addObject:[@"core." stringByAppendingString:index]];
    }
    for (NSString *name in names) {
        size_t bytes = 0;
        BOOL registered = !namedSize(cid, (char *)name.UTF8String, &bytes) && bytes > 0;
        NSDictionary *entry = names[name];
        if (registered != [entry[@"Registered"] boolValue] ||
            (registered && !matches(entry[@"Original"], readNamed(name))))
            [failures addObject:@{@"name":name, @"stage":@"verifyOriginal",
                @"expectedRegistered":entry[@"Registered"], @"actualRegistered":@(registered)}];
    }
    if (failures.count) {
        recoveryRequired = YES;
        return @{@"ok":@NO, @"error":@"restoreFailed", @"details":failures, @"warnings":warnings};
    }
    NSUInteger count = names.count;
    NSUInteger coreCount = [journal[@"CoreImages"] count];
    // Named registrations are the owned state; regenerated native core caches
    // can differ after display/accessibility changes. Retain that baseline in an
    // archive before releasing the journal, rather than locking out the service.
    NSString *archive = warnings.count ? archiveBackup() : nil;
    if ((warnings.count && !archive) || !clearBackup()) {
        recoveryRequired = YES;
        return @{@"ok":@NO, @"error":@"backupFailed"};
    }
    lastRestoration = @{@"ok":@YES, @"restored":@(count),
        @"coreVerified":@(coreCount - warnings.count), @"warnings":warnings, @"archive":archive ?: @""};
    exportSystemImages();
    return lastRestoration;
}
static NSDictionary *nativeReset(void) {
    // This explicit fallback discards registrations, never the user's only
    // backup. Invalid journals are copied byte-for-byte before system writes.
    NSString *archive = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:journalPath]) {
        archive = archiveBackup();
        if (!archive) return @{@"ok":@NO, @"error":@"backupFailed"};
    }
    NSMutableArray *failures = [NSMutableArray array];
    // The last parameter selects global removal for legacy cursor entries.
    // Built-in CoreGraphics names regenerate their native fallback immediately
    // (and may report kCGErrorFailure while doing so); they remain readable.
    for (NSString *name in knownNames()) removeNamed(cid, (char *)name.UTF8String, true);
    CGError error = unregisterCore(cid);
    if (error) [failures addObject:@{@"name":@"coreCache", @"code":@(error)}];
    for (NSString *name in knownNames()) {
        size_t bytes = 0;
        BOOL registered = !namedSize(cid, (char *)name.UTF8String, &bytes) && bytes > 0;
        if ([name hasPrefix:@"com.apple.coregraphics."]) {
            NSDictionary *native = registered ? readNamed(name) : nil;
            if (!native || (activePlan[name] && matches(activePlan[name], native)))
                [failures addObject:@{@"name":name, @"stage":@"verifyNativeFallback"}];
        } else if (registered)
            [failures addObject:@{@"name":name, @"stage":@"verifyRemoved"}];
    }
    if (failures.count || !clearBackup()) {
        recoveryRequired = YES;
        return @{@"ok":@NO, @"error":@"restoreFailed", @"details":failures, @"archive":archive ?: @""};
    }
    exportSystemImages();
    lastRestoration = @{@"ok":@YES, @"nativeReset":@YES, @"archive":archive ?: @""};
    return lastRestoration;
}
static NSDictionary *ensureBackup(NSDictionary *plan) {
    // Each apply extends the same original baseline, so switches never snapshot
    // a previous Scrollapp theme as the user's default.
    if (!journal) {
        NSDictionary *baseline = snapshot(plan);
        if (!baseline || !preflight(baseline[@"Names"])) return @{@"ok":@NO, @"error":@"backupUnsupported"};
        if (!save(baseline, journalPath)) return @{@"ok":@NO, @"error":@"backupFailed"};
        journal = baseline;
    } else {
        NSMutableSet *additional = [NSMutableSet setWithArray:plan.allKeys];
        [additional minusSet:[NSSet setWithArray:[journal[@"Names"] allKeys]]];
        if (additional.count) return @{@"ok":@NO, @"error":@"mappingChanged"};
    }
    return @{@"ok":@YES};
}
static BOOL installPlan(NSDictionary *plan) {
    for (NSString *name in journal[@"Names"]) {
        if (plan[name]) {
            CGError error = install(name, plan[name], YES);
            NSDictionary *actual = !error ? readNamed(name) : nil;
            if (error || !matches(plan[name], actual)) {
                installFailure = @{@"name":name, @"code":@(error),
                    @"expected":metadata(plan[name]), @"actual":actual ? metadata(actual) : @{}};
                return NO;
            }
        } else {
            NSDictionary *original = journal[@"Names"][name][@"Original"];
            if (original) {
                if (install(name, original, YES) || !matches(original, readNamed(name))) return NO;
            } else {
                removeNamed(cid, (char *)name.UTF8String, false);
            }
        }
    }
    return YES;
}
static NSDictionary *commitPlan(NSDictionary *plan) {
    NSDictionary *previous = activePlan;
    if (!installPlan(plan)) {
        NSDictionary *failure = installFailure ?: @{};
        if (previous && installPlan(previous))
            return @{@"ok":@NO, @"error":@"applyFailed", @"previousRetained":@YES, @"details":failure};
        NSDictionary *result = restore();
        return @{@"ok":@NO, @"error":[result[@"ok"] boolValue] ? @"applyFailed" : @"restoreFailed",
            @"reset":result[@"ok"], @"details":failure};
    }
    activePlan = plan;
    return @{@"ok":@YES, @"applied":@(plan.count)};
}
static NSDictionary *apply(NSDictionary *plan, double scale, BOOL pixelated, double markerDiameter) {
    NSString *error = validate(plan);
    if (error) return @{@"ok":@NO, @"error":error};
    if (!isfinite(scale) || scale < 0.5 || scale > 8 || !isfinite(markerDiameter) ||
        markerDiameter < 0 || markerDiameter > 16) return @{@"ok":@NO, @"error":@"invalidMetadata"};
    NSDictionary *backup = ensureBackup(plan);
    if (![backup[@"ok"] boolValue]) return backup;
    NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    for (NSString *name in plan) {
        BOOL useOriginal = [plan[name][@"RestoreOriginal"] boolValue];
        NSDictionary *source = useOriginal ? journal[@"Names"][name][@"Original"] : plan[name];
        if (!source) continue; // Keep an originally absent system registration.
        NSDictionary *d = source;
        if (!useOriginal || scale != 1 || markerDiameter > 0) {
            d = cache[source] ?: [SCRCursorRaster renderDescriptor:source scale:scale
                pixelated:useOriginal ? NO : pixelated markerDiameter:markerDiameter];
            if (!d) return @{@"ok":@NO, @"error":@"invalidImages"};
            cache[source] = d;
        }
        resolved[name] = d;
    }
    return commitPlan(resolved);
}
static NSDictionary *applySystem(NSArray *names, double scale, double markerDiameter) {
    if (!isfinite(scale) || scale < 0.5 || scale > 8 || !isfinite(markerDiameter) ||
        markerDiameter < 0 || markerDiameter > 16) return @{@"ok":@NO, @"error":@"invalidMetadata"};
    if (scale == 1 && markerDiameter == 0) return restore();
    if (![names isKindOfClass:NSArray.class] || !names.count || names.count > 128)
        return @{@"ok":@NO, @"error":@"invalidPayload"};
    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    for (id name in names) {
        if (![name isKindOfClass:NSString.class] ||
            !([name hasPrefix:@"com.apple.cursor."] || [name hasPrefix:@"com.apple.coregraphics."]))
            return @{@"ok":@NO, @"error":@"invalidName"};
        if ([@[@"com.apple.coregraphics.Wait", @"com.apple.coregraphics.Empty",
               @"com.apple.cursor.4", @"com.apple.cursor.25"] containsObject:name])
            return @{@"ok":@NO, @"error":@"reservedCursor"};
        keys[name] = @{};
    }
    NSDictionary *backup = ensureBackup(keys);
    if (![backup[@"ok"] boolValue]) return backup;
    NSMutableDictionary *plan = [NSMutableDictionary dictionary];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    for (NSString *name in keys) {
        NSDictionary *original = journal[@"Names"][name][@"Original"];
        if (!original) continue; // Preserve an originally absent registration.
        NSDictionary *d = cache[original] ?: [SCRCursorRaster renderDescriptor:original scale:scale
            pixelated:NO markerDiameter:markerDiameter];
        if (!d) return @{@"ok":@NO, @"error":@"invalidImages"};
        cache[original] = d;
        plan[name] = d;
    }
    return commitPlan(plan);
}
static BOOL loadAPI(void) {
    void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
    void *hi = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_NOW);
    if (!cg || !hi) return NO;
    connectionID = dlsym(cg, "CGSMainConnectionID");
    copyNamed = dlsym(cg, "CGSCopyRegisteredCursorImages");
    namedSize = dlsym(cg, "CGSGetRegisteredCursorDataSize");
    registerImages = dlsym(cg, "CGSRegisterCursorWithImages");
    removeNamed = dlsym(cg, "CGSRemoveRegisteredCursor");
    copyCore = dlsym(hi, "CoreCursorCopyImages");
    unregisterCore = dlsym(hi, "CoreCursorUnregisterAll");
    return connectionID && copyNamed && namedSize && registerImages && removeNamed && copyCore && unregisterCore;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 || !loadAPI()) { emit(@{@"ok":@NO, @"error":@"unsupportedSystem"}); return 2; }
        [NSApplication sharedApplication];
        cid = connectionID();
        journalPath = @(argv[1]);
        pid_t parent = atoi(argv[2]);
        NSString *lockPath = [journalPath stringByAppendingString:@".lock"];
        int lock = open(lockPath.UTF8String, O_CREAT | O_RDWR, 0600);
        if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) { emit(@{@"ok":@NO, @"error":@"anotherInstance"}); return 3; }
        int queue = kqueue();
        struct kevent events[2];
        EV_SET(&events[0], parent, EVFILT_PROC, EV_ADD | EV_ENABLE, NOTE_EXIT, 0, NULL);
        EV_SET(&events[1], STDIN_FILENO, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
        if (queue < 0 || kevent(queue, events, 2, NULL, 0, NULL) < 0) {
            emit(@{@"ok":@NO, @"error":@"guardUnavailable"}); return 4;
        }
        // Recover a journal left by service/system interruption before accepting
        // any new theme. Never discard an unsuccessful recovery.
        if ([[NSFileManager defaultManager] fileExistsAtPath:journalPath]) {
            journal = load(journalPath);
            if (!validBackup(journal)) backupError = @"invalidBackup";
            NSDictionary *result = restore();
            if (![result[@"ok"] boolValue]) {
                NSMutableDictionary *paused = result.mutableCopy;
                paused[@"ready"] = @NO; paused[@"pid"] = @(getpid());
                emit(paused);
            } else {
                NSMutableDictionary *ready = result.mutableCopy;
                ready[@"ready"] = @YES; ready[@"pid"] = @(getpid());
                emit(ready);
            }
        } else {
            exportSystemImages();
            emit(@{@"ok":@YES, @"ready":@YES, @"pid":@(getpid())});
        }
        NSMutableData *buffer = [NSMutableData data];
        BOOL finished = NO;
        while (!finished) {
            struct kevent event;
            if (kevent(queue, NULL, 0, &event, 1, NULL) < 0) break;
            if (event.filter == EVFILT_PROC) break;
            char bytes[8192];
            ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (count <= 0) break;
            [buffer appendBytes:bytes length:(NSUInteger)count];
            if (buffer.length > 65536) break;
            while (YES) {
                NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
                if (newline.location == NSNotFound) break;
                @autoreleasepool {
                    NSData *line = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
                    [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
                    id command = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                    if (![command isKindOfClass:NSDictionary.class]) { emit(@{@"ok":@NO, @"error":@"invalidCommand"}); continue; }
                    NSString *action = command[@"action"];
                    stage = [action isKindOfClass:NSString.class] ? action : @"invalidCommand";
                    if (recoveryRequired && ([action isEqual:@"apply"] || [action isEqual:@"system"])) {
                        emit(@{@"ok":@NO, @"error":backupError ?: @"restoreFailed"});
                    } else if ([action isEqual:@"apply"]) {
                        NSString *path = command[@"path"];
                        NSDictionary *payload = [path isKindOfClass:NSString.class] ? load(path) : nil;
                        double scale = command[@"scale"] ? [command[@"scale"] doubleValue] : 1;
                        emit(apply(payload[@"Cursors"], scale, [command[@"pixelated"] boolValue],
                            [command[@"markerDiameter"] doubleValue]));
                    } else if ([action isEqual:@"system"]) {
                        emit(applySystem(command[@"names"], [command[@"scale"] doubleValue],
                            [command[@"markerDiameter"] doubleValue]));
                    } else if ([action isEqual:@"reset"] || [action isEqual:@"quit"]) {
                        NSDictionary *result = restore(); emit(result);
                        finished = [action isEqual:@"quit"];
                    } else if ([action isEqual:@"nativeReset"]) {
                        emit(nativeReset());
                    } else if ([action isEqual:@"diagnostics"]) {
                        emit(@{@"ok":@YES, @"os":NSProcessInfo.processInfo.operatingSystemVersionString,
                            @"pid":@(getpid()), @"backupError":backupError ?: @"",
                            @"hasBackup":@([NSFileManager.defaultManager fileExistsAtPath:journalPath]),
                            @"namedBackupCount":@([journal[@"Names"] count]),
                            @"history":load([journalPath stringByAppendingString:@".diagnostics"]) ?: @{},
                            @"lastRestoration":lastRestoration ?: @{}});
                    } else if ([action isEqual:@"verify"]) {
                        BOOL ok = activePlan != nil;
                        for (NSString *name in activePlan) if (!matches(activePlan[name], readNamed(name))) ok = NO;
                        NSDictionary *arrow = readNamed(@"com.apple.coregraphics.Arrow");
                        NSDictionary *legacy = readNamed(@"com.apple.cursor.14");
                        NSMutableDictionary *readback = [NSMutableDictionary dictionary];
                        // Optional read-only diagnostics for integration checks.
                        NSArray *requested = command[@"names"];
                        if ([requested isKindOfClass:NSArray.class] && requested.count <= 128) {
                            for (id name in requested) {
                                if (![name isKindOfClass:NSString.class] ||
                                    !([name hasPrefix:@"com.apple.coregraphics."] || [name hasPrefix:@"com.apple.cursor."])) continue;
                                NSDictionary *d = readNamed(name);
                                readback[name] = d ? metadata(d) : @{};
                            }
                        }
                        emit(@{@"ok":@(ok), @"verified":@(activePlan.count),
                            @"arrowPoints":@[arrow[@"PointsWide"] ?: @0, arrow[@"PointsHigh"] ?: @0],
                            @"arrowHotSpot":@[arrow[@"HotSpotX"] ?: @0, arrow[@"HotSpotY"] ?: @0],
                            @"legacyFrames":legacy[@"FrameCount"] ?: @0, @"namedReadback":readback});
                    } else emit(@{@"ok":@NO, @"error":@"invalidCommand"});
                }
                if (finished) break;
            }
        }
        stage = @"shutdown";
        NSDictionary *final = restore();
        // Persist the recovery outcome for diagnostics without retaining images.
        save([final[@"ok"] boolValue] && !journal && lastRestoration ? lastRestoration : final,
             [journalPath stringByAppendingString:@".result"]);
        close(queue); close(lock);
        return [final[@"ok"] boolValue] ? 0 : 6;
    }
}
