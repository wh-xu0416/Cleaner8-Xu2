#import "SubscriptionViewController.h"
#import "Cleaner8_Xu2-Swift.h"
#import "LTEventTracker.h"

#pragma mark - Helpers
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

static inline CGFloat ASScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

static inline UIFont *ASACFont(CGFloat size, UIFontWeight weight) {
    return ASFontS(size, weight);
}

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
    self.badge.layer.cornerRadius = AS(43/2.0);
    self.badge.clipsToBounds = YES;
    [self addSubview:self.badge];

    self.badgeLab = [[UILabel alloc] init];
    self.badgeLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeLab.textAlignment = NSTextAlignmentCenter;
    self.badgeLab.textColor = UIColor.whiteColor;
    self.badgeLab.font = PoppinsFont(@"Poppins-Regular", AS(18), UIFontWeightRegular);
    [self.badge addSubview:self.badgeLab];

    self.titleLab = [[UILabel alloc] init];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    self.titleLab.textColor = HexColor(@"#FF1F1434");
    self.titleLab.font = PoppinsFont(@"Poppins-SemiBold", AS(14), UIFontWeightSemibold);
    self.titleLab.text = title ?: @"";
    [self addSubview:self.titleLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:AS(85)],
        [self.iconView.heightAnchor constraintEqualToConstant:AS(85)],

        [self.badge.widthAnchor constraintEqualToConstant:AS(43)],
        [self.badge.heightAnchor constraintEqualToConstant:AS(43)],
        [self.badge.centerXAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:-AS(6)],
        [self.badge.centerYAnchor constraintEqualToAnchor:self.iconView.topAnchor constant:AS(4)],

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
    self.card.layer.cornerRadius = AS(12);
    self.card.layer.borderColor = HexColor(@"#FFACC5FF").CGColor;
    self.card.layer.borderWidth = AS(1);
    self.card.backgroundColor = UIColor.whiteColor;
    self.card.userInteractionEnabled = NO;
    [self addSubview:self.card];

    self.nameLab = [[UILabel alloc] init];
    self.nameLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLab.textColor = HexColor(@"#FF1F1434");
    self.nameLab.font = PoppinsFont(@"Poppins-Bold", AS(16), UIFontWeightBold);
    self.nameLab.userInteractionEnabled = NO;
    [self.card addSubview:self.nameLab];

    self.priceLab = [[UILabel alloc] init];
    self.priceLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.priceLab.textColor = HexColor(@"#FF999999");
    self.priceLab.font = PoppinsFont(@"Poppins-Regular", AS(12), UIFontWeightRegular);
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
    self.popularTipLab.font = PoppinsFont(@"Poppins-Bold", AS(12), UIFontWeightBold);
    self.popularTipLab.adjustsFontSizeToFitWidth = YES;
    self.popularTipLab.minimumScaleFactor = 0.7;
    self.popularTipLab.userInteractionEnabled = NO;
    self.popularTipLab.text = NSLocalizedString(@"Most Popular",nil);
    [self.popularTip addSubview:self.popularTipLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.card.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.card.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.heightAnchor constraintEqualToConstant:AS(70)],

        [self.nameLab.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:AS(15)],
        [self.nameLab.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:AS(15)],
        [self.nameLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.radioImg.leadingAnchor constant:-AS(12)],

        [self.priceLab.topAnchor constraintEqualToAnchor:self.nameLab.bottomAnchor constant:AS(5)],
        [self.priceLab.leadingAnchor constraintEqualToAnchor:self.nameLab.leadingAnchor],
        [self.priceLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.radioImg.leadingAnchor constant:-AS(12)],
        [self.priceLab.bottomAnchor constraintLessThanOrEqualToAnchor:self.card.bottomAnchor constant:-AS(15)],

        [self.radioImg.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
        [self.radioImg.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-AS(22)],
        [self.radioImg.widthAnchor constraintEqualToConstant:AS(22)],
        [self.radioImg.heightAnchor constraintEqualToConstant:AS(22)],

        [self.popularTip.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [self.popularTip.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:-AS(8)],
        [self.popularTip.widthAnchor constraintEqualToConstant:AS(116)],
        [self.popularTip.heightAnchor constraintEqualToConstant:AS(24)],

        [self.popularTipImg.topAnchor constraintEqualToAnchor:self.popularTip.topAnchor],
        [self.popularTipImg.leadingAnchor constraintEqualToAnchor:self.popularTip.leadingAnchor],
        [self.popularTipImg.trailingAnchor constraintEqualToAnchor:self.popularTip.trailingAnchor],
        [self.popularTipImg.bottomAnchor constraintEqualToAnchor:self.popularTip.bottomAnchor],

        [self.popularTipLab.topAnchor constraintEqualToAnchor:self.popularTip.topAnchor constant:AS(2)],
        [self.popularTipLab.bottomAnchor constraintEqualToAnchor:self.popularTip.bottomAnchor constant:-AS(4)],
        [self.popularTipLab.leadingAnchor constraintEqualToAnchor:self.popularTip.leadingAnchor constant:AS(17)],
        [self.popularTipLab.trailingAnchor constraintEqualToAnchor:self.popularTip.trailingAnchor constant:-AS(17)],
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
        self.card.layer.borderWidth = AS(2);
        self.radioImg.image = [UIImage imageNamed:@"ic_sub_selected"];
    } else {
        self.card.layer.borderColor = HexColor(@"#FFACC5FF").CGColor;
        self.card.layer.borderWidth = AS(1);
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
@property(nonatomic,strong) UIView *loadingMask;
@property(nonatomic,strong) UIActivityIndicatorView *loadingSpinner;
@property(nonatomic,assign) NSInteger loadingCount;

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
    [self hideLoading];
    self.loadingCount = 0;
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
    UIFont *f = PoppinsFont(@"Poppins-Regular", AS(12), UIFontWeightRegular);
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
    self.backBtn.imageEdgeInsets = ASEdgeInsets(16, 0, 16, 32);
    [self.backBtn addTarget:self action:@selector(tapBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backBtn];

    self.gateBadgeView = [[UIView alloc] init];
    self.gateBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gateBadgeView.layer.cornerRadius = AS(20);
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
    self.gateBadgeLab.text = NSLocalizedString(@"Free Up",nil);
    [self.gateBadgeView addSubview:self.gateBadgeLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.gateBadgeView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:AS(42)],
        [self.gateBadgeView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.gateBadgeLab.leadingAnchor constraintEqualToAnchor:self.gateBadgeView.leadingAnchor constant:AS(20)],
        [self.gateBadgeLab.trailingAnchor constraintEqualToAnchor:self.gateBadgeView.trailingAnchor constant:-AS(20)],
        [self.gateBadgeLab.topAnchor constraintEqualToAnchor:self.gateBadgeView.topAnchor constant:AS(10)],
        [self.gateBadgeLab.bottomAnchor constraintEqualToAnchor:self.gateBadgeView.bottomAnchor constant:-AS(10)],
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
    self.titleLab.font = PoppinsFont(@"Poppins-Bold", AS(36), UIFontWeightBold);
    self.titleLab.text = NSLocalizedString(@"Unlock Unlimited Access",nil);
    
    NSString *text = self.titleLab.text ?: @"";
    UIFont *font = self.titleLab.font ?: [UIFont systemFontOfSize:AS(36) weight:UIFontWeightBold];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = self.titleLab.textAlignment;
    ps.minimumLineHeight = AS(40);
    ps.maximumLineHeight = AS(40);

    CGFloat baselineOffset = AS((40.0 - font.lineHeight) / 4.0);

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
    self.featureRow.spacing = AS(65);
    [self.view addSubview:self.featureRow];

    NSString *photosTitle = NSLocalizedString(@"photos",nil);
    NSString *icloudTitle = NSLocalizedString(@"icloud",nil);

    self.photosFeature = [[SubFeatureView alloc] initWithIcon:@"ic_sub_photos" title:photosTitle];
    self.icloudFeature  = [[SubFeatureView alloc] initWithIcon:@"ic_sub_icloud" title:icloudTitle];

    [self.featureRow addArrangedSubview:self.photosFeature];
    [self.featureRow addArrangedSubview:self.icloudFeature];

    [self.photosFeature.widthAnchor constraintEqualToConstant:AS(85)].active = YES;
    [self.icloudFeature.widthAnchor constraintEqualToConstant:AS(85)].active = YES;

    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTrack.backgroundColor = HexColor(@"#FFE2E2E4");
    self.progressTrack.layer.cornerRadius = AS(13.5);
    self.progressTrack.clipsToBounds = YES;
    [self.view addSubview:self.progressTrack];

    self.progressFill = [[UIView alloc] init];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFill.layer.cornerRadius = AS(13.5);
    self.progressFill.clipsToBounds = YES;
    [self.progressTrack addSubview:self.progressFill];

    self.usedRow = [[UIStackView alloc] init];
    self.usedRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedRow.axis = UILayoutConstraintAxisHorizontal;
    self.usedRow.alignment = UIStackViewAlignmentCenter;
    self.usedRow.distribution = UIStackViewDistributionFill;
    self.usedRow.spacing = AS(6);
    [self.view addSubview:self.usedRow];

    self.usedPercentLab = [[UILabel alloc] init];
    self.usedPercentLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedPercentLab.textAlignment = NSTextAlignmentRight;
    self.usedPercentLab.font = PoppinsFont(@"Poppins-SemiBold", AS(20), UIFontWeightSemibold);

    self.usedOutOfLab = [[UILabel alloc] init];
    self.usedOutOfLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedOutOfLab.font = PoppinsFont(@"Poppins-SemiBold", AS(16), UIFontWeightSemibold);
    self.usedOutOfLab.textColor = HexColor(@"#FF606060");

    self.usedWordLab = [[UILabel alloc] init];
    self.usedWordLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.usedWordLab.font = PoppinsFont(@"Poppins-SemiBold", AS(16), UIFontWeightSemibold);

    [self.usedRow addArrangedSubview:self.usedPercentLab];
    [self.usedRow addArrangedSubview:self.usedOutOfLab];
    [self.usedRow addArrangedSubview:self.usedWordLab];

    CGFloat w = ceil([@"100 %" sizeWithAttributes:@{NSFontAttributeName: self.usedPercentLab.font}].width);
    self.usedPercentW = [self.usedPercentLab.widthAnchor constraintEqualToConstant:w];
    self.usedPercentW.active = YES;

    self.plansStack = [[UIStackView alloc] init];
    self.plansStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.plansStack.axis = UILayoutConstraintAxisVertical;
    self.plansStack.spacing = AS(20);
    [self.view addSubview:self.plansStack];

    self.trialHintLab = [[UILabel alloc] init];
    self.trialHintLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.trialHintLab.textAlignment = NSTextAlignmentLeft;
    self.trialHintLab.numberOfLines = 1;
    self.trialHintLab.textColor = HexColor(@"#FF8F8A98");
    self.trialHintLab.font = PoppinsFont(@"Poppins-Medium", AS(14), UIFontWeightMedium);
    self.trialHintLab.text = NSLocalizedString(@"3 - Days Free trial enabled",nil);
    self.trialHintLab.hidden = YES;
    [self.view addSubview:self.trialHintLab];

    [NSLayoutConstraint activateConstraints:@[
        [self.trialHintLab.topAnchor constraintEqualToAnchor:self.plansStack.bottomAnchor constant:AS(12)],
        [self.trialHintLab.leadingAnchor constraintEqualToAnchor:self.plansStack.leadingAnchor],
        [self.trialHintLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.plansStack.trailingAnchor],
    ]];

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueBtn.backgroundColor = HexColor(@"#FF014EFE");
    self.continueBtn.layer.cornerRadius = AS(34);
    [self.continueBtn setTitle:NSLocalizedString(@"Continue",nil) forState:UIControlStateNormal];
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = PoppinsFont(@"Poppins-Bold", AS(22), UIFontWeightBold);
    [self.continueBtn addTarget:self action:@selector(tapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];

    self.autoRenewLab = [[UILabel alloc] init];
    self.autoRenewLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoRenewLab.textAlignment = NSTextAlignmentCenter;
    self.autoRenewLab.numberOfLines = 1;
    self.autoRenewLab.textColor = HexColor(@"#FF606060");
    self.autoRenewLab.font = PoppinsFont(@"Poppins-Regular", AS(12), UIFontWeightRegular);
    [self.view addSubview:self.autoRenewLab];

    self.bottomLinks = [[UIStackView alloc] init];
    self.bottomLinks.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomLinks.axis = UILayoutConstraintAxisHorizontal;
    self.bottomLinks.distribution = UIStackViewDistributionEqualSpacing;
    self.bottomLinks.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:self.bottomLinks];

    self.termsBtn = [self linkButtonWithTitle:NSLocalizedString(@"Terms",nil)];
    [self.termsBtn addTarget:self action:@selector(tapTerms) forControlEvents:UIControlEventTouchUpInside];

    self.privacyBtn = [self linkButtonWithTitle:NSLocalizedString(@"Privacy",nil)];
    [self.privacyBtn addTarget:self action:@selector(tapPrivacy) forControlEvents:UIControlEventTouchUpInside];

    self.restoreBtn = [self linkButtonWithTitle:NSLocalizedString(@"Restore",nil)];
    [self.restoreBtn addTarget:self action:@selector(tapRestore) forControlEvents:UIControlEventTouchUpInside];

    [self.bottomLinks addArrangedSubview:self.termsBtn];
    [self.bottomLinks addArrangedSubview:self.privacyBtn];
    [self.bottomLinks addArrangedSubview:self.restoreBtn];
    
    CGFloat rowW = AS(85 + 65 + 85);
    self.titleTopToSafe = [self.titleLab.topAnchor constraintEqualToAnchor:safe.topAnchor constant:AS(60)];
    self.titleTopToGateBadge = [self.titleLab.topAnchor constraintEqualToAnchor:self.gateBadgeView.bottomAnchor constant:AS(18)];

    self.titleTopToSafe.active = YES;
    self.titleTopToGateBadge.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.backBtn.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
        [self.backBtn.widthAnchor constraintEqualToConstant:AS(44)],
        [self.backBtn.heightAnchor constraintEqualToConstant:AS(44)],

        [self.titleLab.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.titleLab.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],

        [self.featureRow.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:AS(50)],
        [self.featureRow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.featureRow.widthAnchor constraintEqualToConstant:rowW],

        [self.featureRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.featureRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],
        
        [self.progressTrack.topAnchor constraintEqualToAnchor:self.featureRow.bottomAnchor constant:AS(22)],
        [self.progressTrack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(40)],
        [self.progressTrack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(40)],
        [self.progressTrack.heightAnchor constraintEqualToConstant:AS(27)],

        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.bottomAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor],
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],

        [self.usedRow.topAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor constant:AS(12)],
        [self.usedRow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.usedRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.usedRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],
        
        [self.plansStack.topAnchor constraintEqualToAnchor:self.usedRow.bottomAnchor constant:AS(64)],
        [self.plansStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(30)],
        [self.plansStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(30)],

        [self.continueBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(35)],
        [self.continueBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(35)],
        [self.continueBtn.heightAnchor constraintEqualToConstant:AS(68)],

        [self.autoRenewLab.topAnchor constraintEqualToAnchor:self.continueBtn.bottomAnchor constant:AS(10)],
        [self.autoRenewLab.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.autoRenewLab.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],

        [self.bottomLinks.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(50)],
        [self.bottomLinks.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(50)],
        [self.bottomLinks.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:0],
        [self.bottomLinks.heightAnchor constraintGreaterThanOrEqualToConstant:AS(20)],

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
    self.titleLab.preferredMaxLayoutWidth = CGRectGetWidth(self.view.bounds) - AS(40);

    if (self.gateBadgeView && self.gateBadgeGradient) {
        self.gateBadgeGradient.frame = self.gateBadgeView.bounds;
        self.gateBadgeGradient.cornerRadius = AS(20);
    }
}

