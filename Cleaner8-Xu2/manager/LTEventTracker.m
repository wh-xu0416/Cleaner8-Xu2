#import "LTEventTracker.h"
#import "ThinkingSDK.h"

@implementation LTEventTracker

+ (instancetype)shared {
    static LTEventTracker *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LTEventTracker alloc] init];
#ifdef DEBUG
        instance.enableLog = YES;
#else
        instance.enaLTEventTrackerbleLog = NO;
#endif
    });
    return instance;
}

- (void)track:(NSString *)event properties:(NSDictionary<NSString *,id> *)properties {
    [self track:event properties:properties requiredKeys:nil];
}

- (void)track:(NSString *)event
   properties:(NSDictionary<NSString *,id> *)properties
 requiredKeys:(NSArray<NSString *> *)requiredKeys
{
    if (event.length == 0) return;

    NSDictionary *props = properties ?: @{};

    // 打印
    if (self.enableLog) {
        NSLog(@"\n [打点] TRACK\n- 事件名: %@\n- 字段参数: %@\n", event, [self prettyJSONString:props]);
    }

    [TDAnalytics track:event properties:properties];
}

#pragma mark - JSON Pretty Print

- (NSString *)prettyJSONString:(id)obj {
    if (!obj) return @"<nil>";
    if (![NSJSONSerialization isValidJSONObject:obj]) return [obj description];

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&err];
    if (err || !data) return [obj description];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [obj description];
}

@end
