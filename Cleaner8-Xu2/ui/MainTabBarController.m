#import "MainTabBarController.h"
#import "ASFloatingTabBar.h"
#import "HomeViewController.h"
#import "VideoViewController.h"
#import "PrivateViewController.h"
#import "SwipeViewController.h"
#import "MoreViewController.h"
#import "Common.h"
#import "SwipeManager.h"
#import "PaywallPresenter.h"

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat SWScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}
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
        [self navWithVC:[HomeViewController new]   title:NSLocalizedString(@"Cleaner", nil) image:@""],
        [self navWithVC:[VideoViewController new]  title:NSLocalizedString(@"Compress", nil) image:@""],
        [self navWithVC:[SwipeViewController new]  title:NSLocalizedString(@"Swipe", nil) image:@""],
        [self navWithVC:[PrivateViewController new]title:NSLocalizedString(@"Private", nil) image:@""],
        [self navWithVC:[MoreViewController new]   title:NSLocalizedString(@"More", nil) image:@""],
    ];

    self.tabBar.hidden = YES;

    self.floatingTab = [[ASFloatingTabBar alloc] initWithItems:@[
        [ASFloatingTabBarItem itemWithTitle:NSLocalizedString(@"Cleaner", nil) normal:@"ic_cleaner_n" selected:@"ic_cleaner_s"],
        [ASFloatingTabBarItem itemWithTitle:NSLocalizedString(@"Compress", nil) normal:@"ic_video_n"  selected:@"ic_video_s"],
        [ASFloatingTabBarItem itemWithTitle:NSLocalizedString(@"Swipe", nil) normal:@"ic_swipe_n" selected:@"ic_swipe_s"],
        [ASFloatingTabBarItem itemWithTitle:NSLocalizedString(@"Private", nil) normal:@"ic_private_n" selected:@"ic_private_s"],
        [ASFloatingTabBarItem itemWithTitle:NSLocalizedString(@"More", nil) normal:@"ic_more_n" selected:@"ic_more_s"],
    ]];

    __weak typeof(self) weakSelf = self;
    self.floatingTab.onSelect = ^(NSInteger idx) {
        weakSelf.selectedIndex = idx;
    };

    [self.view addSubview:self.floatingTab];
    [self.view bringSubviewToFront:self.floatingTab];
    
    [[PaywallPresenter shared] showPaywallIfNeededWithSource:@"home"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    UINavigationController *rootNav = self.navigationController;
    rootNav.interactivePopGestureRecognizer.enabled = YES;
    rootNav.interactivePopGestureRecognizer.delegate = self;

    [self.view bringSubviewToFront:self.floatingTab];
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
    CGFloat h = SW(80);
    CGFloat side = SW(15);
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    self.floatingTab.frame = CGRectMake(side,
                                        self.view.bounds.size.height - h - bottom,
                                        w - side * 2,
                                        h);

    [self.view bringSubviewToFront:self.floatingTab];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];

    self.floatingTab.hidden = NO;
    [self.view bringSubviewToFront:self.floatingTab];
}

- (UINavigationController *)navWithVC:(UIViewController *)vc title:(NSString *)title image:(NSString *)imageName {
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem.title = title;
    nav.tabBarItem.image = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    
    return nav;
}

@end
