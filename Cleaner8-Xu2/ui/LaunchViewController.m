#import "LaunchViewController.h"
#import "OnboardingViewController.h"
#import "MainTabBarController.h"
#import "Common.h"
#import <Network/Network.h>

#pragma mark - UI Helpers
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
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static inline UIColor *ASHexRGBA(uint32_t hex) {
    CGFloat r = ((hex >> 24) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat b = ((hex >> 8)  & 0xFF) / 255.0;
    CGFloat a = ( hex        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

@interface ASTopGradientView : UIView
@end

@implementation ASTopGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;

        CAGradientLayer *g = (CAGradientLayer *)self.layer;
        g.startPoint = CGPointMake(0.5, 0.0);
        g.endPoint   = CGPointMake(0.5, 1.0);

        g.colors = @[
            (id)ASHexRGBA(0xE0E0E0FF).CGColor,
            (id)ASHexRGBA(0x008DFF00).CGColor,
        ];
    }
    return self;
}
@end

static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding";

@interface LaunchViewController ()
@property(nonatomic,strong) ASTopGradientView *topGradientView;

@property(nonatomic,strong) UIImageView *logoView;
@property(nonatomic,strong) UILabel *nameLab;
@property(nonatomic,strong) UIView *centerContainer;
@property(nonatomic,strong) NSLayoutConstraint *containerCenterYCons;

@property(nonatomic,assign) BOOL didScheduleJump;
@property(nonatomic,assign) nw_path_monitor_t pathMonitor;
@property(nonatomic,assign) BOOL hasNetwork;

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
    
    if (self.didScheduleJump) return;
    self.didScheduleJump = YES;
    
    // Start the network monitor when the launch screen appears
    [self startNetworkMonitor];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self jumpNext];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ASHexRGBA(0xF6F6F6FF);
    [self buildUI];
}

#pragma mark - Network Monitor
- (void)startNetworkMonitor {
    if (@available(iOS 12.0, *)) {
        if (self.pathMonitor) return;

        self.hasNetwork = YES;

        nw_path_monitor_t m = nw_path_monitor_create();
        self.pathMonitor = m;

        dispatch_queue_t q = dispatch_queue_create("as.net.monitor", DISPATCH_QUEUE_SERIAL);
        nw_path_monitor_set_queue(m, q);

        __weak typeof(self) weakSelf = self;
        nw_path_monitor_set_update_handler(m, ^(nw_path_t  _Nonnull path) {
            BOOL ok = (nw_path_get_status(path) == nw_path_status_satisfied);
            weakSelf.hasNetwork = ok;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf) return;
                if (!ok) {
                    // Handle no network case (show alert or perform other actions)
                }
            });
        });

        nw_path_monitor_start(m);
    }
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
    self.topGradientView = [ASTopGradientView new];
    self.topGradientView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topGradientView];

    [NSLayoutConstraint activateConstraints:@[
        [self.topGradientView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topGradientView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topGradientView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topGradientView.heightAnchor constraintEqualToConstant:SW(402.0)],
    ]];

    self.centerContainer = [UIView new];
    self.centerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.centerContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.centerContainer];
    
    self.centerContainer = [UIView new];
    self.centerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.centerContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.centerContainer];

    self.logoView = [UIImageView new];
    self.logoView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logoView.image = [UIImage imageNamed:@"launch_icon"];
    self.logoView.contentMode = UIViewContentModeScaleAspectFit;
    
    self.logoView.layer.cornerRadius = SW(36.0);
    self.logoView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.logoView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.centerContainer addSubview:self.logoView];

    self.nameLab = [UILabel new];
    self.nameLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLab.text = NSLocalizedString(@"Compressly", nil);
    self.nameLab.textColor = UIColor.blackColor;
    self.nameLab.font = ASFont(34, UIFontWeightMedium);
    self.nameLab.textAlignment = NSTextAlignmentCenter;
    [self.centerContainer addSubview:self.nameLab];

    self.containerCenterYCons =
        [self.centerContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-SW(100)];

    [NSLayoutConstraint activateConstraints:@[
        [self.centerContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.containerCenterYCons,

        [self.logoView.topAnchor constraintEqualToAnchor:self.centerContainer.topAnchor],
        [self.logoView.centerXAnchor constraintEqualToAnchor:self.centerContainer.centerXAnchor],
        [self.logoView.widthAnchor constraintEqualToConstant:SW(150)],
        [self.logoView.heightAnchor constraintEqualToConstant:SW(150)],

        [self.nameLab.topAnchor constraintEqualToAnchor:self.logoView.bottomAnchor constant:SW(20)],
        [self.nameLab.centerXAnchor constraintEqualToAnchor:self.centerContainer.centerXAnchor],
        [self.nameLab.bottomAnchor constraintEqualToAnchor:self.centerContainer.bottomAnchor],
    ]];
}

@end
