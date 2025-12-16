//
//  MainTabBarController.m
//  Cleaner8-Xu2
//
//  Created by 徐文豪 on 2025/12/15.
//
#import "MainTabBarController.h"

#import "HomeViewController.h"
#import "CutViewController.h"
#import "SecretViewController.h"
#import "SetViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation MainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.viewControllers = @[
        [self navWithVC:[HomeViewController new]
                 title:@"首页"
                 image:@"Frame 383"],

        [self navWithVC:[CutViewController new]
                 title:@"切换"
                 image:@"Frame 383"],

        [self navWithVC:[SecretViewController new]
                 title:@"私密"
                 image:@"Frame 383"],

        [self navWithVC:[SetViewController new]
                 title:@"设置"
                 image:@"Frame 383"]
    ];
}

- (UINavigationController *)navWithVC:(UIViewController *)vc
                                title:(NSString *)title
                                image:(NSString *)imageName {

    vc.title = title;

    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:vc];

    nav.tabBarItem.title = title;
    nav.tabBarItem.image =
        [[UIImage imageNamed:imageName]
         imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

    return nav;
}

@end

NS_ASSUME_NONNULL_END
