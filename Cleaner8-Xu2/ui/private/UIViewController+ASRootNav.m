#import "UIViewController+ASRootNav.h"

@implementation UIViewController (ASRootNav)

- (UINavigationController *)as_rootNav {
    UIViewController *root = self.view.window.rootViewController;
    if ([root isKindOfClass:UINavigationController.class]) return (UINavigationController *)root;

    if ([root isKindOfClass:UITabBarController.class]) {
        UIViewController *sel = ((UITabBarController *)root).selectedViewController;
        if ([sel isKindOfClass:UINavigationController.class]) return (UINavigationController *)sel;
    }
    return nil;
}

@end
