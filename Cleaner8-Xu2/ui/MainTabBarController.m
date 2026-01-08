#import "MainTabBarController.h"
#import "ASFloatingTabBar.h"
#import "VideoViewController.h"
#import "SetViewController.h"

@interface MainTabBarController ()
<
UIGestureRecognizerDelegate
>
@property (nonatomic, strong) ASFloatingTabBar *floatingTab;
@end

@implementation MainTabBarController

- (void)presentFlowController:(UIViewController *)vc {

    // 隐藏浮动 Tab
    self.floatingTab.hidden = YES;

    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:vc];

    nav.modalPresentationStyle = UIModalPresentationFullScreen;

    [self presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"UIScreen bounds = %@", NSStringFromCGSize(UIScreen.mainScreen.bounds.size));

    self.viewControllers = @[
        [self navWithVC:[VideoViewController new]    title:@"Home" image:@""],
        [self navWithVC:[SetViewController new]    title:@"Setting" image:@""],
    ];

    self.tabBar.hidden = YES;

    // 创建浮动 tab
    self.floatingTab = [[ASFloatingTabBar alloc] initWithItems:@[
        [ASFloatingTabBarItem itemWithTitle:@"Home" normal:@"ic_video_n"  selected:@"ic_video_s"],
        [ASFloatingTabBarItem itemWithTitle:@"Setting" normal:@"ic_more_n" selected:@"ic_more_s"],
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

    // 恢复系统侧滑返回
    rootNav.interactivePopGestureRecognizer.enabled = YES;
    rootNav.interactivePopGestureRecognizer.delegate = self;
    
    // 只在首页显示浮动 tab
    if (self.selectedIndex == 0) {
        [self.view addSubview:self.floatingTab];  // 首页显示浮动 tab
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // 栈里只有一个 VC（MainTabBarController）时，禁止返回
    return self.navigationController.viewControllers.count > 1;
}

- (void)navigationController:(UINavigationController *)nav
      willShowViewController:(UIViewController *)vc
                    animated:(BOOL)animated {

    BOOL hide = [vc isKindOfClass:VideoViewController.class];
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

    // 保证浮动 tab 在最上层
    [self.view bringSubviewToFront:self.floatingTab];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];

    // 确保浮动 tab 只在首页显示
    if (selectedIndex == 0) {
        [self.view addSubview:self.floatingTab];  // 首页显示浮动 tab
    } else {
        // 在其他页面不隐藏，只是被系统的 tabBar 覆盖
        // 浮动 tab 不会被移除或隐藏
    }
}

- (UINavigationController *)navWithVC:(UIViewController *)vc title:(NSString *)title image:(NSString *)imageName {
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem.title = title;
    nav.tabBarItem.image = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    
    return nav;
}

@end
