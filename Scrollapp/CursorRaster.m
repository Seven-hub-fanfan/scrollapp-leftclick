#import "CursorRaster.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

@implementation SCRCursorRaster
+ (NSDictionary<NSString *, id> *)renderDescriptor:(NSDictionary<NSString *, id> *)original
                                            scale:(double)scale
                                        pixelated:(BOOL)pixelated
                                   markerDiameter:(double)markerDiameter {
    double w = [original[@"PointsWide"] doubleValue], h = [original[@"PointsHigh"] doubleValue];
    NSUInteger frames = [original[@"FrameCount"] unsignedIntegerValue];
    double targetW = round(w * scale), targetH = round(h * scale);
    if (!isfinite(scale) || scale < 0.5 || scale > 8 || w <= 0 || h <= 0 || !frames ||
        targetW < 1 || targetH < 1 || targetW > 512 || targetH > 512 ||
        !isfinite(markerDiameter) || markerDiameter < 0 || markerDiameter > 16) return nil;

    // Always start from the same largest original. Never resize a previous
    // output or switch artwork when crossing a 64/160/320 px threshold.
    CGImageRef master = NULL;
    for (NSData *data in original[@"Representations"]) {
        if (![data isKindOfClass:NSData.class]) continue;
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        CGImageRef candidate = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
        if (source) CFRelease(source);
        if (!candidate) continue;
        if (!master || CGImageGetWidth(candidate) > CGImageGetWidth(master)) {
            if (master) CGImageRelease(master);
            master = candidate;
        } else CGImageRelease(candidate);
    }
    if (!master) return nil;
    size_t sourceW = CGImageGetWidth(master), sourceH = CGImageGetHeight(master);
    if (sourceH % frames != 0) { CGImageRelease(master); return nil; }

    double x = (double)(float)([original[@"HotSpotX"] doubleValue] * targetW / w);
    double y = (double)(float)([original[@"HotSpotY"] doubleValue] * targetH / h);
    // Hotspots are measured from the top left. Pad the artwork and shift its
    // hotspot together so the dot remains centered on the actual click point.
    double radius = markerDiameter > 0 ? markerDiameter / 2 + 1 : 0;
    double left = ceil(fmax(0, radius - x)), top = ceil(fmax(0, radius - y));
    double right = ceil(fmax(0, x + radius - targetW));
    double bottom = ceil(fmax(0, y + radius - targetH));
    double canvasW = targetW + left + right, canvasH = targetH + top + bottom;
    x = (double)(float)(x + left); y = (double)(float)(y + top);
    if (canvasW > 544 || canvasH > 544 || canvasW * 2 > 2048 || canvasH * 2 > 2048 ||
        canvasH * frames * 2 > 16384 || canvasW * canvasH * frames * 4 > 16777216) {
        CGImageRelease(master); return nil;
    }
    // Explicit 1x/2x images avoid AppKit or WindowServer upscaling a 1x sprite.
    // A bounded extra representation retains source detail for system zoom.
    int maximumDensity = (int)fmin(16, fmin(floor(2048 / canvasW), fmin(floor(2048 / canvasH),
        fmin(floor(16384 / (canvasH * frames)), floor(sqrt(16777216 / (canvasW * canvasH * frames)))))));
    int nativeDensity = (int)fmin(maximumDensity, ceil(fmax((double)sourceW / targetW,
                                                        (double)sourceH / frames / targetH)));
    NSMutableArray<NSNumber *> *densities = [NSMutableArray arrayWithArray:@[@1, @2]];
    if (nativeDensity > 2) [densities addObject:@(nativeDensity)];
    NSMutableArray<NSData *> *pngs = [NSMutableArray array];
    BOOL failed = NO;
    for (NSNumber *value in densities) {
        int density = value.intValue;
        size_t width = (size_t)canvasW * density, height = (size_t)canvasH * density * frames;
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (!context) { failed = YES; break; }
        CGContextScaleCTM(context, density, density);
        CGContextSetInterpolationQuality(context, pixelated ? kCGInterpolationNone : kCGInterpolationHigh);
        for (NSUInteger frame = 0; frame < frames; frame++) {
            CGImageRef image = CGImageCreateWithImageInRect(master,
                CGRectMake(0, frame * (sourceH / frames), sourceW, sourceH / frames));
            if (!image) { failed = YES; break; }
            double frameBottom = (frames - 1 - frame) * canvasH;
            CGContextDrawImage(context, CGRectMake(left, frameBottom + bottom, targetW, targetH), image);
            CGImageRelease(image);
            if (markerDiameter > 0) {
                // Draw after resizing. Its diameter is in points, independent
                // of cursor scale, including each frame of an original strip.
                CGRect circle = CGRectMake(x - markerDiameter / 2,
                    frameBottom + canvasH - y - markerDiameter / 2, markerDiameter, markerDiameter);
                CGContextSetShouldAntialias(context, true);
                CGContextSetRGBFillColor(context, 0.94, 0.08, 0.12, 1);
                CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);
                CGContextSetLineWidth(context, 0.75);
                CGContextAddEllipseInRect(context, circle);
                CGContextDrawPath(context, kCGPathFillStroke);
            }
        }
        CGImageRef rendered = failed ? NULL : CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        NSMutableData *data = [NSMutableData data];
        CGImageDestinationRef destination = rendered ? CGImageDestinationCreateWithData(
            (__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL) : NULL;
        BOOL ok = NO;
        if (destination) {
            CGImageDestinationAddImage(destination, rendered, NULL);
            ok = CGImageDestinationFinalize(destination);
            CFRelease(destination);
        }
        if (rendered) CGImageRelease(rendered);
        if (!ok) { failed = YES; break; }
        [pngs addObject:data];
    }
    CGImageRelease(master);
    if (failed) return nil;
    NSMutableDictionary *result = original.mutableCopy;
    result[@"PointsWide"] = @(canvasW); result[@"PointsHigh"] = @(canvasH);
    result[@"HotSpotX"] = @(x); result[@"HotSpotY"] = @(y);
    result[@"Representations"] = pngs;
    [result removeObjectForKey:@"PixelHashes"];
    return result;
}
@end
