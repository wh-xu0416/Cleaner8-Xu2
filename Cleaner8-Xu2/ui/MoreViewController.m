#import "MoreViewController.h"
#import "SetViewController.h"
#import "ASContactsViewController.h"
#import "Common.h"

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

@property (nonatomic, strong) CAGradientLayer *topGradient;
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
    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];
    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0];
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0];

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = NSLocalizedString(@"More", nil);
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLab];

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

    [self.view addSubview:self.contactCard];
    [self.view addSubview:self.feedbackCard];
    [self.view addSubview:self.settingCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLab.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:SW(13)],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.contactCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:SW(64)],
        [self.contactCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(20)],
        [self.contactCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(20)],

        [self.feedbackCard.topAnchor constraintEqualToAnchor:self.contactCard.bottomAnchor constant:SW(20)],
        [self.feedbackCard.leadingAnchor constraintEqualToAnchor:self.contactCard.leadingAnchor],
        [self.feedbackCard.trailingAnchor constraintEqualToAnchor:self.contactCard.trailingAnchor],

        [self.settingCard.topAnchor constraintEqualToAnchor:self.feedbackCard.bottomAnchor constant:SW(20)],
        [self.settingCard.leadingAnchor constraintEqualToAnchor:self.contactCard.leadingAnchor],
        [self.settingCard.trailingAnchor constraintEqualToAnchor:self.contactCard.trailingAnchor],
    ]];
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
        verLab.textColor = ASBlue();                 // #024DFFFF
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
    
}

- (void)tapSetting {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    SetViewController *setViewController = [[SetViewController alloc] init];
    [nav pushViewController:setViewController animated:YES];
}

@end