#pragma mark - Render

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
        self.continueBtn.enabled = hasCached && !busy;
        if (!hasCached) self.autoRenewLab.text = @"";
        return;
    }

    self.products = [self normalizedProducts:snap.products];

    NSInteger weekIdx = [self indexForUnit:SK2PeriodUnitWeek];
    NSInteger yearIdx = [self indexForUnit:SK2PeriodUnitYear];
    if (weekIdx == NSNotFound) weekIdx = 0;
    if (yearIdx == NSNotFound) yearIdx = 0;

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

    [self updateAutoRenewLine];
    [self updateTrialHintUI];
    self.continueBtn.enabled = !busy && ([self currentProductForPurchase] != nil);

    if (snap.subscriptionState == SubscriptionStateActive) {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }

    if (!busy) {
        [self hideLoading];
        self.loadingCount = 0;
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
            NSString *fmt = NSLocalizedString(@"%@ / %@",nil);
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

    self.plansStack.spacing = AS(20);
    
    for (NSInteger i = 0; i < self.products.count; i++) {
        SK2ProductModel *m = self.products[i];

        SubPlanItemView *item = [[SubPlanItemView alloc] init];
        item.tag = i;
        item.isPopular = (i == self.popularIndex);
        item.showPopularAlways = YES;
        
        item.nameLab.text = [self localizedPlanNameForModel:m];

        NSString *unit = [self localizedPeriodUnitForModel:m];

        NSString *fmt = NSLocalizedString(@"%@ / %@",nil);

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
        case SK2PeriodUnitWeek:  key = NSLocalizedString(@"Weekly",nil); break;
        case SK2PeriodUnitYear:  key = NSLocalizedString(@"Yearly",nil); break;
        default:                 key = NSLocalizedString(@"Plan",nil); break;
    }
    return key;
}

