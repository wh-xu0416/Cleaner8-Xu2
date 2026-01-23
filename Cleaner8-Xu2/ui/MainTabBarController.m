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
#import "LTEventTracker.h"

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

#pragma mark - Placeholder VC (用于识别未加载的 tab)
@interface SWTabPlaceholderViewController : UIViewController
@end
@implementation SWTabPlaceholderViewController
@end

@interface MainTabBarController ()
<
UIGestureRecognizerDelegate,
UINavigationControllerDelegate
>
@property (nonatomic, strong) ASFloatingTabBar *floatingTab;
@property (nonatomic, strong) NSMutableArray<UINavigationController *> *tabNavs;
@property (nonatomic, strong) NSArray<NSString *> *tabTitles;
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

    self.tabTitles = @[
        NSLocalizedString(@"Cleaner", nil),
        NSLocalizedString(@"Swipe", nil),
        NSLocalizedString(@"Compress", nil),
        NSLocalizedString(@"Private", nil),
        NSLocalizedString(@"More", nil),
    ];

    self.tabNavs = [NSMutableArray arrayWithCapacity:self.tabTitles.count];
    for (NSInteger i = 0; i < self.tabTitles.count; i++) {
        SWTabPlaceholderViewController *placeholder = [SWTabPlaceholderViewController new];
        placeholder.view.backgroundColor = UIColor.systemBackgroundColor;
        placeholder.title = self.tabTitles[i];

        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:placeholder];
        nav.navigationBarHidden = YES;
        nav.tabBarItem.title = self.tabTitles[i];
        nav.delegate = self;

        [self.tabNavs addObject:nav];
    }

    self.viewControllers = self.tabNavs;
    self.tabBar.hidden = YES;

    self.floatingTab = [[ASFloatingTabBar alloc] initWithItems:@[
        [ASFloatingTabBarItem itemWithTitle:self.tabTitles[0] normal:@"ic_cleaner_n" selected:@"ic_cleaner_s"],
        [ASFloatingTabBarItem itemWithTitle:self.tabTitles[1] normal:@"ic_swipe_n" selected:@"ic_swipe_s"],
        [ASFloatingTabBarItem itemWithTitle:self.tabTitles[2] normal:@"ic_video_n"  selected:@"ic_video_s"],
        [ASFloatingTabBarItem itemWithTitle:self.tabTitles[3] normal:@"ic_private_n" selected:@"ic_private_s"],
        [ASFloatingTabBarItem itemWithTitle:self.tabTitles[4] normal:@"ic_more_n" selected:@"ic_more_s"],
    ]];

    __weak typeof(self) weakSelf = self;
    self.floatingTab.onSelect = ^(NSInteger idx) {
        if (weakSelf.selectedIndex == idx) { return; }

        [weakSelf sw_ensureTabLoadedAtIndex:idx];

        weakSelf.selectedIndex = idx;

        switch (idx) {
            case 0:
                [[LTEventTracker shared] track:@"function_enter" properties:@{@"function_name": @"clean_page"}];
                break;
            case 1:
                [[LTEventTracker shared] track:@"function_enter" properties:@{@"function_name": @"swipe_page"}];
                break;
            case 2:
                [[LTEventTracker shared] track:@"function_enter" properties:@{@"function_name": @"compress_page"}];
                break;
            case 3:
                [[LTEventTracker shared] track:@"function_enter" properties:@{@"function_name": @"private_page"}];
                break;
            case 4:
                [[LTEventTracker shared] track:@"function_enter" properties:@{@"function_name": @"more_page"}];
                break;
            default:
                break;
        }
    };

    [self.view addSubview:self.floatingTab];
    [self.view bringSubviewToFront:self.floatingTab];

    [self sw_ensureTabLoadedAtIndex:self.selectedIndex];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[PaywallPresenter shared] showPaywallIfNeededWithSource:@"guide"];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    UINavigationController *rootNav = self.navigationController;
    rootNav.interactivePopGestureRecognizer.enabled = YES;
    rootNav.interactivePopGestureRecognizer.delegate = self;

    [self.view bringSubviewToFront:self.floatingTab];
}

#pragma mark - Lazy Load

- (void)sw_ensureTabLoadedAtIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.tabNavs.count) { return; }

    UINavigationController *nav = self.tabNavs[idx];
    UIViewController *root = nav.viewControllers.firstObject;
    if (!root) { return; }

    if (![root isKindOfClass:SWTabPlaceholderViewController.class]) { return; }

    UIViewController *realVC = [self sw_realViewControllerForIndex:idx];
    if (!realVC) { return; }

    if (idx < (NSInteger)self.tabTitles.count) {
        realVC.title = self.tabTitles[idx];
    }

    [nav setViewControllers:@[realVC] animated:NO];
    nav.navigationBarHidden = YES;

    BOOL hide = [realVC isKindOfClass:HomeViewController.class];
    [nav setNavigationBarHidden:hide animated:NO];
}

- (UIViewController *)sw_realViewControllerForIndex:(NSInteger)idx {
    switch (idx) {
        case 0: return [HomeViewController new];
        case 1: return [SwipeViewController new];
        case 2: return [VideoViewController new];
        case 3: return [PrivateViewController new];
        case 4: return [MoreViewController new];
        default: return nil;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return self.navigationController.viewControllers.count > 1;
}

#pragma mark - UINavigationControllerDelegate
- (void)navigationController:(UINavigationController *)nav
      willShowViewController:(UIViewController *)vc
                    animated:(BOOL)animated {

    BOOL isRoot = (vc == nav.viewControllers.firstObject);
    [nav setNavigationBarHidden:isRoot animated:animated];
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
    [self sw_ensureTabLoadedAtIndex:(NSInteger)selectedIndex];

    [super setSelectedIndex:selectedIndex];

    self.floatingTab.hidden = NO;
    [self.view bringSubviewToFront:self.floatingTab];
}

@end
