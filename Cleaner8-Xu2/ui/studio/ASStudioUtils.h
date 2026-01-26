#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface ASStudioUtils : NSObject
+ (NSString *)humanBytes:(int64_t)bytes;
+ (NSString *)formatDateYMD:(NSDate *)date;
+ (NSString *)formatDuration:(double)sec; // mm:ss or hh:mm:ss
+ (NSString *)makeDisplayNameForPhotoWithQualitySuffix:(NSString *)q;
+ (NSString *)makeDisplayNameForVideoWithQualitySuffix:(NSString *)q;
@end
NS_ASSUME_NONNULL_END
