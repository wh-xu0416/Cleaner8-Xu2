#import "SubscriptionViewController.h"
#import "Cleaner8_Xu2-Swift.h"
#import "LTEventTracker.h"

static inline NSString *L(NSString *key) { return NSLocalizedString(key, nil); }
static inline NSString *LF(NSString *key, ...) {
    va_list args; va_start(args, key);
    NSString *format = NSLocalizedString(key, nil);
    NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args); return str;
}

#pragma mark - Helpers

static inline UIColor *HexColor(NSString *hex) {
    NSString *s = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    unsigned int a=255, r=0, g=0, b=0;
    if (s.length == 6) {
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&r];
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(2, 2)]] scanHexInt:&g];
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(4, 2)]] scanHexInt:&b];
    } else if (s.length == 8) {
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&a];
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(2, 2)]] scanHexInt:&r];
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(4, 2)]] scanHexInt:&g];
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(6, 2)]] scanHexInt:&b];
    }
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a/255.0];
}

static inline UIFont *PoppinsFont(NSString *name, CGFloat size, UIFontWeight fallbackWeight) {
    UIFont *f = [UIFont fontWithName:name size:size];
    if (!f) f = [UIFont systemFontOfSize:size weight:fallbackWeight];
    return f;
}

static inline NSAttributedString *UnderlinedText(NSString *text, UIColor *color, UIFont *font) {
    if (!text) text = @"";
    NSDictionary *attrs = @{
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSForegroundColorAttributeName: color ?: UIColor.blackColor,
        NSFontAttributeName: font ?: [UIFont systemFontOfSize:12]
    };
    return [[NSAttributedString alloc] initWithString:text attributes:attrs];
}

static inline id SafeKVC(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; }
    @catch (__unused NSException *e) { return nil; }
}

#pragma mark - Feature Icon View

@interface SubFeatureView : UIView
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UIView *badge;
@property(nonatomic,strong) UILabel *badgeLab;
@property(nonatomic,strong) UILabel *titleLab;
- (void)setBadgeNumber:(NSInteger)num;
@end

@implementation SubFeatureView

- (instancetype)initWithIcon:(NSString *)iconName title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.iconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:iconName]];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:self.iconView];

    self.badge = [[UIView alloc] init];
    self.badge.translatesAutoresizingMaskIntoConstraints = NO;
    self.badge.backgroundColor = HexColor(@"#FFFF2E2E");
    self.badge.layer.cornerRadius = 43/2.0;
    self.badge.clipsToBounds = YES;
    [self addSubview:self.badge];

    self.badgeLab = [[UILabel alloc] init];
    self.badgeLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeLab.textAlignment = NSTextAlignmentCenter;
    self.badgeLab.textColor = UIColor.whiteColor;
    self.badgeLab.font = PoppinsFont(@"Poppins-Regular", 18, UIFontWeightRegular);
    [self.badge addSubview:self.badgeLab];

    self.titleLab = [[UILabel alloc] init];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    self.titleLab.textColor = HexColor(@"#FF1F1434");
    self.titleLab.font = PoppinsFont(@"Poppins-SemiBold", 14, UIFontWeightSemibold);
    self.titleLab.text = title ?: @"";
    [self addSubview:self.titleLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:85],
        [self.iconView.heightAnchor constraintEqualToConstant:85],

        [self.badge.widthAnchor constraintEqualToConstant:43],
        [self.badge.heightAnchor constraintEqualToConstant:43],
        [self.badge.centerXAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:-6],
        [self.badge.centerYAnchor constraintEqualToAnchor:self.iconView.topAnchor constant:4],

        [self.badgeLab.centerXAnchor constraintEqualToAnchor:self.badge.centerXAnchor],
        [self.badgeLab.centerYAnchor constraintEqualToAnchor:self.badge.centerYAnchor],

        [self.titleLab.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:0],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.titleLab.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (void)setBadgeNumber:(NSInteger)num {
    self.badgeLab.text = [NSString stringWithFormat:@"%ld", (long)num];
}

@end

#pragma mark - Plan Item View

@interface SubPlanItemView : UIControl
@property(nonatomic,assign) BOOL showPopularAlways;

@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UILabel *nameLab;
@property(nonatomic,strong) UILabel *priceLab;
@property(nonatomic,strong) UIImageView *radioImg;

@property(nonatomic,strong) UIView *popularTip;
@property(nonatomic,strong) UIImageView *popularTipImg;
@property(nonatomic,strong) UILabel *popularTipLab;

@property(nonatomic,assign) BOOL isPopular;
- (void)applySelectedStyle:(BOOL)selected;
@end

