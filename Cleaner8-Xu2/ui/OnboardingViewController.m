#import "OnboardingViewController.h"
#import "MainTabBarController.h"
#import "Common.h"
#import "LTEventTracker.h"
#import <AdSupport/AdSupport.h>
#import "ASTrackingPermission.h"
#import "AppDelegate.h"
#import "PaywallPresenter.h"

@import Lottie;

static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding";
static NSString * const kASATTDidFinishNotification = @"as_att_did_finish";

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) { return UIScreen.mainScreen.bounds.size.width / SWDesignWidth(); }
static inline CGFloat SWScaleY(void) { return UIScreen.mainScreen.bounds.size.height / SWDesignHeight(); }
static inline CGFloat SWScale(void)  { return MIN(SWScaleX(), SWScaleY()); }
static inline CGFloat SW(CGFloat v)  { return round(v * SWScale()); }

static inline UIColor *ASRGBA(uint32_t argb) {
    CGFloat a = ((argb >> 24) & 0xFF) / 255.0;
    CGFloat r = ((argb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((argb >> 8)  & 0xFF) / 255.0;
    CGFloat b = ( argb        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static inline UIFont *ASFont(NSString *name, CGFloat size) {
    UIFont *f = [UIFont fontWithName:name size:SW(size)];
    if (!f) f = [UIFont systemFontOfSize:SW(size) weight:UIFontWeightRegular];
    return f;
}

@interface OnboardingViewController ()
@property(nonatomic,strong) UIView *lottieContainer;
@property(nonatomic,strong) NSLayoutConstraint *lottieCenterYConstraint;

@property(nonatomic,strong) CompatibleAnimationView *lottieView;

@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *descLabel;

@property(nonatomic,strong) UIStackView *dotsStack;
@property(nonatomic,strong) NSMutableArray<UIView *> *dots;

@property(nonatomic,strong) UIButton *continueBtn;

@property(nonatomic,strong) NSArray<NSString *> *jsonPaths;
@property(nonatomic,strong) NSArray<NSString *> *titles;
@property(nonatomic,strong) NSArray<NSString *> *descs;

@property(nonatomic,assign) NSInteger index;
@property(nonatomic,strong) NSMutableSet<NSNumber *> *trackedIndexes;
@property(nonatomic, assign) BOOL as_attTriggered;

@end

@implementation OnboardingViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASRGBA(0xFFF7F7F9);

    self.jsonPaths = @[@"data1", @"data2", @"data3"];

    self.titles = @[
        NSLocalizedString(@"Cleanup Phone Storage",nil),
        NSLocalizedString(@"Photo Space Manage",nil),
        NSLocalizedString(@"Security Center",nil)
    ];
    self.descs = @[
        NSLocalizedString(@"Get rid of what you don't need, free up 80% space",nil),
        NSLocalizedString(@"AI detect and delete duplicate & similar photos",nil),
        NSLocalizedString(@"Protect your photos and keep your data safe",nil)
    ];

    self.index = 0;
    self.trackedIndexes = [NSMutableSet set];

    [self buildUI];
    [self applyPageAtIndex:self.index animated:NO];
}

#pragma mark - UI Construction

- (void)buildUI {
    CompatibleAnimation *first = [self animationForIndex:0];
    if (first) {
        self.lottieView = [[CompatibleAnimationView alloc] initWithCompatibleAnimation:first
                                                        compatibleRenderingEngineOption:CompatibleRenderingEngineOptionMainThread];
    } else {
        self.lottieView = [[CompatibleAnimationView alloc] initWithFrame:CGRectZero];
    }

    self.lottieView.translatesAutoresizingMaskIntoConstraints = NO;
    self.lottieView.contentMode = UIViewContentModeScaleAspectFit;
    self.lottieView.clipsToBounds = YES;
    self.lottieView.loopAnimationCount = -1;
    [self.view addSubview:self.lottieView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.textColor = ASRGBA(0xFF1F1434);
    self.titleLabel.font = ASFont(@"Poppins-Bold", 28);
    [self.view addSubview:self.titleLabel];

    self.descLabel = [UILabel new];
    self.descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.descLabel.textAlignment = NSTextAlignmentCenter;
    self.descLabel.numberOfLines = 0;
    self.descLabel.textColor = ASRGBA(0xFF8F8A98);
    self.descLabel.font = ASFont(@"Poppins-Regular", 20);
    self.descLabel.adjustsFontSizeToFitWidth = YES;
    self.descLabel.minimumScaleFactor = 0.6;
    [self.view addSubview:self.descLabel];

    self.dots = [NSMutableArray array];
    self.dotsStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.dotsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.dotsStack.axis = UILayoutConstraintAxisHorizontal;
    self.dotsStack.alignment = UIStackViewAlignmentCenter;
    self.dotsStack.distribution = UIStackViewDistributionEqualSpacing;
    self.dotsStack.spacing = SW(12);
    [self.view addSubview:self.dotsStack];

    for (NSInteger i = 0; i < 3; i++) {
        UIView *dot = [UIView new];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.layer.cornerRadius = SW(4);
        dot.layer.masksToBounds = YES;
        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:SW(8)],
            [dot.heightAnchor constraintEqualToConstant:SW(8)],
        ]];
        [self.dotsStack addArrangedSubview:dot];
        [self.dots addObject:dot];
    }

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueBtn.backgroundColor = ASRGBA(0xFF014EFE);
    self.continueBtn.layer.cornerRadius = SW(34);
    self.continueBtn.layer.masksToBounds = YES;
    [self.continueBtn setTitle:NSLocalizedString(@"Continue",nil) forState:UIControlStateNormal];
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = ASFont(@"Poppins-Bold", 22);
    [self.continueBtn addTarget:self action:@selector(tapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];

    self.lottieContainer = [UIView new];
    self.lottieContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.lottieContainer.clipsToBounds = YES;
    [self.view addSubview:self.lottieContainer];

    [self.lottieContainer addSubview:self.lottieView];
    self.lottieView.translatesAutoresizingMaskIntoConstraints = NO;
    self.lottieView.clipsToBounds = YES;
    self.lottieView.contentMode = UIViewContentModeScaleAspectFit;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.lottieContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.lottieContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.lottieContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.lottieContainer.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.55],

        [self.lottieView.centerXAnchor constraintEqualToAnchor:self.lottieContainer.centerXAnchor],
    ]];
    self.lottieCenterYConstraint =
        [self.lottieView.centerYAnchor constraintEqualToAnchor:self.lottieContainer.centerYAnchor constant:0];
    self.lottieCenterYConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.lottieView.widthAnchor constraintEqualToAnchor:self.lottieContainer.widthAnchor],
        [self.lottieView.heightAnchor constraintEqualToAnchor:self.lottieContainer.heightAnchor],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.lottieContainer.bottomAnchor constant:SW(30)],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(30)],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(30)],

        [self.descLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:SW(30)],
        [self.descLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(44)],
        [self.descLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(44)],

        [self.dotsStack.topAnchor constraintEqualToAnchor:self.descLabel.bottomAnchor constant:SW(35)],
        [self.dotsStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.continueBtn.topAnchor constraintEqualToAnchor:self.dotsStack.bottomAnchor constant:SW(35)],
        [self.continueBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(38)],
        [self.continueBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(38)],
        [self.continueBtn.heightAnchor constraintEqualToConstant:SW(68)],

        [self.continueBtn.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:0],
    ]];
}

