#import "ASStudioUtils.h"

@implementation ASStudioUtils

+ (NSString *)humanBytes:(int64_t)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lldB", bytes];
    double kb = (double)bytes / 1024.0;
    if (kb < 1024) return [NSString stringWithFormat:@"%.0fKB", kb];
    double mb = kb / 1024.0;
    if (mb < 1024) return [NSString stringWithFormat:@"%.1fMB", mb];
    double gb = mb / 1024.0;
    return [NSString stringWithFormat:@"%.2fGB", gb];
}

+ (NSString *)formatDateYMD:(NSDate *)date {
    if (!date) return @"";

    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [NSDateFormatter new];
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterNoStyle;
        df.doesRelativeDateFormatting = NO;
    });

    df.locale = [NSLocale autoupdatingCurrentLocale];
    df.timeZone = [NSTimeZone localTimeZone];

    return [df stringFromDate:date];
}

+ (NSString *)formatDuration:(double)sec {
    if (sec < 0) sec = 0;
    NSInteger s = (NSInteger)llround(sec);
    NSInteger h = s / 3600;
    NSInteger m = (s % 3600) / 60;
    NSInteger r = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)r];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)m, (long)r];
}

+ (NSString *)_timestampString {
    static NSDateFormatter *df;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"yyyyMMdd_HHmmss";
    });
    return [df stringFromDate:[NSDate date]];
}

+ (NSString *)makeDisplayNameForPhotoWithQualitySuffix:(NSString *)q {
    // q: @"S"/@"M"/@"L"
    return [NSString stringWithFormat:@"IMG_%@_%@.jpg", [self _timestampString], q ?: @"M"];
}

+ (NSString *)makeDisplayNameForVideoWithQualitySuffix:(NSString *)q {
    return [NSString stringWithFormat:@"VID_%@_%@.mp4", [self _timestampString], q ?: @"M"];
}

@end