- (NSString *)localizedPeriodUnitForModel:(SK2ProductModel *)m {
    NSString *key = nil;
    switch (m.periodUnit) {
        case SK2PeriodUnitWeek:  key = NSLocalizedString(@"week",nil); break;
        case SK2PeriodUnitYear:  key = NSLocalizedString(@"year",nil); break;
        default:                 key = NSLocalizedString(@"period",nil); break;
    }
    
    return key;
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

    NSString *fmt = NSLocalizedString(@"Auto-renewing, %@ / %@, cancel any time",nil);
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
        self.titleLab.text = NSLocalizedString(@"Storage Now",nil);
    } else {
        NSString *t = NSLocalizedString(@"Unlock Unlimited Access",nil);
        self.titleLab.text = t;
    }

    NSString *text = self.titleLab.text ?: @"";
    UIFont *font = self.titleLab.font ?: [UIFont systemFontOfSize:AS(36) weight:UIFontWeightBold];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = self.titleLab.textAlignment;
    ps.minimumLineHeight = AS(40);
    ps.maximumLineHeight = AS(40);
    CGFloat baselineOffset = AS((40.0 - font.lineHeight) / 4.0);

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
    row.spacing = AS(15);

    UILabel *lab = [[UILabel alloc] init];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.numberOfLines = 0;
    lab.textAlignment = NSTextAlignmentLeft;
    lab.textColor = HexColor(@"#FF666666");
    lab.font = PoppinsFont(@"Poppins-Regular", AS(14), UIFontWeightRegular);
    lab.text = text ?: @"";

    [lab setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                         forAxis:UILayoutConstraintAxisHorizontal];
    [lab setContentHuggingPriority:UILayoutPriorityDefaultHigh
                           forAxis:UILayoutConstraintAxisHorizontal];

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_sub_tip"]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;

    UIView *iconWrap = [[UIView alloc] init];
    iconWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [iconWrap addSubview:iv];

    CGFloat lineH = ceil(lab.font.lineHeight);
    CGFloat wrapH = MAX(10.0, lineH);

    [NSLayoutConstraint activateConstraints:@[
        [iconWrap.widthAnchor constraintEqualToConstant:AS(14)],
        [iconWrap.heightAnchor constraintEqualToConstant:wrapH],

        [iv.widthAnchor constraintEqualToConstant:AS(14)],
        [iv.heightAnchor constraintEqualToConstant:AS(10)],
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
    trial.font = PoppinsFont(@"Poppins-Medium", AS(16), UIFontWeightMedium);
    trial.text = (self.paywallMode == SubscriptionPaywallModeGateYearly)
               ? @""
               : NSLocalizedString(@"3-Days Free Trial Enabled",nil);

    UIView *tipsHost = [UIView new];
    tipsHost.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *row1 = [self gateTipRow:NSLocalizedString(@"Unlimited access to free up iphone space",nil)];
    UIView *row2 = [self gateTipRow:NSLocalizedString(@"AI detect similar and dunplicate photos",nil)];
    UIView *row3 = [self gateTipRow:NSLocalizedString(@"Private space to keep your data safe",nil)];

    [tipsHost addSubview:row1];
    [tipsHost addSubview:row2];
    [tipsHost addSubview:row3];

    [NSLayoutConstraint activateConstraints:@[
        [row1.topAnchor constraintEqualToAnchor:tipsHost.topAnchor],
        [row1.centerXAnchor constraintEqualToAnchor:tipsHost.centerXAnchor],
        [row1.leadingAnchor constraintGreaterThanOrEqualToAnchor:tipsHost.leadingAnchor],
        [row1.trailingAnchor constraintLessThanOrEqualToAnchor:tipsHost.trailingAnchor],

        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:AS(12)],
        [row2.leadingAnchor constraintEqualToAnchor:row1.leadingAnchor],
        [row2.trailingAnchor constraintLessThanOrEqualToAnchor:tipsHost.trailingAnchor],

        [row3.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:AS(12)],
        [row3.leadingAnchor constraintEqualToAnchor:row1.leadingAnchor],
        [row3.trailingAnchor constraintLessThanOrEqualToAnchor:tipsHost.trailingAnchor],
        [row3.bottomAnchor constraintEqualToAnchor:tipsHost.bottomAnchor],
    ]];

    [self.plansStack addArrangedSubview:trial];
    [self.plansStack addArrangedSubview:tipsHost];

    if (@available(iOS 11.0, *)) {
        [self.plansStack setCustomSpacing:AS(24) afterView:trial];
    } else {
        UIView *spacer = [[UIView alloc] init];
        spacer.translatesAutoresizingMaskIntoConstraints = NO;
        [spacer.heightAnchor constraintEqualToConstant:AS(24)].active = YES;
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

    self.progressTrack.alpha = 1.0;
    self.usedRow.alpha = 1.0;

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

    NSString *outOf = NSLocalizedString(@"out of 100%",nil);

    NSString *used = NSLocalizedString(@"Used",nil);

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

    if (!snap.networkAvailable) {
        [self showToastText:NSLocalizedString(@"Network Error", nil)];
        return;
    }
    if (snap.productsState != ProductsLoadStateReady) {
        [self showToastText:NSLocalizedString(@"Loading...", nil)];
        return;
    }

    SK2ProductModel *m = [self currentProductForPurchase];
    if (!m) {
        [self showToastText:NSLocalizedString(@"Please try again", nil)];
        return;
    }

    self.continueBtn.enabled = NO;
    [self showLoading];

    __weak typeof(self) weakSelf = self;
    [[StoreKit2Manager shared] purchaseWithProductID:m.productID completion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [self hideLoading];
            [self render];

            switch (st) {
                case PurchaseFlowStatePending:
                    [self showToastText:NSLocalizedString(@"Pending",nil)];
                    break;
                case PurchaseFlowStateCancelled:
                    [self showToastText:NSLocalizedString(@"Cancelled",nil)];
                    break;
                case PurchaseFlowStateSucceeded:
                    [self showToastText:NSLocalizedString(@"Success",nil)];
                    break;
                case PurchaseFlowStateFailed: {
                    NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                    [self showToastText:(msg.length ? msg : NSLocalizedString(@"Failed",nil))];
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

    if (!snap.networkAvailable) {
        [self showToastText:NSLocalizedString(@"Network error", nil)];
        return;
    }

    self.restoreBtn.enabled = NO;
    [self showLoading];

    __weak typeof(self) weakSelf = self;
    [[StoreKit2Manager shared] restoreWithCompletion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [self hideLoading];
            [self render];

            switch (st) {
                case PurchaseFlowStateRestored:
                    [self showToastText:NSLocalizedString(@"Restore Success",nil)];
                    break;
                case PurchaseFlowStateFailed: {
                    NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                    [self showToastText:(msg.length ? msg : NSLocalizedString(@"Restore Failed",nil))];
                    break;
                }
                default:
                    break;
            }
        });
    }];
}

- (void)tapTerms { [self as_openInBrowser: AppConstants.termsLink]; }
- (void)tapPrivacy { [self as_openInBrowser:AppConstants.privacyLink]; }

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

- (void)showToastText:(NSString *)text {
    UIView *host = self.view.window ?: self.view;
    if (!host) return;

    NSInteger tag = 909090;
    UIView *old = [host viewWithTag:tag];
    if (old) [old removeFromSuperview];

    UILabel *lab = [UILabel new];
    lab.text = text ?: @"";
    lab.textColor = UIColor.whiteColor;
    lab.font = ASACFont(16, UIFontWeightMedium);
    lab.textAlignment = NSTextAlignmentCenter;
    lab.numberOfLines = 1;

    UIView *toast = [UIView new];
    toast.tag = tag;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
    toast.layer.cornerRadius = AS(12);
    toast.layer.masksToBounds = YES;

    [toast addSubview:lab];
    [host addSubview:toast];

    CGFloat maxW = host.bounds.size.width - AS(80);
    CGSize textSize = [lab sizeThatFits:CGSizeMake(maxW, 999)];
    CGFloat padX = AS(22), padY = AS(12);

    CGFloat w = MIN(maxW, textSize.width) + padX * 2;
    CGFloat h = textSize.height + padY * 2;

    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = host.safeAreaInsets.bottom;

    CGFloat x = (host.bounds.size.width - w) * 0.5;
    CGFloat y = host.bounds.size.height - safeBottom - h - AS(110);
    toast.frame = CGRectMake(x, y, w, h);
    lab.frame = CGRectMake(padX, padY, w - padX * 2, h - padY * 2);

    toast.alpha = 0.0;
    toast.transform = CGAffineTransformMakeScale(0.98, 0.98);

    [UIView animateWithDuration:0.18 animations:^{
        toast.alpha = 1.0;
        toast.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.18 animations:^{
                toast.alpha = 0.0;
            } completion:^(__unused BOOL finished2) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

#pragma mark - Loading

- (void)showLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingCount += 1;
        if (self.loadingMask.superview) return;

        UIView *host = self.view.window ?: self.view;
        if (!host) return;

        UIView *mask = [[UIView alloc] initWithFrame:host.bounds];
        mask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        mask.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        mask.userInteractionEnabled = YES;
        self.loadingMask = mask;

        UIActivityIndicatorView *sp = nil;
        if (@available(iOS 13.0, *)) {
            sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        } else {
            sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        }
        sp.translatesAutoresizingMaskIntoConstraints = NO;
        [mask addSubview:sp];
        [NSLayoutConstraint activateConstraints:@[
            [sp.centerXAnchor constraintEqualToAnchor:mask.centerXAnchor],
            [sp.centerYAnchor constraintEqualToAnchor:mask.centerYAnchor],
        ]];
        self.loadingSpinner = sp;

        [host addSubview:mask];
        [sp startAnimating];
    });
}

- (void)hideLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingCount = MAX(0, self.loadingCount - 1);
        if (self.loadingCount > 0) return;

        [self.loadingSpinner stopAnimating];
        [self.loadingMask removeFromSuperview];
        self.loadingSpinner = nil;
        self.loadingMask = nil;
    });
}

@end