#pragma mark - Actions

- (void)trackGuidePageIfNeededForIndex:(NSInteger)idx {
    if (idx < 0 || idx >= self.jsonPaths.count) return;

    NSNumber *key = @(idx);
    if ([self.trackedIndexes containsObject:key]) return;
    [self.trackedIndexes addObject:key];

    NSString *pageName = [NSString stringWithFormat:@"guide_page_%ld", (long)(idx + 1)];
    [[LTEventTracker shared] track:@"start_page"
                        properties:@{@"page_name": pageName}];
}

- (void)tapContinue {
    if (self.index < self.jsonPaths.count - 1) {
        self.index += 1;
        [self applyPageAtIndex:self.index animated:YES];
    } else {
        [self startExperience];
    }
}

- (void)applyPageAtIndex:(NSInteger)idx animated:(BOOL)animated {
    if (idx < 0 || idx >= self.jsonPaths.count) return;

    [self trackGuidePageIfNeededForIndex:idx];

    if (idx == 1) {
        [self as_triggerATTOnSecondPageIfNeeded];
    }
   
    self.titleLabel.text = self.titles[idx];
    self.descLabel.text  = self.descs[idx];
    [self updateDotsForIndex:idx];

    CompatibleAnimation *anim = [self animationForIndex:idx];
    if (!anim) {
        [self.lottieView stop];
        return;
    }

    void (^startAnim)(void) = ^{
        self.lottieCenterYConstraint.constant = (idx == 2) ? SW(20.0) : 0.0;
        [self.view layoutIfNeeded];

        self.lottieView.compatibleAnimation = anim;
        [self.lottieView reloadImages];
        [self.lottieView play];
    };

    if (animated) {
        [UIView animateWithDuration:0.15 animations:^{
            self.lottieView.alpha = 0.0;
        } completion:^(BOOL finished) {
            startAnim();
            [UIView animateWithDuration:0.15 animations:^{
                self.lottieView.alpha = 1.0;
            }];
        }];
    } else {
        startAnim();
    }
}

