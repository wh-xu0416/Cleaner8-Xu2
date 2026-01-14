#import "SetViewController.h"
#import "Common.h"
#import "UIViewController+ASPrivateBackground.h"

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
    return SWFontS(size, weight);
}

@interface SetViewController ()

@property(nonatomic,strong) UILabel *titleLab;

@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIView *content;

@property(nonatomic,strong) UIControl *termsCard;
@property(nonatomic,strong) UIControl *privacyCard;
@property(nonatomic,strong) UIControl *versionCard;
@property(nonatomic,strong) UIButton *backBtn;

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
    [self as_applyPrivateBackground];

    self.scroll = [UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.backgroundColor = UIColor.clearColor;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.content = [UIView new];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content.backgroundColor = UIColor.clearColor;
    [self.scroll addSubview:self.content];

    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = NSLocalizedString(@"Setting", nil);
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.titleLab];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];
    self.backBtn.adjustsImageWhenHighlighted = NO;
    [self.backBtn addTarget:self action:@selector(tapBack) forControlEvents:UIControlEventTouchUpInside];
    [self.content addSubview:self.backBtn];

    self.termsCard = [self buildCardWithLeftText:NSLocalizedString(@"Terms of User", nil)
                                      rightType:@"image"
                                     rightValue:@"ic_todo_small"
                                         action:@selector(tapTerms)];

    self.privacyCard = [self buildCardWithLeftText:NSLocalizedString(@"Privacy Policy", nil)
                                        rightType:@"image"
                                       rightValue:@"ic_todo_small"
                                           action:@selector(tapPrivacy)];

    NSString *ver = [self appVersionString];
    self.versionCard = [self buildCardWithLeftText:NSLocalizedString(@"Version", nil)
                                         rightType:@"version"
                                        rightValue:ver
                                            action:nil];

    [self.content addSubview:self.termsCard];
    [self.content addSubview:self.privacyCard];
    [self.content addSubview:self.versionCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.content.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [self.content.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [self.content.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.content.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor],

        [self.titleLab.topAnchor constraintEqualToAnchor:self.content.safeAreaLayoutGuide.topAnchor constant:SW(13)],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.content.centerXAnchor],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:SW(20)],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:self.titleLab.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:SW(24)],
        [self.backBtn.heightAnchor constraintEqualToConstant:SW(24)],

        [self.termsCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:SW(64)],
        [self.termsCard.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:SW(20)],
        [self.termsCard.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-SW(20)],

        [self.privacyCard.topAnchor constraintEqualToAnchor:self.termsCard.bottomAnchor constant:SW(20)],
        [self.privacyCard.leadingAnchor constraintEqualToAnchor:self.termsCard.leadingAnchor],
        [self.privacyCard.trailingAnchor constraintEqualToAnchor:self.termsCard.trailingAnchor],

        [self.versionCard.topAnchor constraintEqualToAnchor:self.privacyCard.bottomAnchor constant:SW(20)],
        [self.versionCard.leadingAnchor constraintEqualToAnchor:self.termsCard.leadingAnchor],
        [self.versionCard.trailingAnchor constraintEqualToAnchor:self.termsCard.trailingAnchor],

        [self.versionCard.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor constant:-SW(34)],
    ]];
}

#pragma mark - Card Builder

- (UIControl *)buildCardWithLeftText:(NSString *)leftText
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
            [verLab.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SW(20)],
            [verLab.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [leftLab.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:SW(30)],
        [leftLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:SW(23)],
        [leftLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SW(23)],

        [leftLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightView.leadingAnchor constant:-SW(12)],
    ]];

    return card;
}

#pragma mark - Version

- (NSString *)appVersionString {
    NSString *shortVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return shortVer ?: @"";
}

#pragma mark - Actions

- (void)tapBack {
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

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
