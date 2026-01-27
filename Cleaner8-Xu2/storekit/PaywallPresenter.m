#import "PaywallPresenter.h"
#import <UIKit/UIKit.h>
#import "Cleaner8_Xu2-Swift.h"
#import "SubscriptionViewController.h"
#import "LTEventTracker.h"

static NSString * const kPaywallDidDismissNotification = @"PaywallDidDismissNotification";

NSNotificationName const PaywallPresenterStateChanged = @"PaywallPresenterStateChanged";

@interface PaywallPresenter ()
@property (nonatomic, weak) UIViewController *presentedVC;
@property (nonatomic, assign) BOOL isPresenting;

@property (nonatomic, copy) PaywallContinueBlock pendingContinue;
@property (nonatomic, copy) NSString *currentSource;
@property (nonatomic, assign) BOOL autoPaywallAttemptedThisSession;
@end

@implementation PaywallPresenter

+ (instancetype)shared {
    static PaywallPresenter *ins;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [PaywallPresenter new];
    });
    return ins;
}

- (void)start {
    [[StoreKit2Manager shared] start];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSubscriptionChanged)
                                                 name:@"subscriptionStateChanged"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaywallDidDismiss:)
                                                 name:kPaywallDidDismissNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)firePendingContinueIfAny {
    PaywallContinueBlock block = self.pendingContinue;
    self.pendingContinue = nil;
    if (block) block();
}

- (void)onPaywallDidDismiss:(NSNotification *)note {
    self.presentedVC = nil;
    [self firePendingContinueIfAny];
}

// 栏门页 未订阅弹出,只弹一次
- (void)showPaywallIfNeededWithSource:(NSString * _Nullable)source {
    [self showPaywallIfNeededWithSource:source completion:nil];
}

- (void)showPaywallIfNeededWithSource:(NSString * _Nullable)source
                           completion:(PaywallContinueBlock _Nullable)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        SubscriptionState state = [StoreKit2Manager shared].state;

        // 已订阅：直接放行
        if (state == SubscriptionStateActive) {
            if (completion) completion();
            return;
        }

        // 本次启动已经尝试弹过自动 paywall：不再弹，直接放行（满足“启动页调用过，其他页面不再弹”）
        if (self.autoPaywallAttemptedThisSession) {
            if (completion) completion();
            return;
        }

        // 记录 completion（只用于这次调用，比如 onboarding 进首页）
        self.pendingContinue = completion;

        // unknown：先刷新订阅状态，等一下再决定
        if (state == SubscriptionStateUnknown) {
            [[StoreKit2Manager shared] forceRefreshSubscriptionState];

            __weak typeof(self) weakSelf = self;
            __block id token = [[NSNotificationCenter defaultCenter]
                addObserverForName:@"subscriptionStateChanged"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *note) {

                [[NSNotificationCenter defaultCenter] removeObserver:token];
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;

                if ([StoreKit2Manager shared].state != SubscriptionStateActive) {
                    [self showPaywallWithSource:source];
                } else {
                    [self firePendingContinueIfAny];
                }
            }];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;

                if ([StoreKit2Manager shared].state == SubscriptionStateUnknown) {
                    [[NSNotificationCenter defaultCenter] removeObserver:token];
                    [self showPaywallWithSource:source];
                }
            });

            return;
        }

        // inactive：直接弹
        [self showPaywallWithSource:source];
    });
}

- (void)showPaywallWithSource:(NSString * _Nullable)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isPresenting) return;

        UIViewController *top = [self topMostViewController];
        if (!top) return;

        if ([top isKindOfClass:SubscriptionViewController.class] ||
            [top.presentedViewController isKindOfClass:SubscriptionViewController.class]) {
            return;
        }

        if (top.presentedViewController) return;

        self.isPresenting = YES;

        self.autoPaywallAttemptedThisSession = YES;

        SubscriptionPaywallMode mode = AppConstants.paywallGateModeRaw;
        SubscriptionViewController *vc = [[SubscriptionViewController alloc] initWithMode:mode];

        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        vc.source = source;

        self.presentedVC = vc;

        [top presentViewController:vc animated:YES completion:^{
            self.isPresenting = NO;
        }];
    });
}

// 订阅列表页
- (void)showSubscriptionPageWithSource:(NSString * _Nullable)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topMostViewController];
        if (!top) return;

        if ([top isKindOfClass:SubscriptionViewController.class] ||
            [top.presentedViewController isKindOfClass:SubscriptionViewController.class]) {
            return;
        }

        if (top.presentedViewController) return;

        SubscriptionPaywallMode mode = AppConstants.subscriptionPageModeRaw;
        SubscriptionViewController *vc = [[SubscriptionViewController alloc] initWithMode:mode];

        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        vc.source = source;

        self.presentedVC = vc;
        [top presentViewController:vc animated:YES completion:nil];
    });
}

- (void)dismissIfPresent {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topMostViewController];
        if (!top) return;

        UIViewController *presented = top.presentedViewController;
        if ([presented isKindOfClass:SubscriptionViewController.class]) {

            [top dismissViewControllerAnimated:YES completion:^{
                self.presentedVC = nil;
            }];
        } else {
            if ([top isKindOfClass:SubscriptionViewController.class]) {
                [top dismissViewControllerAnimated:YES completion:^{
                    self.presentedVC = nil;
                }];
            }
        }
    });
}

#pragma mark - Notifications

- (void)onSubscriptionChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        SubscriptionState state = [StoreKit2Manager shared].state;

        [[NSNotificationCenter defaultCenter] postNotificationName:PaywallPresenterStateChanged object:nil];

        if (state == SubscriptionStateActive) {
            __weak typeof(self) weakSelf = self;
            [self dismissIfPresentWithCompletion:^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                [self firePendingContinueIfAny];
            }];
        }
    });
}

- (SubscriptionState)subscriptionState {
    return [StoreKit2Manager shared].state;
}

- (BOOL)isProActive {
    return [StoreKit2Manager shared].state == SubscriptionStateActive;
}

#pragma mark - Top VC Helper

- (UIWindow *)keyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            return ws.windows.firstObject;
        }
        return nil;
    } else {
        return UIApplication.sharedApplication.keyWindow;
    }
}

- (UIViewController *)topMostViewController {
    UIWindow *window = [self keyWindow];
    UIViewController *vc = window.rootViewController;
    if (!vc) return nil;

    while (1) {
        if (vc.presentedViewController) {
            vc = vc.presentedViewController;
            continue;
        }
        if ([vc isKindOfClass:UINavigationController.class]) {
            vc = ((UINavigationController *)vc).visibleViewController ?: vc;
            continue;
        }
        if ([vc isKindOfClass:UITabBarController.class]) {
            vc = ((UITabBarController *)vc).selectedViewController ?: vc;
            continue;
        }
        break;
    }
    return vc;
}

- (void)dismissIfPresentWithCompletion:(void(^ _Nullable)(void))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topMostViewController];
        if (!top) { if (completion) completion(); return; }

        UIViewController *presented = top.presentedViewController;
        if ([presented isKindOfClass:SubscriptionViewController.class]) {

            [top dismissViewControllerAnimated:YES completion:^{
                self.presentedVC = nil;
                if (completion) completion();
            }];
            return;
        }

        if ([top isKindOfClass:SubscriptionViewController.class]) {

            [top dismissViewControllerAnimated:YES completion:^{
                self.presentedVC = nil;
                if (completion) completion();
            }];
            return;
        }

        if (completion) completion();
    });
}

@end