@implementation SubPlanItemView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = UIColor.clearColor;

    self.card = [[UIView alloc] init];
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = 12;
    self.card.layer.borderColor = HexColor(@"#FFACC5FF").CGColor;
    self.card.layer.borderWidth = 1;
    self.card.backgroundColor = UIColor.whiteColor;
    self.card.userInteractionEnabled = NO;
    [self addSubview:self.card];

    self.nameLab = [[UILabel alloc] init];
    self.nameLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLab.textColor = HexColor(@"#FF1F1434");
    self.nameLab.font = PoppinsFont(@"Poppins-Bold", 16, UIFontWeightBold);
    self.nameLab.userInteractionEnabled = NO;
    [self.card addSubview:self.nameLab];

    self.priceLab = [[UILabel alloc] init];
    self.priceLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.priceLab.textColor = HexColor(@"#FF999999");
    self.priceLab.font = PoppinsFont(@"Poppins-Regular", 12, UIFontWeightRegular);
    self.priceLab.userInteractionEnabled = NO;
    [self.card addSubview:self.priceLab];

    self.radioImg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_sub_select"]];
    self.radioImg.translatesAutoresizingMaskIntoConstraints = NO;
    self.radioImg.contentMode = UIViewContentModeScaleAspectFit;
    self.radioImg.userInteractionEnabled = NO;
    [self.card addSubview:self.radioImg];

    self.popularTip = [[UIView alloc] init];
    self.popularTip.translatesAutoresizingMaskIntoConstraints = NO;
    self.popularTip.hidden = YES;
    self.popularTip.userInteractionEnabled = NO;
    [self addSubview:self.popularTip];

    self.popularTipImg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_sub_check_tip"]];
    self.popularTipImg.translatesAutoresizingMaskIntoConstraints = NO;
    self.popularTipImg.contentMode = UIViewContentModeScaleAspectFit;
    self.popularTipImg.userInteractionEnabled = NO;
    [self.popularTip addSubview:self.popularTipImg];

    self.popularTipLab = [[UILabel alloc] init];
    self.popularTipLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.popularTipLab.textAlignment = NSTextAlignmentCenter;
    self.popularTipLab.textColor = UIColor.whiteColor;
    self.popularTipLab.font = PoppinsFont(@"Poppins-Bold", 12, UIFontWeightBold);
    self.popularTipLab.adjustsFontSizeToFitWidth = YES;
    self.popularTipLab.minimumScaleFactor = 0.7;
    self.popularTipLab.userInteractionEnabled = NO;
    self.popularTipLab.text = L(@"subscription.most_popular");
    if ([self.popularTipLab.text isEqualToString:@"subscription.most_popular"]) self.popularTipLab.text = @"Most Popular";
    [self.popularTip addSubview:self.popularTipLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.card.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.card.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.heightAnchor constraintEqualToConstant:70],

        [self.nameLab.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:15],
        [self.nameLab.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:15],
        [self.nameLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.radioImg.leadingAnchor constant:-12],

        [self.priceLab.topAnchor constraintEqualToAnchor:self.nameLab.bottomAnchor constant:5],
        [self.priceLab.leadingAnchor constraintEqualToAnchor:self.nameLab.leadingAnchor],
        [self.priceLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.radioImg.leadingAnchor constant:-12],
        [self.priceLab.bottomAnchor constraintLessThanOrEqualToAnchor:self.card.bottomAnchor constant:-15],

        [self.radioImg.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
        [self.radioImg.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-22],
        [self.radioImg.widthAnchor constraintEqualToConstant:22],
        [self.radioImg.heightAnchor constraintEqualToConstant:22],

        [self.popularTip.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [self.popularTip.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:-8],
        [self.popularTip.widthAnchor constraintEqualToConstant:116],
        [self.popularTip.heightAnchor constraintEqualToConstant:24],

        [self.popularTipImg.topAnchor constraintEqualToAnchor:self.popularTip.topAnchor],
        [self.popularTipImg.leadingAnchor constraintEqualToAnchor:self.popularTip.leadingAnchor],
        [self.popularTipImg.trailingAnchor constraintEqualToAnchor:self.popularTip.trailingAnchor],
        [self.popularTipImg.bottomAnchor constraintEqualToAnchor:self.popularTip.bottomAnchor],

        [self.popularTipLab.topAnchor constraintEqualToAnchor:self.popularTip.topAnchor constant:2],
        [self.popularTipLab.bottomAnchor constraintEqualToAnchor:self.popularTip.bottomAnchor constant:-4],
        [self.popularTipLab.leadingAnchor constraintEqualToAnchor:self.popularTip.leadingAnchor constant:17],
        [self.popularTipLab.trailingAnchor constraintEqualToAnchor:self.popularTip.trailingAnchor constant:-17],
    ]];

    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    return [self pointInside:point withEvent:event] ? self : nil;
}

- (void)applySelectedStyle:(BOOL)selected {
    if (selected) {
        self.card.layer.borderColor = HexColor(@"#FF014EFE").CGColor;
        self.card.layer.borderWidth = 2;
        self.radioImg.image = [UIImage imageNamed:@"ic_sub_selected"];
    } else {
        self.card.layer.borderColor = HexColor(@"#FFACC5FF").CGColor;
        self.card.layer.borderWidth = 1;
        self.radioImg.image = [UIImage imageNamed:@"ic_sub_select"];
    }

    if (self.isPopular) {
        self.popularTip.hidden = self.showPopularAlways ? NO : !selected;
    } else {
        self.popularTip.hidden = YES;
    }
}

@end

#pragma mark - SubscriptionViewController

@interface SubscriptionViewController ()
@property(nonatomic,strong) UILabel *trialHintLab;
@property(nonatomic,strong) NSLayoutConstraint *continueTopToPlansStack;
@property(nonatomic,strong) NSLayoutConstraint *continueTopToTrialHint;

@property(nonatomic,copy) NSString *productsSignature;
@property(nonatomic,assign) BOOL gateBuilt;

@property(nonatomic,assign) SubProgressPhase progressPhase;
@property(nonatomic,assign) CFTimeInterval phaseStartTime;
@property(nonatomic,assign) CGFloat moveDuration;
@property(nonatomic,assign) CGFloat fadeDuration;

@property(nonatomic,assign) SubscriptionPaywallMode paywallMode;

@property(nonatomic,strong) UIView *gateBadgeView;
@property(nonatomic,strong) UILabel *gateBadgeLab;
@property(nonatomic,strong) CAGradientLayer *gateBadgeGradient;

@property(nonatomic,strong) NSLayoutConstraint *titleTopToSafe;
@property(nonatomic,strong) NSLayoutConstraint *titleTopToGateBadge;

@property(nonatomic,strong) UIButton *backBtn;
@property(nonatomic,strong) UILabel *titleLab;

@property(nonatomic,strong) UIStackView *featureRow;
@property(nonatomic,strong) SubFeatureView *photosFeature;
@property(nonatomic,strong) SubFeatureView *icloudFeature;

@property(nonatomic,strong) UIView *progressTrack;
@property(nonatomic,strong) UIView *progressFill;
@property(nonatomic,strong) NSLayoutConstraint *progressFillW;

@property(nonatomic,strong) UIStackView *usedRow;
@property(nonatomic,strong) UILabel *usedPercentLab;
@property(nonatomic,strong) UILabel *usedOutOfLab;
@property(nonatomic,strong) UILabel *usedWordLab;
@property(nonatomic,strong) NSLayoutConstraint *usedPercentW;

@property(nonatomic,strong) UIStackView *plansStack;
@property(nonatomic,strong) UIButton *continueBtn;
@property(nonatomic,strong) UILabel *autoRenewLab;

