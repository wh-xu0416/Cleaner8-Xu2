#import "SceneDelegate.h"
#import "MainTabBarController.h"
#import "OnboardingViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
options:(UISceneConnectionOptions *)connectionOptions {

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    BOOL hasCompletedOnboarding =
        [[NSUserDefaults standardUserDefaults]
            boolForKey:@"hasCompletedOnboarding"];

    if (!hasCompletedOnboarding) {
        NSLog(@"➡️ 显示引导页");
        self.window.rootViewController =
            [[OnboardingViewController alloc] init];
    } else {
        NSLog(@"➡️ 显示主界面");
        self.window.rootViewController =
            [[MainTabBarController alloc] init];
    }

    [self.window makeKeyAndVisible];
}

@end
