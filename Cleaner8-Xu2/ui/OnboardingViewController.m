#import "OnboardingViewController.h"
#import "MainTabBarController.h"
#import "Common.h"

static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding";

#pragma mark - UI Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
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
    self.continueBtn.layer.cornerRadius = 20;
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
        [self.continueBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:45],
        [self.continueBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-45],
        [self.continueBtn.heightAnchor constraintEqualToConstant:56],
        [self.continueBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-113],
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