@property(nonatomic,strong) UIStackView *bottomLinks;
@property(nonatomic,strong) UIButton *termsBtn;
@property(nonatomic,strong) UIButton *privacyBtn;
@property(nonatomic,strong) UIButton *restoreBtn;

@property(nonatomic,assign) BOOL allowDismiss;

@property(nonatomic,strong) NSArray<SK2ProductModel *> *products;
@property(nonatomic,copy) NSString *selectedProductID;
@property(nonatomic,assign) NSInteger selectedIndex;
@property(nonatomic,assign) NSInteger popularIndex;

@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,assign) CFTimeInterval animStart;
@property(nonatomic,assign) CGFloat animFrom;
@property(nonatomic,assign) CGFloat animTo;
@property(nonatomic,assign) CGFloat progress;
@property(nonatomic,assign) CGFloat trackWidth;
@end

@implementation SubscriptionViewController

- (instancetype)initWithMode:(SubscriptionPaywallMode)mode {
    if (self = [super init]) {
        _paywallMode = mode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HexColor(@"#FFF7F7F9");

    self.allowDismiss = YES;
    self.selectedIndex = 0;
    self.popularIndex = 0;

    [[StoreKit2Manager shared] start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onStoreSnapshotChanged:)
                                                 name:@"storeSnapshotChanged"
                                               object:nil];

    [self buildUI];
    
    if (self.paywallMode != SubscriptionPaywallModeWeekly &&
        self.paywallMode != SubscriptionPaywallModeYearly &&
        self.paywallMode != SubscriptionPaywallModeGateWeekly &&
        self.paywallMode != SubscriptionPaywallModeGateYearly) {
        self.paywallMode = SubscriptionPaywallModeWeekly;
    }

    [self applyPaywallModeUI];
    
    if (self.paywallMode == SubscriptionPaywallModeGateWeekly || self.paywallMode == SubscriptionPaywallModeGateYearly) {
        [self clearPlansUI];
        [self rebuildGateUI];
        self.gateBuilt = YES;
    }
    
    [self render];
    [[StoreKit2Manager shared] uploadIAPIdentifiersOnEnterPaywall];
}

- (void)dealloc {
    [self stopLoopAnimation];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startLoopAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopLoopAnimation];
}

- (void)onStoreSnapshotChanged:(NSNotification *)note {
    if ([NSThread isMainThread]) {
        [self render];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];
        });
    }
}

#pragma mark - UI

- (UIButton *)linkButtonWithTitle:(NSString *)t {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    UIColor *c = HexColor(@"#FFBFC2CD");
    UIFont *f = PoppinsFont(@"Poppins-Regular", 12, UIFontWeightRegular);
    [b setAttributedTitle:UnderlinedText(t, c, f) forState:UIControlStateNormal];
    return b;
}

