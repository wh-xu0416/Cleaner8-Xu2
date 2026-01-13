#import "ASTrackingPermission.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>

static NSString * const kASHasRequestedATTKey = @"hasRequestedATT";

@implementation ASTrackingPermission

+ (BOOL)hasRequested {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kASHasRequestedATTKey];
}

+ (BOOL)shouldRequest {
    if (@available(iOS 14, *)) {
        if ([self hasRequested]) return NO;
        return (ATTrackingManager.trackingAuthorizationStatus == ATTrackingManagerAuthorizationStatusNotDetermined);
    }
    return NO;
}

+ (NSInteger)currentStatusValue {
    if (@available(iOS 14, *)) {
        return (NSInteger)ATTrackingManager.trackingAuthorizationStatus;
    }
    // iOS 13 及以下没有 ATT，这里返回一个约定值即可（比如 0）
    return 0;
}

+ (void)requestIfNeededWithDelay:(NSTimeInterval)delay
                      completion:(ASTrackingAuthCompletion)completion {

    if (![self shouldRequest]) {
        if (completion) completion([self currentStatusValue]);
        return;
    }

    // 防止并发多次触发（多处“需要时调用”时很常见）
    static BOOL sRequesting = NO;
    @synchronized(self) {
        if (sRequesting) {
            if (completion) completion([self currentStatusValue]);
            return;
        }
        sRequesting = YES;
    }

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kASHasRequestedATTKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (@available(iOS 14, *)) {
        void (^doRequest)(void) = ^{
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                @synchronized(self) { sRequesting = NO; }
                if (completion) completion((NSInteger)status);
            }];
        };

        if (delay > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), doRequest);
        } else {
            dispatch_async(dispatch_get_main_queue(), doRequest);
        }
    } else {
        @synchronized(self) { sRequesting = NO; }
        if (completion) completion([self currentStatusValue]);
    }
}

@end
