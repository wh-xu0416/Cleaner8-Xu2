#import "MoreViewController.h"
#import "SetViewController.h"
#import "ASContactsViewController.h"
#import "Common.h"
#import "PaywallPresenter.h"
#import "ASReviewHelper.h"

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
static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return SWFontS(size,weight);
}

@interface MoreViewController ()
@property(nonatomic,strong) NSLayoutConstraint *contactTopToProCst;
@property(nonatomic,strong) NSLayoutConstraint *contactTopToTitleCst;

@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UIView *contentView;

@property(nonatomic,strong) UIControl *proCard;

@property(nonatomic,strong) CAGradientLayer *topGradient;
@property(nonatomic,strong) UILabel *titleLab;

@property(nonatomic,strong) UIControl *contactCard;
@property(nonatomic,strong) UIControl *feedbackCard;
@property(nonatomic,strong) UIControl *settingCard;

@end

@implementation MoreViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ASRGB(246, 248, 251);
    [self buildUI];

    [[StoreKit2Manager shared] start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSubscriptionStateChanged)
                                                 name:@"subscriptionStateChanged"
                                               object:nil];

    [self updateProCardVisibility];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat gradientH = safeTop + SW(402.0);
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);
}

#pragma mark - UI

- (void)buildUI {
    self.view.backgroundColor = ASRGB(246, 246, 246);

    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = ASRGB(224, 224, 224);
    UIColor *c2 = [UIColor colorWithRed:0/255.0 green:141/255.0 blue:255/255.0 alpha:0.0];
    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = NO;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.backgroundColor = UIColor.clearColor;
    [self.scrollView addSubview:self.contentView];

    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],

            [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
            [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        ]];
    }

    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = NSLocalizedString(@"More", nil);
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLab];

    self.proCard = [self buildProCard];

    [self.contentView addSubview:self.proCard];

    self.contactCard = [self buildCardWithLeftIcon:@"ic_contact_more"
                                         leftText:NSLocalizedString(@"Contact", nil)
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapContact)];

    self.feedbackCard = [self buildCardWithLeftIcon:@"ic_feedback_more"
                                          leftText:NSLocalizedString(@"Feedback", nil)
                                         rightType:@"image"
                                        rightValue:@"ic_todo_small"
                                            action:@selector(tapFeedBack)];

    self.settingCard = [self buildCardWithLeftIcon:@"ic_setting_more"
                                         leftText:NSLocalizedString(@"Setting", nil)
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapSetting)];

    [self.contentView addSubview:self.contactCard];
    [self.contentView addSubview:self.feedbackCard];
    [self.contentView addSubview:self.settingCard];

    self.contactTopToProCst =
        [self.contactCard.topAnchor constraintEqualToAnchor:self.proCard.bottomAnchor constant:SW(40)];

    self.contactTopToTitleCst =
        [self.contactCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:SW(40)];

    self.contactTopToProCst.active = YES;
    self.contactTopToTitleCst.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLab.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:SW(13)],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],

        [self.proCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:SW(40)],
        [self.proCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:SW(20)],
        [self.proCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-SW(20)],

        [self.contactCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:SW(20)],
        [self.contactCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-SW(20)],

        [self.feedbackCard.topAnchor constraintEqualToAnchor:self.contactCard.bottomAnchor constant:SW(20)],
        [self.feedbackCard.leadingAnchor constraintEqualToAnchor:self.contactCard.leadingAnchor],
        [self.feedbackCard.trailingAnchor constraintEqualToAnchor:self.contactCard.trailingAnchor],

        [self.settingCard.topAnchor constraintEqualToAnchor:self.feedbackCard.bottomAnchor constant:SW(20)],
        [self.settingCard.leadingAnchor constraintEqualToAnchor:self.contactCard.leadingAnchor],
        [self.settingCard.trailingAnchor constraintEqualToAnchor:self.contactCard.trailingAnchor],

        [self.settingCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-SW(100)],
    ]];
}

- (void)onSubscriptionStateChanged {
    [self updateProCardVisibility];
}