- (void)buildUI {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backBtn setImage:[UIImage imageNamed:@"ic_back_sub"] forState:UIControlStateNormal];
    self.backBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.backBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.backBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.backBtn.imageEdgeInsets = UIEdgeInsetsMake(16, 0, 16, 32);
    [self.backBtn addTarget:self action:@selector(tapBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backBtn];

    self.gateBadgeView = [[UIView alloc] init];
    self.gateBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gateBadgeView.layer.cornerRadius = 20;
    self.gateBadgeView.clipsToBounds = YES;
    self.gateBadgeView.hidden = YES;
    [self.view addSubview:self.gateBadgeView];

    self.gateBadgeGradient = [CAGradientLayer layer];
    self.gateBadgeGradient.startPoint = CGPointMake(0.5, 0);
    self.gateBadgeGradient.endPoint   = CGPointMake(0.5, 1);
    self.gateBadgeGradient.colors = @[
        (id)HexColor(@"#FF4566FF").CGColor,
        (id)HexColor(@"#FF3FADFF").CGColor
    ];
    [self.gateBadgeView.layer insertSublayer:self.gateBadgeGradient atIndex:0];

    self.gateBadgeLab = [[UILabel alloc] init];
    self.gateBadgeLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.gateBadgeLab.textColor = UIColor.whiteColor;
    self.gateBadgeLab.font = PoppinsFont(@"Poppins-Bold", 26, UIFontWeightBold);
    self.gateBadgeLab.text = @"Free Up";
    [self.gateBadgeView addSubview:self.gateBadgeLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.gateBadgeView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:42],
        [self.gateBadgeView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.gateBadgeLab.leadingAnchor constraintEqualToAnchor:self.gateBadgeView.leadingAnchor constant:20],
        [self.gateBadgeLab.trailingAnchor constraintEqualToAnchor:self.gateBadgeView.trailingAnchor constant:-20],
        [self.gateBadgeLab.topAnchor constraintEqualToAnchor:self.gateBadgeView.topAnchor constant:10],
        [self.gateBadgeLab.bottomAnchor constraintEqualToAnchor:self.gateBadgeView.bottomAnchor constant:-10],
    ]];

    self.titleLab = [[UILabel alloc] init];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    self.titleLab.numberOfLines = 0;
    self.titleLab.lineBreakMode = NSLineBreakByWordWrapping;
    self.titleLab.adjustsFontSizeToFitWidth = NO;

    [self.titleLab setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                  forAxis:UILayoutConstraintAxisVertical];
    [self.titleLab setContentHuggingPriority:UILayoutPriorityRequired
                                     forAxis:UILayoutConstraintAxisVertical];

    self.titleLab.textColor = HexColor(@"#FF1F1434");
    self.titleLab.font = PoppinsFont(@"Poppins-Bold", 36, UIFontWeightBold);
    self.titleLab.text = L(@"subscription.unlock_unlimited_access");
    if ([self.titleLab.text isEqualToString:@"subscription.unlock_unlimited_access"]) self.titleLab.text = @"Unlock Unlimited Access";
    
    NSString *text = self.titleLab.text ?: @"";
    UIFont *font = self.titleLab.font ?: [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = self.titleLab.textAlignment;
    ps.minimumLineHeight = 40;
    ps.maximumLineHeight = 40;

    CGFloat baselineOffset = (40.0 - font.lineHeight) / 4.0;

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: self.titleLab.textColor ?: UIColor.blackColor,
        NSParagraphStyleAttributeName: ps,
        NSBaselineOffsetAttributeName: @(baselineOffset)
    };

    self.titleLab.attributedText = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    [self.view addSubview:self.titleLab];

    self.featureRow = [[UIStackView alloc] init];
    self.featureRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.featureRow.axis = UILayoutConstraintAxisHorizontal;
    self.featureRow.alignment = UIStackViewAlignmentTop;
    self.featureRow.distribution = UIStackViewDistributionFill;
    self.featureRow.spacing = 65;
    [self.view addSubview:self.featureRow];

    NSString *photosTitle = L(@"subscription.photos");
    if ([photosTitle isEqualToString:@"subscription.photos"]) photosTitle = @"photos";
    NSString *icloudTitle = L(@"subscription.icloud");
    if ([icloudTitle isEqualToString:@"subscription.icloud"]) icloudTitle = @"icloud";

    self.photosFeature = [[SubFeatureView alloc] initWithIcon:@"ic_sub_photos" title:photosTitle];
    self.icloudFeature  = [[SubFeatureView alloc] initWithIcon:@"ic_sub_icloud" title:icloudTitle];

    [self.featureRow addArrangedSubview:self.photosFeature];
    [self.featureRow addArrangedSubview:self.icloudFeature];

    [self.photosFeature.widthAnchor constraintEqualToConstant:85].active = YES;
    [self.icloudFeature.widthAnchor constraintEqualToConstant:85].active = YES;

    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTrack.backgroundColor = HexColor(@"#FFE2E2E4");
    self.progressTrack.layer.cornerRadius = 13.5;
    self.progressTrack.clipsToBounds = YES;
    [self.view addSubview:self.progressTrack];

    self.progressFill = [[UIView alloc] init];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFill.layer.cornerRadius = 13.5;
    self.progressFill.clipsToBounds = YES;
    [self.progressTrack addSubview:self.progressFill];

    self.usedRow = [[UIStackView alloc] init];
    self.usedRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedRow.axis = UILayoutConstraintAxisHorizontal;
    self.usedRow.alignment = UIStackViewAlignmentCenter;
    self.usedRow.distribution = UIStackViewDistributionFill;
    self.usedRow.spacing = 6;
    [self.view addSubview:self.usedRow];

    self.usedPercentLab = [[UILabel alloc] init];
    self.usedPercentLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedPercentLab.textAlignment = NSTextAlignmentRight;
    self.usedPercentLab.font = PoppinsFont(@"Poppins-SemiBold", 20, UIFontWeightSemibold);

    self.usedOutOfLab = [[UILabel alloc] init];
    self.usedOutOfLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedOutOfLab.font = PoppinsFont(@"Poppins-SemiBold", 16, UIFontWeightSemibold);
    self.usedOutOfLab.textColor = HexColor(@"#FF606060");

    self.usedWordLab = [[UILabel alloc] init];
    self.usedWordLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedWordLab.font = PoppinsFont(@"Poppins-SemiBold", 16, UIFontWeightSemibold);

    [self.usedRow addArrangedSubview:self.usedPercentLab];
    [self.usedRow addArrangedSubview:self.usedOutOfLab];
    [self.usedRow addArrangedSubview:self.usedWordLab];

    CGFloat w = ceil([@"100 %" sizeWithAttributes:@{NSFontAttributeName: self.usedPercentLab.font}].width);
    self.usedPercentW = [self.usedPercentLab.widthAnchor constraintEqualToConstant:w];
    self.usedPercentW.active = YES;

    self.plansStack = [[UIStackView alloc] init];
    self.plansStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.plansStack.axis = UILayoutConstraintAxisVertical;
    self.plansStack.spacing = 20;
    [self.view addSubview:self.plansStack];

    self.trialHintLab = [[UILabel alloc] init];
    self.trialHintLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.trialHintLab.textAlignment = NSTextAlignmentLeft;
    self.trialHintLab.numberOfLines = 1;
    self.trialHintLab.textColor = HexColor(@"#FF8F8A98");
    self.trialHintLab.font = PoppinsFont(@"Poppins-Medium", 14, UIFontWeightMedium);
    self.trialHintLab.text = @"3 - Days Free trial enabled";
    self.trialHintLab.hidden = YES;
    [self.view addSubview:self.trialHintLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.trialHintLab.topAnchor constraintEqualToAnchor:self.plansStack.bottomAnchor constant:12],
        [self.trialHintLab.leadingAnchor constraintEqualToAnchor:self.plansStack.leadingAnchor],
        [self.trialHintLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.plansStack.trailingAnchor],
    ]];

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueBtn.backgroundColor = HexColor(@"#FF014EFE");
    self.continueBtn.layer.cornerRadius = 34;
    [self.continueBtn setTitle:L(@"subscription.continue") forState:UIControlStateNormal];
    if ([[self.continueBtn titleForState:UIControlStateNormal] isEqualToString:@"subscription.continue"]) {
        [self.continueBtn setTitle:@"Continue" forState:UIControlStateNormal];
    }
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = PoppinsFont(@"Poppins-Bold", 22, UIFontWeightBold);
    [self.continueBtn addTarget:self action:@selector(tapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];

    self.autoRenewLab = [[UILabel alloc] init];
    self.autoRenewLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoRenewLab.textAlignment = NSTextAlignmentCenter;
    self.autoRenewLab.numberOfLines = 1;
    self.autoRenewLab.textColor = HexColor(@"#FF606060");
    self.autoRenewLab.font = PoppinsFont(@"Poppins-Regular", 12, UIFontWeightRegular);
    [self.view addSubview:self.autoRenewLab];

    self.bottomLinks = [[UIStackView alloc] init];
    self.bottomLinks.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomLinks.axis = UILayoutConstraintAxisHorizontal;
    self.bottomLinks.distribution = UIStackViewDistributionEqualSpacing;
    self.bottomLinks.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:self.bottomLinks];

    self.termsBtn = [self linkButtonWithTitle:@"Terms"];
    [self.termsBtn addTarget:self action:@selector(tapTerms) forControlEvents:UIControlEventTouchUpInside];

    self.privacyBtn = [self linkButtonWithTitle:@"Privacy"];
    [self.privacyBtn addTarget:self action:@selector(tapPrivacy) forControlEvents:UIControlEventTouchUpInside];

    self.restoreBtn = [self linkButtonWithTitle:@"Restore"];
    [self.restoreBtn addTarget:self action:@selector(tapRestore) forControlEvents:UIControlEventTouchUpInside];

    [self.bottomLinks addArrangedSubview:self.termsBtn];
    [self.bottomLinks addArrangedSubview:self.privacyBtn];
    [self.bottomLinks addArrangedSubview:self.restoreBtn];
    
    CGFloat rowW = 85 + 65 + 85;
    self.titleTopToSafe = [self.titleLab.topAnchor constraintEqualToAnchor:safe.topAnchor constant:60];
    self.titleTopToGateBadge = [self.titleLab.topAnchor constraintEqualToAnchor:self.gateBadgeView.bottomAnchor constant:18];

    self.titleTopToSafe.active = YES;
    self.titleTopToGateBadge.active = NO;

    self.continueTopToPlansStack = [self.continueBtn.topAnchor constraintEqualToAnchor:self.plansStack.bottomAnchor constant:47];
    self.continueTopToTrialHint  = [self.continueBtn.topAnchor constraintEqualToAnchor:self.trialHintLab.bottomAnchor constant:15];

    self.continueTopToPlansStack.active = YES;
    self.continueTopToTrialHint.active  = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.backBtn.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.titleLab.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleLab.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.featureRow.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:50],
        [self.featureRow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.featureRow.widthAnchor constraintEqualToConstant:rowW],

        [self.featureRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.featureRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.progressTrack.topAnchor constraintEqualToAnchor:self.featureRow.bottomAnchor constant:22],
        [self.progressTrack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.progressTrack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.progressTrack.heightAnchor constraintEqualToConstant:27],

        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.bottomAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor],
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],

        [self.usedRow.topAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor constant:12],
        [self.usedRow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.usedRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.usedRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.plansStack.topAnchor constraintEqualToAnchor:self.usedRow.bottomAnchor constant:50],
        [self.plansStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.plansStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],

        [self.continueBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:35],
        [self.continueBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-35],
        [self.continueBtn.heightAnchor constraintEqualToConstant:68],

        [self.autoRenewLab.topAnchor constraintEqualToAnchor:self.continueBtn.bottomAnchor constant:10],
        [self.autoRenewLab.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.autoRenewLab.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.bottomLinks.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:50],
        [self.bottomLinks.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-50],
        [self.bottomLinks.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:0],
        [self.bottomLinks.heightAnchor constraintGreaterThanOrEqualToConstant:20],

        [self.autoRenewLab.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomLinks.topAnchor constant:0],
    ]];

    self.progressFillW = [self.progressFill.widthAnchor constraintEqualToConstant:0];
    self.progressFillW.active = YES;

    self.backBtn.hidden = !self.allowDismiss;

    self.progress = 1.0;
    [self.photosFeature setBadgeNumber:822];
    [self.icloudFeature setBadgeNumber:768];
    [self applyProgressUI];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.titleLab.preferredMaxLayoutWidth = CGRectGetWidth(self.view.bounds) - 40;

    if (self.gateBadgeView && self.gateBadgeGradient) {
        self.gateBadgeGradient.frame = self.gateBadgeView.bounds;
        self.gateBadgeGradient.cornerRadius = 20;
    }
}

