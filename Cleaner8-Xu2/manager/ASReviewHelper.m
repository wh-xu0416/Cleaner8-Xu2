#import "ASReviewHelper.h"
#import <StoreKit/StoreKit.h>
#import "ASABTestManager.h"
#import "LTEventTracker.h"
#import "Cleaner8_Xu2-Swift.h"

#define kABKeyPaidRate (AppConstants.abKeyPaidRateRate)
#define kABKeySetRate  (AppConstants.abKeySetRateRate)

static NSString * const kOCSystemReviewDidRequestKey = @"oc_system_review_did_request_once";
static NSString * const kASFirstInstallTSKey = @"as_first_install_ts";

static inline NSString *ASABTrackedFlagKey(NSString *abKey) {
    return [NSString stringWithFormat:@"as_abtest_tracked_%@", abKey ?: @""];
}

@interface ASReviewHelper ()
+ (UIWindowScene *)_activeWindowSceneFromVC:(UIViewController *)vc API_AVAILABLE(ios(13.0));
+ (BOOL)_isReviewAllowedByABForSourceAndTrackIfNeeded:(NSString *)source;
+ (BOOL)_isWithin24HoursSinceInstall;
@end

@implementation ASReviewHelper

+ (void)requestReviewOnceFromViewController:(UIViewController *)vc
                                     source:(NSString *)source {
    if (@available(iOS 15.0, *)) {
        [[LTEventTracker shared] track: @"Rate" properties:@{@"position": source}];

        // 先按来源判断是否允许弹出（此处会在“远程AB值”时触发一次打点，默认值不打点）
        if (![self _isReviewAllowedByABForSourceAndTrackIfNeeded:source]) {
            return;
        }

        // 只尝试弹一次
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kOCSystemReviewDidRequestKey]) {
            return;
        }

        void (^doRequest)(void) = ^{
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kOCSystemReviewDidRequestKey]) {
                return;
            }

            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kOCSystemReviewDidRequestKey];

            UIWindowScene *scene = [self _activeWindowSceneFromVC:vc];
            if (scene) {
                [SKStoreReviewController requestReviewInScene:scene];
            } else {
                [SKStoreReviewController requestReview];
            }
        };

        if ([NSThread isMainThread]) {
            doRequest();
        } else {
            dispatch_async(dispatch_get_main_queue(), doRequest);
        }
    }
}

+ (BOOL)_isReviewAllowedByABForSourceAndTrackIfNeeded:(NSString *)source {
    if (source.length == 0) return YES;

    NSString *abKey = nil;

    static NSSet<NSString *> *paidSources;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paidSources = [NSSet setWithArray:@[
            @"photo_compress",
            @"video_compress",
            @"livephoto_compress",
            @"similar_photo",
            @"similar_video",
            @"duplicate_photo",
            @"duplicate_video",
            @"screenshots",
            @"other_photo",
            @"blurry",
            @"screen_recording",
            @"large_video",
            @"swipe_page",
            @"contact"
        ]];
    });

    if ([paidSources containsObject:source] ||
        [source isEqualToString:kABKeyPaidRate]) {
        abKey = kABKeyPaidRate;

    } else if ([source isEqualToString:@"setting"] ||
               [source isEqualToString:kABKeySetRate]) {
        abKey = kABKeySetRate;

    } else {
        return YES;
    }

    ASABTestManager *ab = [ASABTestManager shared];
    NSString *val = [ab stringForKey:abKey]; // open/close；无缓存默认 close

    // 仅当值来源为 Remote 时打点；默认值不打点；且每个 key 只打一次；且安装24小时内才打点
    if ([ab isRemoteValueForKey:abKey] && [self _isWithin24HoursSinceInstall]) {
        NSString *flagKey = ASABTrackedFlagKey(abKey);
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if (![ud boolForKey:flagKey]) {
            [[LTEventTracker shared] track:abKey properties:@{@"page_name": val ?: @""}];
            [ud setBool:YES forKey:flagKey];
        }
    }

    return [val isEqualToString:@"open"];
}

+ (UIWindowScene *)_activeWindowSceneFromVC:(UIViewController *)vc API_AVAILABLE(ios(13.0)) {
    if (vc.view.window.windowScene) {
        return vc.view.window.windowScene;
    }

    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive &&
            [s isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)s;
        }
    }
    return nil;
}

+ (BOOL)_isWithin24HoursSinceInstall {
    NSTimeInterval ts = [[NSUserDefaults standardUserDefaults] doubleForKey:kASFirstInstallTSKey];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return (now - ts) <= 24.0 * 60.0 * 60.0;
}
@end