- (void)updateProCardVisibility {
    dispatch_async(dispatch_get_main_queue(), ^{
        SubscriptionState state = [StoreKit2Manager shared].state;

        if (state == SubscriptionStateUnknown) {
            self.proCard.hidden = NO;
            self.contactTopToProCst.active = YES;
            self.contactTopToTitleCst.active = NO;
            [self.view layoutIfNeeded];
            return;
        }

        self.proCard.hidden = [PaywallPresenter shared].isProActive;;
        self.contactTopToProCst.active = ![PaywallPresenter shared].isProActive;;
        self.contactTopToTitleCst.active = [PaywallPresenter shared].isProActive;;

        [self.view layoutIfNeeded];
    });
}

#pragma mark - Pro Card

- (UIControl *)buildProCard {
    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    
    [card addTarget:self action:@selector(tapPro) forControlEvents:UIControlEventTouchUpInside];
    card.layer.cornerRadius = SW(16);
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    card.layer.shadowOpacity = 1.0;
    card.layer.shadowOffset = CGSizeMake(0, SW(10));
    card.layer.shadowRadius = SW(20);

    UIView *bgView = [UIView new];
    bgView.translatesAutoresizingMaskIntoConstraints = NO;
    bgView.layer.cornerRadius = SW(16);
    bgView.layer.masksToBounds = YES;
    bgView.userInteractionEnabled = NO;
    [card addSubview:bgView];

    [NSLayoutConstraint activateConstraints:@[
        [bgView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [bgView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [bgView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [bgView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint   = CGPointMake(1, 0.5);
    gradient.colors = @[
        (id)ASRGB(111, 71, 225).CGColor,   // #6F47E1
        (id)ASRGB(46,  59, 240).CGColor    // #2E3BF0
    ];
    gradient.cornerRadius = SW(16);
    [bgView.layer insertSublayer:gradient atIndex:0];

    bgView.layer.needsDisplayOnBoundsChange = YES;
    gradient.frame = CGRectMake(0, 0, 1, 1);

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.userInteractionEnabled = NO;
    [bgView addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:bgView.topAnchor constant:SW(20)],
        [content.bottomAnchor constraintEqualToAnchor:bgView.bottomAnchor constant:-SW(20)],
        [content.leadingAnchor constraintEqualToAnchor:bgView.leadingAnchor constant:SW(30)],
        [content.trailingAnchor constraintEqualToAnchor:bgView.trailingAnchor constant:-SW(27)],
    ]];

    UIImageView *vipIcon = [UIImageView new];
    vipIcon.translatesAutoresizingMaskIntoConstraints = NO;
    vipIcon.image = [UIImage imageNamed:@"ic_vip"];
    vipIcon.contentMode = UIViewContentModeScaleAspectFit;
    [content addSubview:vipIcon];

    UILabel *proLab = [UILabel new];
    proLab.translatesAutoresizingMaskIntoConstraints = NO;
    proLab.text = NSLocalizedString(@"Pro",nil);
    proLab.textColor = UIColor.whiteColor;
    proLab.font = ASFont(36, UIFontWeightSemibold);
    [content addSubview:proLab];

    UIImageView *todoWhite = [UIImageView new];
    todoWhite.translatesAutoresizingMaskIntoConstraints = NO;
    todoWhite.image = [UIImage imageNamed:@"ic_todo_white"];
    todoWhite.contentMode = UIViewContentModeScaleAspectFit;
    [content addSubview:todoWhite];

    UILabel *subLab = [UILabel new];
    subLab.translatesAutoresizingMaskIntoConstraints = NO;
    subLab.text = NSLocalizedString(@"Unlock all Features",nil);
    subLab.textColor = UIColor.whiteColor;
    subLab.font = ASFont(20, UIFontWeightRegular);
    [content addSubview:subLab];

    [NSLayoutConstraint activateConstraints:@[
        [vipIcon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [vipIcon.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [vipIcon.widthAnchor constraintEqualToConstant:SW(60)],
        [vipIcon.heightAnchor constraintEqualToConstant:SW(60)],

        [proLab.leadingAnchor constraintEqualToAnchor:vipIcon.trailingAnchor constant:SW(15)],
        [proLab.topAnchor constraintEqualToAnchor:content.topAnchor],

        [todoWhite.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [todoWhite.centerYAnchor constraintEqualToAnchor:proLab.centerYAnchor],
        [todoWhite.widthAnchor constraintEqualToConstant:SW(60)],
        [todoWhite.heightAnchor constraintEqualToConstant:SW(36)],

        [subLab.leadingAnchor constraintEqualToAnchor:proLab.leadingAnchor],
        [subLab.topAnchor constraintEqualToAnchor:proLab.bottomAnchor constant:SW(5)],
        [subLab.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        gradient.frame = bgView.bounds;
        [CATransaction commit];
    });
    vipIcon.userInteractionEnabled = NO;
    proLab.userInteractionEnabled = NO;
    todoWhite.userInteractionEnabled = NO;
    subLab.userInteractionEnabled = NO;
    return card;
}

#pragma mark - Card Builder

- (UIControl *)buildCardWithLeftIcon:(NSString *)leftIcon
                            leftText:(NSString *)leftText
                           rightType:(NSString *)rightType
                          rightValue:(NSString *)rightValue
                              action:(SEL _Nullable)sel {

    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = SW(16);
    card.layer.masksToBounds = NO;

    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    card.layer.shadowOpacity = 1.0;
    card.layer.shadowOffset = CGSizeMake(0, SW(10));
    card.layer.shadowRadius = SW(20);

    if (sel) [card addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];

    UIImageView *leftIconView = [UIImageView new];
    leftIconView.translatesAutoresizingMaskIntoConstraints = NO;
    leftIconView.image = [[UIImage imageNamed:leftIcon ?: @""] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    leftIconView.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:leftIconView];

    UILabel *leftLab = [UILabel new];
    leftLab.translatesAutoresizingMaskIntoConstraints = NO;
    leftLab.text = leftText;
    leftLab.textColor = UIColor.blackColor;
    leftLab.font = ASFont(24, UIFontWeightRegular);
    [card addSubview:leftLab];

    UIView *rightView = nil;

    if ([rightType isEqualToString:@"image"]) {
        UIImageView *img = [UIImageView new];
        img.translatesAutoresizingMaskIntoConstraints = NO;
        img.image = [[UIImage imageNamed:rightValue] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        img.contentMode = UIViewContentModeScaleAspectFit;
        [card addSubview:img];
        rightView = img;

        [NSLayoutConstraint activateConstraints:@[
            [img.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SW(20)],
            [img.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [img.widthAnchor constraintEqualToConstant:SW(40)],
            [img.heightAnchor constraintEqualToConstant:SW(24)],
        ]];
    } else {
        UILabel *verLab = [UILabel new];
        verLab.translatesAutoresizingMaskIntoConstraints = NO;
        verLab.text = rightValue ?: @"";
        verLab.textColor = ASBlue();
        verLab.font = ASFont(24, UIFontWeightRegular);
        verLab.textAlignment = NSTextAlignmentRight;
        [card addSubview:verLab];
        rightView = verLab;

        [NSLayoutConstraint activateConstraints:@[
            [verLab.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SW(20)],
            [verLab.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [leftIconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:SW(16)],
        [leftIconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:SW(22)],
        [leftIconView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SW(11)],
        [leftIconView.widthAnchor constraintEqualToConstant:SW(62)],
        [leftIconView.heightAnchor constraintEqualToConstant:SW(42)],

        [leftLab.leadingAnchor constraintEqualToAnchor:leftIconView.trailingAnchor constant:SW(6)],
        [leftLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:SW(23)],
        [leftLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SW(23)],
        [leftLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightView.leadingAnchor constant:-SW(12)],
    ]];

    return card;
}

#pragma mark - Actions

- (void)tapContact {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    ASContactsViewController *contactsViewController = [[ASContactsViewController alloc] init];
    [nav pushViewController:contactsViewController animated:YES];
}

- (void)tapFeedBack {
    [ASReviewHelper requestReviewOnceFromViewController:self source:AppConstants.abKeySetRateRate];
}

- (void)tapSetting {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    SetViewController *setViewController = [[SetViewController alloc] init];
    [nav pushViewController:setViewController animated:YES];
}

- (void)tapPro {
    [[PaywallPresenter shared] showSubscriptionPageWithSource:@"more"];
}

@end