- (void)as_triggerATTOnSecondPageIfNeeded {
    if (self.as_attTriggered) return;

    // 只在首次安装（首次启动）时走引导页 ATT
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if (![app isKindOfClass:[AppDelegate class]] || !app.as_isFirstLaunch) {
        return;
    }

    self.as_attTriggered = YES;

    // 给页面切换动画一点时间，避免“弹窗抢动画”
    [ASTrackingPermission requestIfNeededWithDelay:0.35 completion:^(NSInteger status) {

        // 通知 AppDelegate：ATT 已完成（用于触发 AppsFlyer start）
        [[NSNotificationCenter defaultCenter] postNotificationName:kASATTDidFinishNotification
                                                            object:nil
                                                          userInfo:@{@"status": @(status)}];
    }];
}

- (void)updateDotsForIndex:(NSInteger)idx {
    for (NSInteger i = 0; i < self.dots.count; i++) {
        UIView *dot = self.dots[i];
        if (i == idx) {
            dot.backgroundColor = ASRGBA(0xFF014EFE);
            dot.alpha = 1.0;
        } else {
            dot.backgroundColor = ASRGBA(0xFF8F8A98);
            dot.alpha = 0.2454;
        }
    }
}

#pragma mark - Lottie Helpers

- (CompatibleAnimation *)animationForIndex:(NSInteger)idx {
    if (idx < 0 || idx >= self.jsonPaths.count) return nil;
    NSString *name = self.jsonPaths[idx];

    CompatibleAnimation *anim = [[CompatibleAnimation alloc] initWithName:name
                                                             subdirectory:nil
                                                                   bundle:[NSBundle mainBundle]];
    return anim;
}

#pragma mark - Finish

- (void)enterMainTabBar {
    MainTabBarController *main = [MainTabBarController new];

    UIWindow *window = self.view.window;
    if (self.navigationController) {
        [self.navigationController setViewControllers:@[main] animated:NO];
    } else {
        window.rootViewController = main;
        [UIView transitionWithView:window
                          duration:0.3
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:nil
                        completion:nil];
    }
}

- (void)startExperience {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasCompletedOnboardingKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    __weak typeof(self) weakSelf = self;
    [[PaywallPresenter shared] showPaywallIfNeededWithSource:@"guide" completion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self enterMainTabBar];
    }];
}

@end