#pragma mark - Render (Store)

- (void)render {
    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;

    BOOL hasNet = snap.networkAvailable;
    BOOL busy = (snap.purchaseState == PurchaseFlowStatePurchasing ||
                 snap.purchaseState == PurchaseFlowStateRestoring ||
                 snap.purchaseState == PurchaseFlowStatePending);

    BOOL ready = (snap.productsState == ProductsLoadStateReady && snap.products.count > 0);

    self.restoreBtn.enabled = hasNet && !busy;

    if (!ready) {
        BOOL hasCached = (self.products.count > 0);
        self.continueBtn.enabled = hasNet && hasCached && !busy;
        if (!hasCached) self.autoRenewLab.text = @"";
        return;
    }

    // 1) 先规范化 products
    self.products = [self normalizedProducts:snap.products];

    NSInteger weekIdx = [self indexForUnit:SK2PeriodUnitWeek];
    NSInteger yearIdx = [self indexForUnit:SK2PeriodUnitYear];
    if (weekIdx == NSNotFound) weekIdx = 0;
    if (yearIdx == NSNotFound) yearIdx = 0;

    // 2) Gate or not
    BOOL isGate = (self.paywallMode == SubscriptionPaywallModeGateWeekly ||
                   self.paywallMode == SubscriptionPaywallModeGateYearly);

    if (self.paywallMode == SubscriptionPaywallModeWeekly || self.paywallMode == SubscriptionPaywallModeGateWeekly) {
        self.popularIndex = yearIdx;
    } else if (self.paywallMode == SubscriptionPaywallModeYearly || self.paywallMode == SubscriptionPaywallModeGateYearly) {
        self.popularIndex = yearIdx;
    }

    if (!isGate) {
        if (self.selectedProductID.length > 0) {
            NSInteger found = NSNotFound;
            for (NSInteger i = 0; i < self.products.count; i++) {
                if ([self.products[i].productID isEqualToString:self.selectedProductID]) { found = i; break; }
            }
            if (found != NSNotFound) self.selectedIndex = found;
        } else {
            self.selectedIndex = (self.paywallMode == SubscriptionPaywallModeYearly) ? yearIdx : weekIdx;
            self.selectedProductID = self.products.count ? self.products[self.selectedIndex].productID : nil;
        }
    }

    // 5) signature 只用于非 Gate 的列表是否重建
    NSString *sig = [self signatureForProducts:self.products];
    BOOL productsChanged = ![sig isEqualToString:self.productsSignature];
    self.productsSignature = sig;

    if (isGate) {
        if (!self.gateBuilt) {
            [self clearPlansUI];
            [self rebuildGateUI];
            self.gateBuilt = YES;
        }
    } else {
        if (productsChanged) [self rebuildPlansUI];
        else [self refreshPlanSelectionOnly];
    }

    // 6) 自动续订文案 & 按钮 enable
    [self updateAutoRenewLine];
    [self updateTrialHintUI];
    self.continueBtn.enabled = hasNet && !busy && ([self currentProductForPurchase] != nil);

    if (snap.subscriptionState == SubscriptionStateActive) {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
}

- (void)updateTrialHintUI {
    BOOL isGate = (self.paywallMode == SubscriptionPaywallModeGateWeekly ||
                   self.paywallMode == SubscriptionPaywallModeGateYearly);

    BOOL show = NO;
    if (!isGate) {
        SK2ProductModel *m = [self currentProductForPurchase];
        show = (m && m.periodUnit == SK2PeriodUnitWeek);
    }

    self.trialHintLab.hidden = !show;

    self.continueTopToPlansStack.active = !show;
    self.continueTopToTrialHint.active  = show;

    [self.view setNeedsLayout];
}

- (void)refreshPlanSelectionOnly {
    for (UIView *v in self.plansStack.arrangedSubviews) {
        if (![v isKindOfClass:SubPlanItemView.class]) continue;

        SubPlanItemView *it = (SubPlanItemView *)v;
        BOOL selected = (it.tag == self.selectedIndex);
        [it applySelectedStyle:selected];

        if (it.tag >= 0 && it.tag < self.products.count) {
            SK2ProductModel *m = self.products[it.tag];
            it.nameLab.text = [self localizedPlanNameForModel:m];

            NSString *unit = [self localizedPeriodUnitForModel:m];
            NSString *fmt = L(@"subscription.price_per_period");
            if ([fmt isEqualToString:@"subscription.price_per_period"]) fmt = @"%@ / %@";
            it.priceLab.text = [NSString stringWithFormat:fmt, (m.displayPrice ?: @""), unit];
        }
    }
}

- (void)clearPlansUI {
    for (UIView *v in self.plansStack.arrangedSubviews) {
        [self.plansStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (void)rebuildPlansUI {
    [self clearPlansUI];
    if (self.products.count == 0) return;

    if (self.paywallMode == SubscriptionPaywallModeGateWeekly || self.paywallMode == SubscriptionPaywallModeGateYearly) {
        [self rebuildGateUI];
        return;
    }

    self.plansStack.spacing = 20;
    
    for (NSInteger i = 0; i < self.products.count; i++) {
        SK2ProductModel *m = self.products[i];

        SubPlanItemView *item = [[SubPlanItemView alloc] init];
        item.tag = i;
        item.isPopular = (i == self.popularIndex);
        item.showPopularAlways = YES;
        
        item.nameLab.text = [self localizedPlanNameForModel:m];

        NSString *unit = [self localizedPeriodUnitForModel:m];

        NSString *fmt = L(@"subscription.price_per_period");
        if ([fmt isEqualToString:@"subscription.price_per_period"]) fmt = @"%@ / %@";

        item.priceLab.text = [NSString stringWithFormat:fmt, (m.displayPrice ?: @""), unit];

        [item addTarget:self action:@selector(tapPlanItem:) forControlEvents:UIControlEventTouchUpInside];

        BOOL selected = (i == self.selectedIndex);
        [item applySelectedStyle:selected];

        item.enabled = YES;

        [self.plansStack addArrangedSubview:item];
    }
}

- (NSArray<SK2ProductModel *> *)normalizedProducts:(NSArray<SK2ProductModel *> *)products {
    return [products sortedArrayUsingComparator:^NSComparisonResult(SK2ProductModel *a, SK2ProductModel *b) {
        if (a.periodUnit != b.periodUnit) {
            return (a.periodUnit > b.periodUnit) ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.productID ?: @"" compare:(b.productID ?: @"")];
    }];
}

- (NSString *)signatureForProducts:(NSArray<SK2ProductModel *> *)products {
    if (products.count == 0) return @"";
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:products.count];
    for (SK2ProductModel *m in products) {
        [ids addObject:(m.productID ?: @"")];
    }
    return [ids componentsJoinedByString:@"|"];
}

- (NSString *)localizedPlanNameForModel:(SK2ProductModel *)m {
    if (m.displayName.length > 0) return m.displayName;

    NSString *key = nil;
    switch (m.periodUnit) {
        case SK2PeriodUnitWeek:  key = @"subscription.week"; break;
        case SK2PeriodUnitYear:  key = @"subscription.year"; break;
        default:                 key = @"subscription.plan"; break;
    }

    NSString *s = L(key);

    if ([s isEqualToString:key]) {
        if ([key isEqualToString:@"subscription.week"])  return @"Weekly";
        if ([key isEqualToString:@"subscription.year"])  return @"Yearly";
        return @"Plan";
    }
    return s;
}

- (NSString *)localizedPeriodUnitForModel:(SK2ProductModel *)m {
    NSString *key = nil;
    switch (m.periodUnit) {
        case SK2PeriodUnitWeek:  key = @"subscription.period.week"; break;
        case SK2PeriodUnitYear:  key = @"subscription.period.year"; break;
        default:                 key = @"subscription.unit_period"; break;
    }

    NSString *s = L(key);

    if ([s isEqualToString:key]) {
        if ([key isEqualToString:@"subscription.period.week"])  return @"week";
        if ([key isEqualToString:@"subscription.period.year"])  return @"year";
        return @"period";
    }
    return s;
}

- (SK2ProductModel *)currentProductForPurchase {
    if (self.paywallMode == SubscriptionPaywallModeGateWeekly) {
        return [self productForUnit:SK2PeriodUnitWeek];
    }
    if (self.paywallMode == SubscriptionPaywallModeGateYearly) {
        return [self productForUnit:SK2PeriodUnitYear];
    }
    if (self.selectedIndex >= 0 && self.selectedIndex < self.products.count) {
        return self.products[self.selectedIndex];
    }
    return nil;
}

- (void)updateAutoRenewLine {
    if (self.selectedIndex < 0 || self.selectedIndex >= self.products.count) {
        self.autoRenewLab.text = @"";
        return;
    }
    SK2ProductModel *m = [self currentProductForPurchase];
    if (!m) { self.autoRenewLab.text = @""; return; }

    NSString *unit = [self localizedPeriodUnitForModel:m];

    NSString *fmt = L(@"subscription.autorenewing_format");
    if ([fmt isEqualToString:@"subscription.autorenewing_format"]) {
        fmt = @"Auto-renewing, %@ / %@, cancel any time";
    }
    self.autoRenewLab.text = [NSString stringWithFormat:fmt, (m.displayPrice ?: @""), unit];
}

- (NSInteger)indexForUnit:(SK2PeriodUnit)unit {
    for (NSInteger i = 0; i < self.products.count; i++) {
        SK2ProductModel *m = self.products[i];
        if (m.periodUnit == unit) return i;
    }
    return NSNotFound;
}

- (SK2ProductModel *)productForUnit:(SK2PeriodUnit)unit {
    NSInteger idx = [self indexForUnit:unit];
    if (idx == NSNotFound) return nil;
    return self.products[idx];
}

- (void)applyPaywallModeUI {
    BOOL isGate = (self.paywallMode == SubscriptionPaywallModeGateWeekly || self.paywallMode == SubscriptionPaywallModeGateYearly);

    self.gateBadgeView.hidden = !isGate;

    if (isGate) {
        self.titleLab.text = @"Storage Now";
    } else {
        NSString *t = L(@"subscription.unlock_unlimited_access");
        if ([t isEqualToString:@"subscription.unlock_unlimited_access"]) t = @"Unlock Unlimited Access";
        self.titleLab.text = t;
    }

    NSString *text = self.titleLab.text ?: @"";
    UIFont *font = self.titleLab.font ?: [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = self.titleLab.textAlignment;
    ps.minimumLineHeight = 40;
    ps.maximumLineHeight = 40;
    CGFloat baselineOffset = (40.0 - font.lineHeight) / 4.0;

    self.titleLab.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: self.titleLab.textColor ?: UIColor.blackColor,
        NSParagraphStyleAttributeName: ps,
        NSBaselineOffsetAttributeName: @(baselineOffset)
    }];

    self.titleTopToSafe.active = !isGate;
    self.titleTopToGateBadge.active = isGate;

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (UIView *)gateTipRow:(NSString *)text {
    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 15;

    UILabel *lab = [[UILabel alloc] init];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.numberOfLines = 0;
    lab.textAlignment = NSTextAlignmentLeft;
    lab.textColor = HexColor(@"#FF666666");
    lab.font = PoppinsFont(@"Poppins-Regular", 14, UIFontWeightRegular);
    lab.text = text ?: @"";

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_sub_tip"]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;

    UIView *iconWrap = [[UIView alloc] init];
    iconWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [iconWrap addSubview:iv];

    CGFloat lineH = ceil(lab.font.lineHeight);
    CGFloat wrapH = MAX(10.0, lineH);

    [NSLayoutConstraint activateConstraints:@[
        [iconWrap.widthAnchor constraintEqualToConstant:14],
        [iconWrap.heightAnchor constraintEqualToConstant:wrapH],

        [iv.widthAnchor constraintEqualToConstant:14],
        [iv.heightAnchor constraintEqualToConstant:10],
        [iv.centerXAnchor constraintEqualToAnchor:iconWrap.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:iconWrap.centerYAnchor],
    ]];

    [row addArrangedSubview:iconWrap];
    [row addArrangedSubview:lab];

    return row;
}

- (void)rebuildGateUI {
    [self clearPlansUI];

    self.plansStack.spacing = 0;

    UILabel *trial = [[UILabel alloc] init];
    trial.translatesAutoresizingMaskIntoConstraints = NO;
    trial.textAlignment = NSTextAlignmentCenter;
    trial.textColor = HexColor(@"#FF15172C");
    trial.font = PoppinsFont(@"Poppins-Medium", 16, UIFontWeightMedium);
    trial.text = (self.paywallMode == SubscriptionPaywallModeGateYearly)
               ? @""
               : @"3-Days Free Trial Enabled";

    UIStackView *tips = [[UIStackView alloc] init];
    tips.translatesAutoresizingMaskIntoConstraints = NO;
    tips.axis = UILayoutConstraintAxisVertical;
    tips.alignment = UIStackViewAlignmentFill;
    tips.distribution = UIStackViewDistributionFill;
    tips.spacing = 12;

    [tips addArrangedSubview:[self gateTipRow:@"Unlimited access to free up iphone space"]];
    [tips addArrangedSubview:[self gateTipRow:@"AI detect similar and dunplicate photos"]];
    [tips addArrangedSubview:[self gateTipRow:@"Private space to keep your data safe"]];

    [self.plansStack addArrangedSubview:trial];
    [self.plansStack addArrangedSubview:tips];

    if (@available(iOS 11.0, *)) {
        [self.plansStack setCustomSpacing:24 afterView:trial];
    } else {
        UIView *spacer = [[UIView alloc] init];
        spacer.translatesAutoresizingMaskIntoConstraints = NO;
        [spacer.heightAnchor constraintEqualToConstant:24].active = YES;
        [self.plansStack insertArrangedSubview:spacer atIndex:1];
    }
}

#pragma mark - Progress Loop Animation

- (void)startLoopAnimation {
    if (self.displayLink) return;

    self.animFrom = 1.0;
    self.animTo   = 0.33;
    self.progress = self.animFrom;

    self.moveDuration = 3.5;
    self.fadeDuration = 1.5;

    self.progressPhase = SubProgressPhaseMove;
    self.phaseStartTime = CACurrentMediaTime();

    // 每轮开始都确保可见
    self.progressTrack.alpha = 1.0;
    self.usedRow.alpha = 1.0;

    // 进度/数字回到起点
    [self.photosFeature setBadgeNumber:822];
    [self.icloudFeature setBadgeNumber:768];
    [self applyProgressUI];

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopLoopAnimation {
    [self.displayLink invalidate];
    self.displayLink = nil;

    self.progressTrack.alpha = 1.0;
    self.usedRow.alpha = 1.0;
}

- (void)onTick:(CADisplayLink *)dl {
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval t = now - self.phaseStartTime;

    if (self.progressPhase == SubProgressPhaseMove) {
        CGFloat p = (CGFloat)(t / self.moveDuration);
        if (p >= 1.0) p = 1.0;

        self.progress = self.animFrom + (self.animTo - self.animFrom) * p;

        NSInteger leftN  = (NSInteger)llround(822 + (68  - 822) * p);
        NSInteger rightN = (NSInteger)llround(768 + (53  - 768) * p);
        [self.photosFeature setBadgeNumber:leftN];
        [self.icloudFeature setBadgeNumber:rightN];

        self.progressTrack.alpha = 1.0;
        self.usedRow.alpha = 1.0;
        [self applyProgressUI];

        if (p >= 1.0) {
            self.progressPhase = SubProgressPhaseFade;
            self.phaseStartTime = now;
        }
        return;
    }

    if (self.progressPhase == SubProgressPhaseFade) {
        CGFloat fp = (CGFloat)(t / self.fadeDuration);
        if (fp >= 1.0) fp = 1.0;

        CGFloat alpha = (1.0 - fp);
        alpha = alpha * alpha;

        self.progressTrack.alpha = alpha;
        self.usedRow.alpha = alpha;

        if (fp >= 1.0) {
            self.progressPhase = SubProgressPhaseMove;
            self.phaseStartTime = now;

            self.progressTrack.alpha = 1.0;
            self.usedRow.alpha = 1.0;

            self.progress = self.animFrom;
            [self.photosFeature setBadgeNumber:822];
            [self.icloudFeature setBadgeNumber:768];
            [self applyProgressUI];
        }
        return;
    }
}

- (UIColor *)colorForProgress:(CGFloat)progress {
    if (progress >= 0.8) return HexColor(@"#FFF70B0B");
    if (progress >= 0.4) return HexColor(@"#FFAC6A08");
    return HexColor(@"#FF35D167");
}

- (void)applyProgressUI {
    UIColor *fillColor = [self colorForProgress:self.progress];
    self.progressFill.backgroundColor = fillColor;

    if (self.trackWidth <= 0) {
        [self.view layoutIfNeeded];
        self.trackWidth = self.progressTrack.bounds.size.width;
    }
    CGFloat w = MAX(0, MIN(self.trackWidth, self.trackWidth * self.progress));
    self.progressFillW.constant = w;

    NSInteger percent = (NSInteger)llround(self.progress * 100);
    self.usedPercentLab.text = [NSString stringWithFormat:@"%ld %%", (long)percent];
    self.usedPercentLab.textColor = fillColor;

    NSString *outOf = L(@"subscription.used_out_of_100");
    if ([outOf isEqualToString:@"subscription.used_out_of_100"]) outOf = @"out of 100%";

    NSString *used = L(@"subscription.used");
    if ([used isEqualToString:@"subscription.used"]) used = @"Used";

    UIColor *outColor = HexColor(@"#FF606060");
    UIColor *usedColor = (self.progress < 0.8) ? outColor : HexColor(@"#FFFF0000");

    self.usedOutOfLab.text = outOf;
    self.usedOutOfLab.textColor = outColor;

    self.usedWordLab.text = used;
    self.usedWordLab.textColor = usedColor;

    [UIView performWithoutAnimation:^{
        [self.progressTrack layoutIfNeeded];
    }];
}

#pragma mark - Actions

- (void)tapBack {
    if (!self.allowDismiss) return;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tapPlanItem:(SubPlanItemView *)sender {
    if (self.paywallMode == SubscriptionPaywallModeGateWeekly || self.paywallMode == SubscriptionPaywallModeGateYearly) return;
    if (sender.tag < 0 || sender.tag >= self.products.count) return;

    self.selectedIndex = sender.tag;
    self.selectedProductID = self.products[self.selectedIndex].productID;

    for (UIView *v in self.plansStack.arrangedSubviews) {
        if (![v isKindOfClass:SubPlanItemView.class]) continue;
        SubPlanItemView *it = (SubPlanItemView *)v;
        [it applySelectedStyle:(it.tag == self.selectedIndex)];
    }
    [self updateAutoRenewLine];
    [self updateTrialHintUI];
}

- (void)tapContinue {
    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;
    if (!snap.networkAvailable) return;
    if (snap.productsState != ProductsLoadStateReady) return;

    if (self.selectedIndex < 0 || self.selectedIndex >= self.products.count) return;
    SK2ProductModel *m = [self currentProductForPurchase];
    if (!m) return;
    
    self.continueBtn.enabled = NO;

    [[StoreKit2Manager shared] purchaseWithProductID:m.productID completion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];

            switch (st) {
                case PurchaseFlowStatePending:
                    [self showToast:L(@"paywall.purchase_pending")];
                    break;
                case PurchaseFlowStateCancelled:
                    [self showToast:L(@"paywall.purchase_cancelled")];
                    break;
                case PurchaseFlowStateSucceeded:
                    [self showToast:L(@"paywall.purchase_success")];
                    break;
                case PurchaseFlowStateFailed: {
                    NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                    [self showToast:(msg.length ? msg : L(@"paywall.purchase_failed"))];
                    break;
                }
                default:
                    break;
            }
        });
    }];
}

- (void)tapRestore {
    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;
    if (!snap.networkAvailable) return;

    self.restoreBtn.enabled = NO;

    [[StoreKit2Manager shared] restoreWithCompletion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];

            switch (st) {
                case PurchaseFlowStateRestored:
                    [self showToast:L(@"paywall.restore_success")];
                    break;
                case PurchaseFlowStateFailed: {
                    NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                    [self showToast:(msg.length ? msg : L(@"paywall.restore_failed"))];
                    break;
                }
                default:
                    break;
            }
        });
    }];
}

- (void)tapTerms { /* 留空 */ }
- (void)tapPrivacy { /* 留空 */ }

- (void)showToast:(NSString *)msg {
    if (msg.length == 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [ac dismissViewControllerAnimated:YES completion:nil];
    });
}

@end
