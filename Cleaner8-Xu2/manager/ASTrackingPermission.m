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
    return 0;
}

+ (void)requestIfNeededWithDelay:(NSTimeInterval)delay
                      completion:(ASTrackingAuthCompletion)completion {

    if (@available(iOS 14, *)) {
        ATTrackingManagerAuthorizationStatus cur = ATTrackingManager.trackingAuthorizationStatus;
        if (cur != ATTrackingManagerAuthorizationStatusNotDetermined) {
            if (completion) completion((NSInteger)cur);
            return;
        }

        void (^doRequest)(void) = ^{
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
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
        if (completion) completion(0);
    }
}

@end
