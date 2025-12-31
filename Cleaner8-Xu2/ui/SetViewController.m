#import "SetViewController.h"

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

@interface SetViewController ()

@property(nonatomic,strong) UIImageView *bgTop;
@property(nonatomic,strong) UILabel *titleLab;

@property(nonatomic,strong) UIControl *termsCard;
@property(nonatomic,strong) UIControl *privacyCard;
@property(nonatomic,strong) UIControl *versionCard;

@end

@implementation SetViewController

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

    // 顶部背景
    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    [self.view addSubview:self.bgTop];

    // 标题
    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = @"Setting";
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLab];

    // 三个卡片
    self.termsCard = [self buildCardWithLeftText:@"Terms of User"
                                      rightType:@"image"
                                     rightValue:@"ic_todo_small"
                                         action:@selector(tapTerms)];

    self.privacyCard = [self buildCardWithLeftText:@"Privacy Policy"
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapPrivacy)];

    NSString *ver = [self appVersionString]; // 真实版本号
    self.versionCard = [self buildCardWithLeftText:@"Version"
                                         rightType:@"version"
                                        rightValue:ver
                                            action:nil];

    [self.view addSubview:self.termsCard];
    [self.view addSubview:self.privacyCard];
    [self.view addSubview:self.versionCard];

    [NSLayoutConstraint activateConstraints:@[
        // 背景
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:360],

        // 标题
        [self.titleLab.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:13],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // 卡片：左右 20，占满；纵向排列；间距 20
        [self.termsCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:64],
        [self.termsCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.termsCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.privacyCard.topAnchor constraintEqualToAnchor:self.termsCard.bottomAnchor constant:20],
        [self.privacyCard.leadingAnchor constraintEqualToAnchor:self.termsCard.leadingAnchor],
        [self.privacyCard.trailingAnchor constraintEqualToAnchor:self.termsCard.trailingAnchor],

        [self.versionCard.topAnchor constraintEqualToAnchor:self.privacyCard.bottomAnchor constant:20],
        [self.versionCard.leadingAnchor constraintEqualToAnchor:self.termsCard.leadingAnchor],
        [self.versionCard.trailingAnchor constraintEqualToAnchor:self.termsCard.trailingAnchor],
    ]];
}

#pragma mark - Card Builder

/// rightType: @"image" / @"version"
- (UIControl *)buildCardWithLeftText:(NSString *)leftText
                           rightType:(NSString *)rightType
                          rightValue:(NSString *)rightValue
                              action:(SEL _Nullable)sel {

    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 24;
    card.layer.masksToBounds = NO;

    // 阴影（跟你 HOME row 风格接近）
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    card.layer.shadowOpacity = 1.0;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    card.layer.shadowRadius = 20;

    if (sel) [card addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];

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
    } else { // version
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

    // 内边距：左 30，右 20，上下 23
    // 用 top/bottom 约束把卡片高度撑起来（不写死高度）
    [NSLayoutConstraint activateConstraints:@[
        [leftLab.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:30],
        [leftLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:23],
        [leftLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-23],

        // 左文右内容间距（避免重叠）
        [leftLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightView.leadingAnchor constant:-12],
    ]];

    return card;
}

#pragma mark - Version

- (NSString *)appVersionString {
    NSString *shortVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    // 如果你也想带 build：把下面这一行拼上去即可
    // NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    // return [NSString stringWithFormat:@"%@ (%@)", shortVer ?: @"", build ?: @""];
    return shortVer ?: @"";
}

#pragma mark - Actions

- (void)tapTerms {
    [self as_openInBrowser:@"https://www.baidu.com"];
}

- (void)tapPrivacy {
    [self as_openInBrowser:@"https://www.baidu.com"];
}

- (void)as_openInBrowser:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url) return;

    if (!url.scheme.length) {
        url = [NSURL URLWithString:[@"https://" stringByAppendingString:urlString]];
        if (!url) return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = UIApplication.sharedApplication;
        if ([app canOpenURL:url]) {
            [app openURL:url options:@{} completionHandler:nil];
        }
    });
}

@end
