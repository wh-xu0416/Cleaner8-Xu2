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
        
        // 弹出过不再弹出
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kOCSystemReviewDidRequestKey]) {
            return;
        }
        
        // 按来源判断是否允许弹出（此处会在远程AB值时触发remote配置打点，默认值不打点）
        if (![self _isReviewAllowedByABForSourceAndTrackIfNeeded:source]) {
            return;
        }
        
        void (^doRequest)(void) = ^{
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kOCSystemReviewDidRequestKey]) {
                return;
            }
            
            // show打点
            [[LTEventTracker shared] track: @"Rate" properties:@{@"position": source ?: @""}];

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
    if (source.length == 0) return YES; // 其它来源不参与 24h 规则

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

    BOOL isPaidRateSource = ([paidSources containsObject:source] ||
                            [source isEqualToString:kABKeyPaidRate]);

    BOOL isSetRateSource  = ([source isEqualToString:@"setting"] ||
                            [source isEqualToString:kABKeySetRate]);

    // 仅 paid_rate_rate 来源：超过时间不允许弹
    if (isPaidRateSource && ![self _isWithin24HoursSinceInstall]) {
        return NO;
    }

    // 其它来源：不走 AB 控制
    if (!isPaidRateSource && !isSetRateSource) {
        return YES;
    }

    NSString *abKey = isPaidRateSource ? kABKeyPaidRate : kABKeySetRate;

    ASABTestManager *ab = [ASABTestManager shared];
    NSString *val = [ab stringForKey:abKey]; // open/close；无缓存默认 close（你现在默认是 close）

    if ([ab isRemoteValueForKey:abKey]) {
        BOOL shouldTrack =
            isPaidRateSource ? [self _isWithin24HoursSinceInstall] : YES;

        if (shouldTrack) {
            NSString *flagKey = ASABTrackedFlagKey(abKey);
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            if (![ud boolForKey:flagKey]) {
                [[LTEventTracker shared] track:abKey properties:@{@"page_name": val ?: @""}];
                [ud setBool:YES forKey:flagKey];
            }
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
