#import "VideoCompressionQualityViewController.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import "VideoCompressionProgressViewController.h"
#import "ASMediaPreviewViewController.h"

static const CGFloat kASDesignBaseWidth  = 402.0;
static const CGFloat kASDesignBaseHeight = 874.0;

static inline CGFloat ASScaleDown(void) {
    CGSize sz = UIScreen.mainScreen.bounds.size;
    CGFloat sw = sz.width  / kASDesignBaseWidth;
    CGFloat sh = sz.height / kASDesignBaseHeight;
    return MIN(sw, sh);
}

static inline CGFloat ASV(CGFloat v)  { return ceil(v * ASScaleDown()); }
static inline CGFloat ASVR(CGFloat v) { return v * ASScaleDown(); }
static inline CGFloat ASClamp(CGFloat v, CGFloat lo, CGFloat hi) { return MIN(MAX(v, lo), hi); }

#pragma mark - Helpers

static uint64_t ASAssetFileSize(PHAsset *asset) {
    PHAssetResource *r = [PHAssetResource assetResourcesForAsset:asset].firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

static NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

static NSString *ASMB1(uint64_t bytes) {
    double mb = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1fMB", mb];
}

static NSString *ASDurationText(NSTimeInterval duration) {
    NSInteger d = (NSInteger)llround(duration);
    NSInteger m = d / 60, s = d % 60;
    if (m >= 60) { NSInteger h = m/60; m%=60; return [NSString stringWithFormat:@"%ld:%02ld:%02ld",(long)h,(long)m,(long)s]; }
    return [NSString stringWithFormat:@"%ld:%02ld",(long)m,(long)s];
}

static double ASRemainRatioForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 0.20;
        case ASCompressionQualityMedium: return 0.50;
        case ASCompressionQualityLarge:  return 0.80;
    }
}

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0];
}
static inline UIColor *ASSelectCardBG(void) {
    return [UIColor colorWithRed:221/255.0 green:229/255.0 blue:247/255.0 alpha:1.0];
}

static inline UIFont *ASSB(CGFloat s) { return [UIFont systemFontOfSize:round(s * ASScaleDown()) weight:UIFontWeightSemibold]; }
static inline UIFont *ASMD(CGFloat s) { return [UIFont systemFontOfSize:round(s * ASScaleDown()) weight:UIFontWeightMedium]; }
static inline UIFont *ASRG(CGFloat s) { return [UIFont systemFontOfSize:round(s * ASScaleDown()) weight:UIFontWeightRegular]; }

#pragma mark - Option Row

@interface ASQualityRow : UIControl
@property (nonatomic) ASCompressionQuality quality;
@property (nonatomic, strong) UIImageView *radioIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UILabel *sizeLabel;

@property (nonatomic, strong) UIView *pad;
@property (nonatomic, strong) NSLayoutConstraint *padL;
@property (nonatomic, strong) NSLayoutConstraint *padR;
@property (nonatomic, strong) NSLayoutConstraint *padT;
@property (nonatomic, strong) NSLayoutConstraint *padB;

- (instancetype)initWithQuality:(ASCompressionQuality)q title:(NSString *)title subtitle:(NSString *)sub;
- (void)applySelectedState:(BOOL)selected;
@end

@implementation ASQualityRow

- (instancetype)initWithQuality:(ASCompressionQuality)q title:(NSString *)title subtitle:(NSString *)sub {
    if (self = [super initWithFrame:CGRectZero]) {
        self.quality = q;
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = ASClamp(ASVR(16), 14, 16);
        self.layer.masksToBounds = YES;

        self.radioIcon = [UIImageView new];
        self.radioIcon.contentMode = UIViewContentModeScaleAspectFit;

        self.titleLabel = [UILabel new];
        self.titleLabel.font = ASSB(20);
        self.titleLabel.textColor = UIColor.blackColor;
        self.titleLabel.text = title;

        self.subLabel = [UILabel new];
        self.subLabel.font = ASRG(12);
        self.subLabel.textColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.subLabel.text = sub;

        self.percentLabel = [UILabel new];
        self.percentLabel.font = ASSB(15);
        self.percentLabel.textColor = ASBlue();
        self.percentLabel.textAlignment = NSTextAlignmentRight;

        self.sizeLabel = [UILabel new];
        self.sizeLabel.font = ASRG(12);
        self.sizeLabel.textColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.sizeLabel.textAlignment = NSTextAlignmentRight;

        [self addSubview:self.radioIcon];
        [self addSubview:self.titleLabel];
        [self addSubview:self.subLabel];
        [self addSubview:self.percentLabel];
        [self addSubview:self.sizeLabel];

        self.radioIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self as_applyRowLayout_Scaled];
        [self applySelectedState:NO];
    }
    return self;
}

