#import "MainTabBarController.h"
#import "ASFloatingTabBar.h"
#import "HomeViewController.h"
#import "CutViewController.h"
#import "SecretViewController.h"
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

    // 设置底部四个页面
    self.viewControllers = @[
        [self navWithVC:[HomeViewController new]   title:@"首页" image:@"Frame 383"],
        [self navWithVC:[CutViewController new]    title:@"切换" image:@"Frame 383"],
        [self navWithVC:[SecretViewController new] title:@"私密" image:@"Frame 383"],
        [self navWithVC:[SetViewController new]    title:@"设置" image:@"Frame 383"],
    ];

    self.tabBar.hidden = YES;  // 隐藏系统的 tabBar

    // 创建浮动 tab
    self.floatingTab = [[ASFloatingTabBar alloc] initWithItems:@[
        [ASFloatingTabBarItem itemWithTitle:@"首页" normal:@"tab_home_n" selected:@"tab_home_s"],
        [ASFloatingTabBarItem itemWithTitle:@"切换" normal:@"tab_cut_n"  selected:@"tab_cut_s"],
        [ASFloatingTabBarItem itemWithTitle:@"私密" normal:@"tab_secret_n" selected:@"tab_secret_s"],
        [ASFloatingTabBarItem itemWithTitle:@"设置" normal:@"tab_set_n" selected:@"tab_set_s"],
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = 64;
    CGFloat side = 20;
    CGFloat bottom = 20 + self.view.safeAreaInsets.bottom;

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
