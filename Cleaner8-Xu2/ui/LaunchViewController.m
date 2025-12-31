#import "LaunchViewController.h"
#import "OnboardingViewController.h"
#import "MainTabBarController.h"

#pragma mark - UI Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding";

@interface LaunchViewController ()
@property(nonatomic,strong) UIImageView *bgTop;
@property(nonatomic,strong) UIImageView *logoView;
@property(nonatomic,strong) UILabel *nameLab;
@property(nonatomic,strong) UIView *centerContainer;
@property(nonatomic,strong) NSLayoutConstraint *containerCenterYCons;

@property(nonatomic,assign) BOOL didScheduleJump;
@end

@implementation LaunchViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // 防止多次触发
    if (self.didScheduleJump) return;
    self.didScheduleJump = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self jumpNext];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ASRGB(246, 248, 251);
    [self buildUI];
}

#pragma mark - Jump

- (void)jumpNext {
    BOOL done = [[NSUserDefaults standardUserDefaults] boolForKey:kHasCompletedOnboardingKey];

    UIViewController *target = nil;
    if (done) {
        target = [MainTabBarController new];
    } else {
        target = [OnboardingViewController new];
    }

    // 优先用当前 nav
    UINavigationController *nav = self.navigationController;
    if (!nav) {
        // 兜底：从 window root 拿
        UIViewController *root = self.view.window.rootViewController;
        if ([root isKindOfClass:[UINavigationController class]]) {
            nav = (UINavigationController *)root;
        }
    }

    if (nav) {
        [nav setViewControllers:@[target] animated:YES];
    } else {
        self.view.window.rootViewController = target;
    }
}

#pragma mark - UI

- (void)buildUI {

    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    [self.view addSubview:self.bgTop];

    self.centerContainer = [UIView new];
    self.centerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.centerContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.centerContainer];

    self.logoView = [UIImageView new];
    self.logoView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logoView.image = [UIImage imageNamed:@"launch_icon"];
    self.logoView.contentMode = UIViewContentModeScaleAspectFit;
    [self.centerContainer addSubview:self.logoView];

    self.nameLab = [UILabel new];
    self.nameLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLab.text = @"Compressly";
    self.nameLab.textColor = UIColor.blackColor;
    self.nameLab.font = ASFont(34, UIFontWeightMedium);
    self.nameLab.textAlignment = NSTextAlignmentCenter;
    [self.centerContainer addSubview:self.nameLab];

    self.containerCenterYCons =
        [self.centerContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-100];

    [NSLayoutConstraint activateConstraints:@[
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:236],

        [self.centerContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.containerCenterYCons,

        [self.logoView.topAnchor constraintEqualToAnchor:self.centerContainer.topAnchor],
        [self.logoView.centerXAnchor constraintEqualToAnchor:self.centerContainer.centerXAnchor],
        [self.logoView.widthAnchor constraintEqualToConstant:150],
        [self.logoView.heightAnchor constraintEqualToConstant:150],

        [self.nameLab.topAnchor constraintEqualToAnchor:self.logoView.bottomAnchor constant:20],
        [self.nameLab.centerXAnchor constraintEqualToAnchor:self.centerContainer.centerXAnchor],
        [self.nameLab.bottomAnchor constraintEqualToAnchor:self.centerContainer.bottomAnchor],
    ]];
}

@end
