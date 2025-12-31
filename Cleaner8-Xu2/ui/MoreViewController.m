#import "MoreViewController.h"
#import "SetViewController.h"
#import "ASContactsViewController.h"

#pragma mark - UI Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

@interface MoreViewController ()

@property(nonatomic,strong) UIImageView *bgTop;
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

#pragma mark - UI

- (void)buildUI {

    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    [self.view addSubview:self.bgTop];

    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = @"More";
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLab];

    self.contactCard = [self buildCardWithLeftIcon:@"ic_contact_more"
                                         leftText:@"Contact"
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapContact)];

    self.feedbackCard = [self buildCardWithLeftIcon:@"ic_feedback_more"
                                          leftText:@"Feedback"
                                         rightType:@"image"
                                        rightValue:@"ic_todo_small"
                                            action:@selector(tapFeedBack)];

    self.settingCard = [self buildCardWithLeftIcon:@"ic_setting_more"
                                         leftText:@"Setting"
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapSetting)];

    [self.view addSubview:self.contactCard];
    [self.view addSubview:self.feedbackCard];
    [self.view addSubview:self.settingCard];

    [NSLayoutConstraint activateConstraints:@[
        // 背景
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:360],

        [self.titleLab.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:13],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.contactCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:64],
        [self.contactCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.contactCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.feedbackCard.topAnchor constraintEqualToAnchor:self.contactCard.bottomAnchor constant:20],
        [self.feedbackCard.leadingAnchor constraintEqualToAnchor:self.contactCard.leadingAnchor],
        [self.feedbackCard.trailingAnchor constraintEqualToAnchor:self.contactCard.trailingAnchor],

        [self.settingCard.topAnchor constraintEqualToAnchor:self.feedbackCard.bottomAnchor constant:20],
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
    card.layer.cornerRadius = 24;
    card.layer.masksToBounds = NO;

    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    card.layer.shadowOpacity = 1.0;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    card.layer.shadowRadius = 20;

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
    leftLab.font = ASFont(24, UIFontWeightMedium);
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
            [img.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [img.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [img.widthAnchor constraintEqualToConstant:40],
            [img.heightAnchor constraintEqualToConstant:24],
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
            [verLab.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [verLab.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        ]];
    }


    [NSLayoutConstraint activateConstraints:@[
        [leftIconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [leftIconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [leftIconView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-11],
        [leftIconView.widthAnchor constraintEqualToConstant:62],
        [leftIconView.heightAnchor constraintEqualToConstant:42],

        [leftLab.leadingAnchor constraintEqualToAnchor:leftIconView.trailingAnchor constant:6],

        [leftLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:23],
        [leftLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-23],

        [leftLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightView.leadingAnchor constant:-12],
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
