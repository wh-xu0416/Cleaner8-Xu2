#import "MainTabBarController.h"
#import "ASFloatingTabBar.h"
#import "HomeViewController.h"
#import "VideoViewController.h"
#import "SecretViewController.h"
#import "SwipeViewController.h"
#import "MoreViewController.h"
#import "SwipeManager.h"

@interface MainTabBarController ()
<
UIGestureRecognizerDelegate
>
@property (nonatomic, strong) ASFloatingTabBar *floatingTab;
@end

@implementation MainTabBarController

- (void)presentFlowController:(UIViewController *)vc {

    self.floatingTab.hidden = YES;

    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:vc];

    nav.modalPresentationStyle = UIModalPresentationFullScreen;

    [self presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.viewControllers = @[
        [self navWithVC:[HomeViewController new]   title:@"Cleaner" image:@""],
        [self navWithVC:[VideoViewController new]    title:@"Compress" image:@""],
        [self navWithVC:[SwipeViewController new]    title:@"Swipe" image:@""],
        [self navWithVC:[SecretViewController new] title:@"Private" image:@""],
        [self navWithVC:[MoreViewController new]    title:@"More" image:@""],
    ];

    self.tabBar.hidden = YES;

    self.floatingTab = [[ASFloatingTabBar alloc] initWithItems:@[
        [ASFloatingTabBarItem itemWithTitle:@"Cleaner" normal:@"ic_cleaner_n" selected:@"ic_cleaner_s"],
        [ASFloatingTabBarItem itemWithTitle:@"Compress" normal:@"ic_video_n"  selected:@"ic_video_s"],
        [ASFloatingTabBarItem itemWithTitle:@"Swipe" normal:@"ic_swipe_n" selected:@"ic_swipe_s"],
        [ASFloatingTabBarItem itemWithTitle:@"Private" normal:@"ic_private_n" selected:@"ic_private_s"],
        [ASFloatingTabBarItem itemWithTitle:@"More" normal:@"ic_more_n" selected:@"ic_more_s"],
    ]];

    __weak typeof(self) weakSelf = self;
    self.floatingTab.onSelect = ^(NSInteger idx) {
        weakSelf.selectedIndex = idx;
    };
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    UINavigationController *rootNav =
           self.navigationController;

    rootNav.interactivePopGestureRecognizer.enabled = YES;
    rootNav.interactivePopGestureRecognizer.delegate = self;
    
    if (self.selectedIndex == 0) {
        [self.view addSubview:self.floatingTab];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return self.navigationController.viewControllers.count > 1;
}

- (void)navigationController:(UINavigationController *)nav
      willShowViewController:(UIViewController *)vc
                    animated:(BOOL)animated {

    BOOL hide = [vc isKindOfClass:HomeViewController.class];
    [nav setNavigationBarHidden:hide animated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = 70;
    CGFloat side = 15;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    self.floatingTab.frame = CGRectMake(side,
                                        self.view.bounds.size.height - h - bottom,
                                        w - side * 2,
                                        h);

    [self.view bringSubviewToFront:self.floatingTab];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    [self.view addSubview:self.floatingTab];
}

- (UINavigationController *)navWithVC:(UIViewController *)vc title:(NSString *)title image:(NSString *)imageName {
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem.title = title;
    nav.tabBarItem.image = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    
    return nav;
}

@end
