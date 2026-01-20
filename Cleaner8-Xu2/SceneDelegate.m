#import "SceneDelegate.h"
#import "OnboardingViewController.h"
#import "VideoViewController.h"
#import "MainTabBarController.h"
#import "LaunchViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    
    UIViewController *rootVC;
    
    rootVC = [[LaunchViewController alloc] init];
    
    UINavigationController *rootNav =
    [[UINavigationController alloc] initWithRootViewController:rootVC];
    rootNav.navigationBarHidden = YES;
    
    self.window.rootViewController = rootNav;
    [self.window makeKeyAndVisible];
    
}

@end