- (void)as_applyRowLayout_Scaled {
    self.pad = [UIView new];
    self.pad.translatesAutoresizingMaskIntoConstraints = NO;
    self.pad.userInteractionEnabled = NO;
    [self addSubview:self.pad];

    CGFloat padH = ASClamp(ASV(17), 14, 17);
    CGFloat padV = ASClamp(ASV(14), 12, 14);

    self.padL = [self.pad.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:padH];
    self.padR = [self.pad.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-padH];
    self.padT = [self.pad.topAnchor constraintEqualToAnchor:self.topAnchor constant:padV];
    self.padB = [self.pad.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-padV];
    [NSLayoutConstraint activateConstraints:@[self.padL, self.padR, self.padT, self.padB]];

    UIView *leftGroup = [UIView new];
    UIView *rightGroup = [UIView new];
    UIView *spacer = [UIView new];

    leftGroup.translatesAutoresizingMaskIntoConstraints = NO;
    rightGroup.translatesAutoresizingMaskIntoConstraints = NO;
    spacer.translatesAutoresizingMaskIntoConstraints = NO;

    leftGroup.userInteractionEnabled = NO;
    rightGroup.userInteractionEnabled = NO;
    spacer.userInteractionEnabled = NO;

    UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[leftGroup, spacer, rightGroup]];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.alignment = UIStackViewAlignmentCenter;
    h.distribution = UIStackViewDistributionFill;
    h.spacing = ASClamp(ASV(12), 10, 12);
    h.translatesAutoresizingMaskIntoConstraints = NO;
    h.userInteractionEnabled = NO;

    [self.pad addSubview:h];

    [NSLayoutConstraint activateConstraints:@[
        [h.leadingAnchor constraintEqualToAnchor:self.pad.leadingAnchor],
        [h.trailingAnchor constraintEqualToAnchor:self.pad.trailingAnchor],
        [h.topAnchor constraintEqualToAnchor:self.pad.topAnchor],
        [h.bottomAnchor constraintEqualToAnchor:self.pad.bottomAnchor],
    ]];

    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];

    // move into groups
    [self.radioIcon removeFromSuperview];
    [self.titleLabel removeFromSuperview];
    [self.subLabel removeFromSuperview];
    [self.percentLabel removeFromSuperview];
    [self.sizeLabel removeFromSuperview];

    [leftGroup addSubview:self.radioIcon];
    [leftGroup addSubview:self.titleLabel];
    [leftGroup addSubview:self.subLabel];

    [rightGroup addSubview:self.percentLabel];
    [rightGroup addSubview:self.sizeLabel];

    self.radioIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    CGFloat radio = ASClamp(ASV(24), 22, 24);
    CGFloat gap1  = ASClamp(ASV(14), 12, 14);
    CGFloat gap2  = ASClamp(ASV(4),  3,  4);

    [NSLayoutConstraint activateConstraints:@[
        [self.radioIcon.leadingAnchor constraintEqualToAnchor:leftGroup.leadingAnchor],
        [self.radioIcon.centerYAnchor constraintEqualToAnchor:leftGroup.centerYAnchor],
        [self.radioIcon.widthAnchor constraintEqualToConstant:radio],
        [self.radioIcon.heightAnchor constraintEqualToConstant:radio],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.radioIcon.trailingAnchor constant:gap1],
        [self.titleLabel.topAnchor constraintEqualToAnchor:leftGroup.topAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:leftGroup.trailingAnchor],

        [self.subLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:gap2],
        [self.subLabel.trailingAnchor constraintEqualToAnchor:leftGroup.trailingAnchor],
        [self.subLabel.bottomAnchor constraintEqualToAnchor:leftGroup.bottomAnchor],
    ]];

    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.sizeLabel.textAlignment = NSTextAlignmentRight;

    [NSLayoutConstraint activateConstraints:@[
        [self.percentLabel.topAnchor constraintEqualToAnchor:rightGroup.topAnchor],
        [self.percentLabel.leadingAnchor constraintEqualToAnchor:rightGroup.leadingAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:rightGroup.trailingAnchor],

        [self.sizeLabel.topAnchor constraintEqualToAnchor:self.percentLabel.bottomAnchor constant:gap2],
        [self.sizeLabel.leadingAnchor constraintEqualToAnchor:rightGroup.leadingAnchor],
        [self.sizeLabel.trailingAnchor constraintEqualToAnchor:rightGroup.trailingAnchor],
        [self.sizeLabel.bottomAnchor constraintEqualToAnchor:rightGroup.bottomAnchor],
    ]];

    [rightGroup setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [rightGroup setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)applySelectedState:(BOOL)selected {
    static UIImage *onImg = nil;
    static UIImage *offImg = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        onImg  = [[UIImage imageNamed:@"ic_select_s"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        offImg = [[UIImage imageNamed:@"ic_select_gray_n"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });

    self.radioIcon.image = selected ? onImg : offImg;
    self.radioIcon.contentMode = UIViewContentModeScaleAspectFit;

    if (selected) {
        self.layer.borderWidth = 2;
        self.layer.borderColor = ASBlue().CGColor;
    } else {
        self.layer.borderWidth = 0;
        self.layer.borderColor = UIColor.clearColor.CGColor;
    }
}

@end

#pragma mark - VC

@interface VideoCompressionQualityViewController ()
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic) ASCompressionQuality quality;
@property (nonatomic) uint64_t totalBeforeBytes;

@property (nonatomic, strong) CAGradientLayer *bgGradient;

// Header
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

// Preview
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIButton *playBtn;

@property (nonatomic, strong) UILabel *sizeKey;
@property (nonatomic, strong) UILabel *sizeVal;
@property (nonatomic, strong) UILabel *durKey;
@property (nonatomic, strong) UILabel *durVal;
@property (nonatomic, strong) UILabel *resKey;
@property (nonatomic, strong) UILabel *resVal;

// Before/After
@property (nonatomic, strong) UILabel *beforeLabel;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) UILabel *afterLabel;
@property (nonatomic, strong) UILabel *saveLabel;

// Select card
@property (nonatomic, strong) UIView *selectCard;
@property (nonatomic, strong) UILabel *selectTitle;
@property (nonatomic, strong) UIView *whiteBox;
@property (nonatomic, strong) ASQualityRow *rowSmall;
@property (nonatomic, strong) ASQualityRow *rowMedium;
@property (nonatomic, strong) ASQualityRow *rowLarge;

// Bottom
@property (nonatomic, strong) UIButton *compressBtn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *scrollContentView;

@end

@implementation VideoCompressionQualityViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _quality = ASCompressionQualityMedium;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self loadTopInfo];
    [self loadThumbForFirst];
    [self refreshAll];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.bgGradient.frame = self.view.bounds;
}

