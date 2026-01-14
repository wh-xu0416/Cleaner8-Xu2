#import "OnboardingViewController.h"
#import "MainTabBarController.h"
#import "Common.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <AdSupport/AdSupport.h>
#import "ASTrackingPermission.h"

static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding";
static NSString * const kHasRequestedATTKey = @"hasRequestedATT";

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
#pragma mark - UI Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return SWFontS(size, weight);
}

@interface OnboardingViewController ()
@property(nonatomic,strong) UIImageView *bgImageView;
@property(nonatomic,strong) UIButton *continueBtn;

@property(nonatomic,strong) NSArray<NSString *> *images;
@property(nonatomic,assign) NSInteger index;
@end

@implementation OnboardingViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;

    self.images = @[@"sp_1", @"sp_2", @"sp_3"];
    self.index = 0;

    [self buildUI];
    [self applyImageAtIndex:self.index animated:NO];
}

#pragma mark - UI

- (void)buildUI {

    self.bgImageView = [UIImageView new];
    self.bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    self.bgImageView.userInteractionEnabled = YES;
    [self.view addSubview:self.bgImageView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapToNext)];
    [self.bgImageView addGestureRecognizer:tap];

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueBtn.backgroundColor = ASRGB(43, 127, 255); // #2B7FFF
    self.continueBtn.layer.cornerRadius = SW(20);
    self.continueBtn.layer.masksToBounds = YES;

    [self.continueBtn setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = ASFont(18, UIFontWeightSemibold);

    [self.continueBtn addTarget:self action:@selector(tapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];

    [NSLayoutConstraint activateConstraints:@[
        // bg full screen
        [self.bgImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // button
        [self.continueBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(45)],
        [self.continueBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(45)],
        [self.continueBtn.heightAnchor constraintEqualToConstant:SW(56)],
        [self.continueBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-SW(113)],
    ]];
}

#pragma mark - Actions

- (void)tapToNext {
    if (self.index < self.images.count - 1) {
        self.index += 1;
        [self applyImageAtIndex:self.index animated:YES];
    }
}

- (void)tapContinue {
    if (self.index == 0) {
        [ASTrackingPermission requestIfNeededWithDelay:0.0 completion:nil];
    }
    
    if (self.index < self.images.count - 1) {
        self.index += 1;
        [self applyImageAtIndex:self.index animated:YES];
    } else {
        [self startExperience];
    }
}

- (void)applyImageAtIndex:(NSInteger)idx animated:(BOOL)animated {
    if (idx < 0 || idx >= self.images.count) return;

    UIImage *img = [UIImage imageNamed:self.images[idx]];
    if (!animated) {
        self.bgImageView.image = img;
        return;
    }

    [UIView transitionWithView:self.bgImageView
                      duration:0.25
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        self.bgImageView.image = img;
    } completion:nil];
}

- (void)requestATTIfNeededOnFirstPage {
    if (self.index != 0) return;

    if (@available(iOS 14, *)) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kHasRequestedATTKey]) return;

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasRequestedATTKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        ATTrackingManagerAuthorizationStatus status = ATTrackingManager.trackingAuthorizationStatus;
        if (status != ATTrackingManagerAuthorizationStatusNotDetermined) return;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                // status: Authorized / Denied / Restricted / NotDetermined
            }];
        });
    }
}

#pragma mark - Enter Main

- (void)startExperience {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasCompletedOnboardingKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    MainTabBarController *main = [MainTabBarController new];

    UINavigationController *nav = self.navigationController;
    if (!nav) {
        UIViewController *root = self.view.window.rootViewController;
        if ([root isKindOfClass:[UINavigationController class]]) {
            nav = (UINavigationController *)root;
        }
    }

    if (nav) {
        [nav setViewControllers:@[main] animated:YES];
    } else {
        self.view.window.rootViewController = main;
    }
}

@end
