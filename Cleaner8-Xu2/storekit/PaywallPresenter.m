#import "PaywallPresenter.h"
#import <UIKit/UIKit.h>
#import "Cleaner8_Xu2-Swift.h"
#import "PaywallViewController.h"
#import "SubscriptionViewController.h"
#import "LTEventTracker.h"

NSNotificationName const PaywallPresenterStateChanged = @"PaywallPresenterStateChanged";

@interface PaywallPresenter ()
@property (nonatomic, weak) UIViewController *presentedVC;
@property (nonatomic, assign) BOOL isPresenting;

@property (nonatomic, copy) PaywallContinueBlock pendingContinue;
@property (nonatomic, copy) NSString *currentSource;
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
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 栏门页
- (void)showPaywallIfNeededWithSource:(NSString * _Nullable)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[StoreKit2Manager shared] start];

        SubscriptionState state = [StoreKit2Manager shared].state;
        if (state == SubscriptionStateActive) return;

        if (state == SubscriptionStateUnknown) {
            __weak typeof(self) weakSelf = self;
            __block id token = [[NSNotificationCenter defaultCenter]
                addObserverForName:@"subscriptionStateChanged"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification * _Nonnull note) {

                [[NSNotificationCenter defaultCenter] removeObserver:token];
                SubscriptionState st = [StoreKit2Manager shared].state;
                if (st == SubscriptionStateInactive) {
                    [weakSelf showPaywallWithSource:source];
                }
            }];
            return;
        }

        // 已确定是未订阅
        [self showPaywallWithSource:source];
    });
}

- (void)showPaywallWithSource:(NSString * _Nullable)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isPresenting) return;

        UIViewController *top = [self topMostViewController];
        if (!top) return;

        // 不重复弹
        if ([top isKindOfClass:PaywallViewController.class] ||
            [top isKindOfClass:SubscriptionViewController.class] ||
            [top.presentedViewController isKindOfClass:PaywallViewController.class] ||
            [top.presentedViewController isKindOfClass:SubscriptionViewController.class]) {
            return;
        }

        // 还有别的 modal 正在展示时，不抢
        if (top.presentedViewController) return;

        self.isPresenting = YES;

        PaywallViewController *paywall = [PaywallViewController new];
        paywall.modalPresentationStyle = UIModalPresentationFullScreen;

        paywall.source = source;

        self.presentedVC = paywall;

        [top presentViewController:paywall animated:YES completion:^{
            self.isPresenting = NO;
        }];
    });
}

// 订阅页
- (void)showSubscriptionPageWithSource:(NSString * _Nullable)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topMostViewController];
        if (!top) return;

        // 防重复
        if ([top isKindOfClass:SubscriptionViewController.class] ||
            [top.presentedViewController isKindOfClass:SubscriptionViewController.class]) {
            return;
        }

        if (top.presentedViewController) return;

        SubscriptionViewController *vc = [SubscriptionViewController new];
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
        if ([presented isKindOfClass:PaywallViewController.class] ||
            [presented isKindOfClass:SubscriptionViewController.class]) {

            [top dismissViewControllerAnimated:YES completion:^{
                self.presentedVC = nil;
            }];
        } else {
            if ([top isKindOfClass:PaywallViewController.class] ||
                [top isKindOfClass:SubscriptionViewController.class]) {
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
            [self dismissIfPresent];
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
            // 没有 keyWindow 就取第一个
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
        if ([presented isKindOfClass:PaywallViewController.class] ||
            [presented isKindOfClass:SubscriptionViewController.class]) {

            [top dismissViewControllerAnimated:YES completion:^{
                self.presentedVC = nil;
                if (completion) completion();
            }];
            return;
        }

        if ([top isKindOfClass:PaywallViewController.class] ||
            [top isKindOfClass:SubscriptionViewController.class]) {

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
