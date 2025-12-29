#import "SceneDelegate.h"
#import "OnboardingViewController.h"
#import "VideoViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
options:(UISceneConnectionOptions *)connectionOptions {

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    BOOL hasCompletedOnboarding =
        [[NSUserDefaults standardUserDefaults]
            boolForKey:@"hasCompletedOnboarding"];

    UIViewController *rootVC;

    if (!hasCompletedOnboarding) {
        NSLog(@"➡️ 显示引导页");
        rootVC = [[OnboardingViewController alloc] init];
    } else {
        NSLog(@"➡️ 显示主界面");
        rootVC = [[VideoViewController alloc] init];
    }

    UINavigationController *rootNav =
        [[UINavigationController alloc] initWithRootViewController:rootVC];
    rootNav.navigationBarHidden = YES;

    self.window.rootViewController = rootNav;
    [self.window makeKeyAndVisible];
}

@end
