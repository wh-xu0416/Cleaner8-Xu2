#import "ASStudioItem.h"

@implementation ASStudioItem

- (NSDictionary *)toJSON {
    return @{
        @"assetId": self.assetId ?: @"",
        @"type": @(self.type),
        @"displayName": self.displayName ?: @"",
        @"compressedAt": @([self.compressedAt timeIntervalSince1970]),
        @"afterBytes": @(self.afterBytes),
        @"beforeBytes": @(self.beforeBytes),
        @"duration": @(self.duration)
    };
}

+ (instancetype)fromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    ASStudioItem *it = [ASStudioItem new];
    it.assetId = [json[@"assetId"] isKindOfClass:[NSString class]] ? json[@"assetId"] : @"";
    it.type = (ASStudioMediaType)[json[@"type"] integerValue];
    it.displayName = [json[@"displayName"] isKindOfClass:[NSString class]] ? json[@"displayName"] : @"";
    NSTimeInterval ts = [json[@"compressedAt"] doubleValue];
    it.compressedAt = (ts > 0) ? [NSDate dateWithTimeIntervalSince1970:ts] : [NSDate date];
    it.afterBytes = [json[@"afterBytes"] longLongValue];
    it.beforeBytes = [json[@"beforeBytes"] longLongValue];
    it.duration = [json[@"duration"] doubleValue];
    return it;
}

@end
