#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shared by the AppKit preview and the independent WindowServer service.
@interface SCRCursorRaster : NSObject
+ (nullable NSDictionary<NSString *, id> *)renderDescriptor:(NSDictionary<NSString *, id> *)original
                                                     scale:(double)scale
                                                 pixelated:(BOOL)pixelated
                                            markerDiameter:(double)markerDiameter
    NS_SWIFT_NAME(render(_:scale:pixelated:markerDiameter:));
@end

NS_ASSUME_NONNULL_END