#pragma mark - UI

- (UILabel *)makeKey:(NSString *)t {
    UILabel *l = [UILabel new];
    l.font = ASRG(15);
    l.textColor = [UIColor colorWithWhite:0 alpha:0.5];
    l.text = t;
    return l;
}

- (UILabel *)makeVal {
    UILabel *l = [UILabel new];
    l.font = ASMD(15);
    l.textColor = UIColor.blackColor;
    l.text = @"--";
    return l;
}

- (void)buildUI {
    // ===== scaled constants based on 402x874 =====
    CGFloat side = ASClamp(ASV(20), 14, 20);
    CGFloat headerH = ASClamp(ASV(56), 50, 56);

    CGFloat thumbW = ASClamp(ASV(150), 128, 150);
    CGFloat thumbH = ASClamp(ASV(200), 170, 200);

    CGFloat playInset = ASClamp(ASV(11), 9, 11);
    CGFloat playSize  = ASClamp(ASV(22), 20, 22);

    CGFloat infoGapToThumb = ASClamp(ASV(18), 14, 18);
    CGFloat infoKeyValGap  = ASClamp(ASV(6),  5,  6);
    CGFloat infoBlockGap   = ASClamp(ASV(20), 16, 20);

    CGFloat baTopGap = ASClamp(ASV(22), 18, 22);
    CGFloat baH      = ASClamp(ASV(34), 30, 34);
    CGFloat baSpace  = ASClamp(ASV(17), 14, 17);

    CGFloat arrowS   = ASClamp(ASV(26), 24, 26);

    CGFloat saveTop  = ASClamp(ASV(4),  3, 4);

    CGFloat cardTop  = ASClamp(ASV(18), 14, 18);
    CGFloat cardR    = ASClamp(ASVR(22), 18, 22);
    CGFloat whiteR   = ASClamp(ASVR(16), 14, 16);

    CGFloat cardTitleTop = ASClamp(ASV(13), 11, 13);
    CGFloat cardTitleL   = ASClamp(ASV(18), 16, 18);
    CGFloat whiteTopGap  = ASClamp(ASV(11), 9, 11);

    CGFloat stackTop = ASClamp(ASV(5), 4, 5);
    CGFloat stackSide = ASClamp(ASV(15), 12, 15);
    CGFloat stackBottom = ASClamp(ASV(5), 4, 5);
    CGFloat stackSpacing = ASClamp(ASV(5), 4, 5);

    CGFloat rowH = ASClamp(ASV(74), 66, 74);

    CGFloat compressH = ASClamp(ASV(70), 64, 70);  // ✅ 下限保护
    CGFloat compressR = compressH / 2.0;

    // ===== bg =====
    self.bgGradient = [CAGradientLayer layer];
    self.bgGradient.colors = @[
        (id)[UIColor colorWithRed:229/255.0 green:241/255.0 blue:251/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1].CGColor
    ];
    self.bgGradient.startPoint = CGPointMake(0.5, 0.0);
    self.bgGradient.endPoint   = CGPointMake(0.5, 1.0);
    [self.view.layer insertSublayer:self.bgGradient atIndex:0];

    // ===== bottom button =====
    self.compressBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.compressBtn setTitle:NSLocalizedString(@"Compress",nil) forState:UIControlStateNormal];
    self.compressBtn.titleLabel.font = ASRG(20);
    [self.compressBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.compressBtn.backgroundColor = ASBlue();
    self.compressBtn.layer.cornerRadius = compressR;
    self.compressBtn.layer.masksToBounds = YES;
    [self.compressBtn addTarget:self action:@selector(onCompress) forControlEvents:UIControlEventTouchUpInside];
    self.compressBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.compressBtn];

    // ===== header =====
    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];
    self.backBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.backBtn];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = ASSB(24);
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.titleLabel];

    // ===== scroll =====
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.scrollView];

    self.scrollContentView = [UIView new];
    self.scrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollContentView.backgroundColor = UIColor.clearColor;
    [self.scrollView addSubview:self.scrollContentView];

    // ===== preview =====
    UIView *preview = [UIView new];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:preview];

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [preview addSubview:content];

    self.thumbView = [UIImageView new];
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.layer.cornerRadius = ASClamp(ASVR(16), 14, 16);
    self.thumbView.layer.masksToBounds = YES;
    self.thumbView.userInteractionEnabled = YES;
    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.thumbView];

    UITapGestureRecognizer *tapThumb = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapPreview)];
    [self.thumbView addGestureRecognizer:tapThumb];

    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *playImg = [UIImage imageNamed:@"ic_play"];
    [self.playBtn setImage:[playImg imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    self.playBtn.layer.cornerRadius = ASClamp(ASVR(11), 10, 11);
    self.playBtn.layer.masksToBounds = YES;
    [self.playBtn addTarget:self action:@selector(onTapPreview) forControlEvents:UIControlEventTouchUpInside];
    self.playBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.thumbView addSubview:self.playBtn];

    UIView *info = [UIView new];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:info];

    self.sizeKey = [self makeKey:NSLocalizedString(@"Size",nil)];
    self.sizeVal = [self makeVal];
    self.durKey  = [self makeKey:NSLocalizedString(@"Duration",nil)];
    self.durVal  = [self makeVal];
    self.resKey  = [self makeKey:NSLocalizedString(@"Resolution",nil)];
    self.resVal  = [self makeVal];

    [info addSubview:self.sizeKey];
    [info addSubview:self.sizeVal];
    [info addSubview:self.durKey];
    [info addSubview:self.durVal];
    [info addSubview:self.resKey];
    [info addSubview:self.resVal];
    for (UIView *v in info.subviews) v.translatesAutoresizingMaskIntoConstraints = NO;

    // ===== before/after =====
    self.beforeLabel = [UILabel new];
    self.beforeLabel.font = ASSB(24);
    self.beforeLabel.textColor = UIColor.blackColor;

    self.afterLabel = [UILabel new];
    self.afterLabel.font = ASSB(24);
    self.afterLabel.textColor = ASBlue();

    self.arrowView = [UIImageView new];
    UIImage *toImg = [[UIImage imageNamed:@"ic_compress_to"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.arrowView.image = toImg;
    self.arrowView.contentMode = UIViewContentModeCenter;

    UIView *ba = [UIView new];
    ba.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:ba];

    UIStackView *baStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeLabel, self.arrowView, self.afterLabel]];
    baStack.axis = UILayoutConstraintAxisHorizontal;
    baStack.alignment = UIStackViewAlignmentCenter;
    baStack.distribution = UIStackViewDistributionFill;
    baStack.spacing = baSpace;
    baStack.translatesAutoresizingMaskIntoConstraints = NO;
    [ba addSubview:baStack];

    self.saveLabel = [UILabel new];
    self.saveLabel.font = ASRG(16);
    self.saveLabel.textColor = UIColor.blackColor;
    self.saveLabel.textAlignment = NSTextAlignmentCenter;
    self.saveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:self.saveLabel];

    // ===== select card =====
    self.selectCard = [UIView new];
    self.selectCard.backgroundColor = ASSelectCardBG();
    self.selectCard.layer.cornerRadius = cardR;
    self.selectCard.layer.masksToBounds = YES;
    self.selectCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:self.selectCard];

    self.selectTitle = [UILabel new];
    self.selectTitle.font = ASSB(20);
    self.selectTitle.textColor = UIColor.blackColor;
    self.selectTitle.text = NSLocalizedString(@"Select size",nil);
    self.selectTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectCard addSubview:self.selectTitle];

    self.whiteBox = [UIView new];
    self.whiteBox.backgroundColor = UIColor.whiteColor;
    self.whiteBox.layer.cornerRadius = whiteR;
    self.whiteBox.layer.masksToBounds = YES;
    self.whiteBox.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectCard addSubview:self.whiteBox];

    self.rowSmall = [[ASQualityRow alloc] initWithQuality:ASCompressionQualitySmall
                                                   title:NSLocalizedString(@"Small Size",nil)
                                                subtitle:NSLocalizedString(@"Compact and shareable",nil)];
    self.rowMedium = [[ASQualityRow alloc] initWithQuality:ASCompressionQualityMedium
                                                    title:NSLocalizedString(@"Medium Size",nil)
                                                 subtitle:NSLocalizedString(@"Balance quality and space",nil)];
    self.rowLarge = [[ASQualityRow alloc] initWithQuality:ASCompressionQualityLarge
                                                   title:NSLocalizedString(@"Large Size",nil)
                                                subtitle:NSLocalizedString(@"Maximum quality, larger file",nil)];
    [self.rowSmall addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.rowMedium addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.rowLarge addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.rowSmall, self.rowMedium, self.rowLarge]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = stackSpacing;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.whiteBox addSubview:stack];

    // ===== constraints =====
    [NSLayoutConstraint activateConstraints:@[
        // bottom button
        [self.compressBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [self.compressBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
        [self.compressBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:0],
        [self.compressBtn.heightAnchor constraintEqualToConstant:compressH],

        // header
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:headerH],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:6],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        // scroll
        [self.scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.compressBtn.topAnchor],

        [self.scrollContentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollContentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.scrollContentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.scrollContentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.scrollContentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        // preview
        [preview.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:ASClamp(ASV(16), 12, 16)],
        [preview.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [preview.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        [content.centerXAnchor constraintEqualToAnchor:preview.centerXAnchor],
        [content.topAnchor constraintEqualToAnchor:preview.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:preview.leadingAnchor],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:preview.trailingAnchor],

        // thumb fixed (scaled)
        [self.thumbView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.thumbView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.thumbView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:thumbW],
        [self.thumbView.heightAnchor constraintEqualToConstant:thumbH],

        // play button
        [self.playBtn.leadingAnchor constraintEqualToAnchor:self.thumbView.leadingAnchor constant:playInset],
        [self.playBtn.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor constant:playInset],
        [self.playBtn.widthAnchor constraintEqualToConstant:playSize],
        [self.playBtn.heightAnchor constraintEqualToConstant:playSize],

        // info
        [info.leadingAnchor constraintEqualToAnchor:self.thumbView.trailingAnchor constant:infoGapToThumb],
        [info.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [info.centerYAnchor constraintEqualToAnchor:self.thumbView.centerYAnchor],

        // info labels
        [self.sizeKey.topAnchor constraintEqualToAnchor:info.topAnchor],
        [self.sizeKey.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.sizeKey.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

        [self.sizeVal.topAnchor constraintEqualToAnchor:self.sizeKey.bottomAnchor constant:infoKeyValGap],
        [self.sizeVal.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.sizeVal.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

        [self.durKey.topAnchor constraintEqualToAnchor:self.sizeVal.bottomAnchor constant:infoBlockGap],
        [self.durKey.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.durKey.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

        [self.durVal.topAnchor constraintEqualToAnchor:self.durKey.bottomAnchor constant:infoKeyValGap],
        [self.durVal.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.durVal.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

        [self.resKey.topAnchor constraintEqualToAnchor:self.durVal.bottomAnchor constant:infoBlockGap],
        [self.resKey.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.resKey.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

        [self.resVal.topAnchor constraintEqualToAnchor:self.resKey.bottomAnchor constant:infoKeyValGap],
        [self.resVal.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [self.resVal.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],
        [self.resVal.bottomAnchor constraintEqualToAnchor:info.bottomAnchor],

        // before/after
        [ba.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:baTopGap],
        [ba.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [ba.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],
        [ba.heightAnchor constraintEqualToConstant:baH],

        [self.arrowView.widthAnchor constraintEqualToConstant:arrowS],
        [self.arrowView.heightAnchor constraintEqualToConstant:arrowS],

        [baStack.centerXAnchor constraintEqualToAnchor:ba.centerXAnchor],
        [baStack.centerYAnchor constraintEqualToAnchor:ba.centerYAnchor],
        [baStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:ba.leadingAnchor],
        [baStack.trailingAnchor constraintLessThanOrEqualToAnchor:ba.trailingAnchor],

        // save label
        [self.saveLabel.topAnchor constraintEqualToAnchor:ba.bottomAnchor constant:saveTop],
        [self.saveLabel.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [self.saveLabel.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        // select card
        [self.selectCard.topAnchor constraintEqualToAnchor:self.saveLabel.bottomAnchor constant:cardTop],
        [self.selectCard.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [self.selectCard.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        [self.selectTitle.topAnchor constraintEqualToAnchor:self.selectCard.topAnchor constant:cardTitleTop],
        [self.selectTitle.leadingAnchor constraintEqualToAnchor:self.selectCard.leadingAnchor constant:cardTitleL],

        [self.whiteBox.topAnchor constraintEqualToAnchor:self.selectTitle.bottomAnchor constant:whiteTopGap],
        [self.whiteBox.leadingAnchor constraintEqualToAnchor:self.selectCard.leadingAnchor constant:0],
        [self.whiteBox.trailingAnchor constraintEqualToAnchor:self.selectCard.trailingAnchor constant:0],
        [self.whiteBox.bottomAnchor constraintEqualToAnchor:self.selectCard.bottomAnchor constant:0],

        [stack.topAnchor constraintEqualToAnchor:self.whiteBox.topAnchor constant:stackTop],
        [stack.leadingAnchor constraintEqualToAnchor:self.whiteBox.leadingAnchor constant:stackSide],
        [stack.trailingAnchor constraintEqualToAnchor:self.whiteBox.trailingAnchor constant:-stackSide],
        [stack.bottomAnchor constraintEqualToAnchor:self.whiteBox.bottomAnchor constant:-stackBottom],

        [self.rowSmall.heightAnchor constraintEqualToConstant:rowH],
        [self.rowMedium.heightAnchor constraintEqualToConstant:rowH],
        [self.rowLarge.heightAnchor constraintEqualToConstant:rowH],

        [self.selectCard.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-ASClamp(ASV(16), 14, 16)],
    ]];
}

#pragma mark - Data

- (void)loadTopInfo {
    NSInteger count = self.assets.count;
    self.titleLabel.text = (count <= 1) ? NSLocalizedString(@"1 Video Selected",nil) : [NSString stringWithFormat:NSLocalizedString(@"%ld Videos Selected",nil),(long)count];

    uint64_t total = 0;
    for (PHAsset *a in self.assets) total += ASAssetFileSize(a);
    self.totalBeforeBytes = total;

    PHAsset *first = self.assets.firstObject;
    if (!first) return;

    uint64_t b = ASAssetFileSize(first);
    self.sizeVal.text = (b > 0) ? ASHumanSize(b) : @"--";
    self.durVal.text = ASDurationText(first.duration);
    self.resVal.text = [NSString stringWithFormat:@"%ld × %ld", (long)first.pixelWidth, (long)first.pixelHeight];
}

- (void)loadThumbForFirst {
    PHAsset *first = self.assets.firstObject;
    if (!first) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    [[PHImageManager defaultManager] requestImageForAsset:first
                                              targetSize:CGSizeMake(900, 900)
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) self.thumbView.image = result;
    }];
}

#pragma mark - Refresh

- (void)refreshAll {
    double r = ASRemainRatioForQuality(self.quality);
    uint64_t after = (uint64_t)llround((double)self.totalBeforeBytes * r);
    uint64_t saved = (self.totalBeforeBytes > after) ? (self.totalBeforeBytes - after) : 0;

    self.beforeLabel.text = (self.totalBeforeBytes > 0) ? ASMB1(self.totalBeforeBytes) : @"--";
    self.afterLabel.text  = (self.totalBeforeBytes > 0) ? ASMB1(after) : @"--";

    NSString *saveSize = (self.totalBeforeBytes > 0 ? ASMB1(saved) : @"--");
    NSString *prefix = NSLocalizedString(@"You will save about ",nil);

    NSMutableAttributedString *attr =
    [[NSMutableAttributedString alloc] initWithString:prefix
                                           attributes:@{
        NSFontAttributeName: ASRG(16),
        NSForegroundColorAttributeName: UIColor.blackColor
    }];

    NSAttributedString *boldPart =
    [[NSAttributedString alloc] initWithString:saveSize
                                    attributes:@{
        NSFontAttributeName: ASSB(16),
        NSForegroundColorAttributeName: UIColor.blackColor
    }];

    [attr appendAttributedString:boldPart];
    self.saveLabel.attributedText = attr;

    [self updateRow:self.rowSmall];
    [self updateRow:self.rowMedium];
    [self updateRow:self.rowLarge];

    [self.rowSmall applySelectedState:(self.quality == ASCompressionQualitySmall)];
    [self.rowMedium applySelectedState:(self.quality == ASCompressionQualityMedium)];
    [self.rowLarge applySelectedState:(self.quality == ASCompressionQualityLarge)];
}

- (void)updateRow:(ASQualityRow *)row {
    if (self.totalBeforeBytes == 0) {
        row.percentLabel.text = @"--";
        row.sizeLabel.text = @"--";
        return;
    }
    double r = ASRemainRatioForQuality(row.quality);
    NSInteger savePercent = (NSInteger)llround((1.0 - r) * 100.0);
    uint64_t after = (uint64_t)llround((double)self.totalBeforeBytes * r);

    row.percentLabel.text = [NSString stringWithFormat:@"-%ld%%", (long)savePercent];
    row.sizeLabel.text = ASMB1(after);
}

#pragma mark - Actions

- (void)onBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onRowTap:(ASQualityRow *)row {
    self.quality = row.quality;
    [self refreshAll];
}

- (void)onTapPreview {
    if (self.assets.count == 0) return;

    PHAsset *a = self.assets.firstObject;
    if (!a) return;

    NSArray<PHAsset *> *previewAssets = @[a];
    NSIndexSet *preSel = [NSIndexSet indexSet];

    ASMediaPreviewViewController *p =
    [[ASMediaPreviewViewController alloc] initWithAssets:previewAssets
                                           initialIndex:0
                                        selectedIndexes:preSel];

    p.bestIndex = 0;
    p.showsBestBadge = YES;

    [self.navigationController pushViewController:p animated:YES];
}

- (void)onCompress {
    uint64_t before = self.totalBeforeBytes;
    double r = ASRemainRatioForQuality(self.quality);
    uint64_t after = (uint64_t)llround((double)before * r);

    VideoCompressionProgressViewController *vc =
    [[VideoCompressionProgressViewController alloc] initWithAssets:self.assets
                                                           quality:self.quality
                                                   totalBeforeBytes:before
                                                estimatedAfterBytes:after];

    [self.navigationController pushViewController:vc animated:YES];
}

@end
