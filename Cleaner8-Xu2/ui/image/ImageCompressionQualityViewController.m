#import "ImageCompressionQualityViewController.h"
#import "ImageCompressionProgressViewController.h"
#import <Photos/Photos.h>

#pragma mark - Helpers

static uint64_t ASAssetFileSize(PHAsset *asset) {
    PHAssetResource *r = [PHAssetResource assetResourcesForAsset:asset].firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

static NSString *ASMB1(uint64_t bytes) {
    double mb = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1fMB", mb];
}

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0];
}
static inline UIColor *ASSelectCardBG(void) {
    return [UIColor colorWithRed:221/255.0 green:229/255.0 blue:247/255.0 alpha:1.0];
}
static inline UIFont *ASSB(CGFloat s) { return [UIFont systemFontOfSize:s weight:UIFontWeightSemibold]; }
static inline UIFont *ASRG(CGFloat s) { return [UIFont systemFontOfSize:s weight:UIFontWeightRegular]; }

static double ASImageRemainRatioForQuality(ASImageCompressionQuality q) {
    switch (q) {
        case ASImageCompressionQualitySmall:  return 0.20;
        case ASImageCompressionQualityMedium: return 0.50;
        case ASImageCompressionQualityLarge:  return 0.80;
    }
}

#pragma mark - Grid cell with minus (80x80)

@interface ASMinusCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UIButton *minusBtn;
@property (nonatomic, copy) NSString *representedAssetId;
@end

@implementation ASMinusCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        // ✅ 不裁剪：允许按钮突出
        self.clipsToBounds = NO;
        self.layer.masksToBounds = NO;
        self.contentView.clipsToBounds = NO;
        self.contentView.layer.masksToBounds = NO;

        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.layer.cornerRadius = 16;
        self.iv.layer.masksToBounds = YES;
        self.iv.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.iv];

        self.minusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.minusBtn.translatesAutoresizingMaskIntoConstraints = NO;

        self.minusBtn.layer.cornerRadius = 12;
        self.minusBtn.layer.masksToBounds = YES;

        // ✅ ic_delete 22x22 原尺寸显示
        UIImage *delImg = [[UIImage imageNamed:@"ic_delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.minusBtn setImage:delImg forState:UIControlStateNormal];
        self.minusBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

        self.minusBtn.layer.zPosition = 1000;

        [self.contentView addSubview:self.minusBtn];

        [NSLayoutConstraint activateConstraints:@[
            [self.iv.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.iv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.iv.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [self.minusBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:-8],
            [self.minusBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:8],
            [self.minusBtn.widthAnchor constraintEqualToConstant:24],
            [self.minusBtn.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([super pointInside:point withEvent:event]) return YES;
    CGPoint p = [self convertPoint:point toView:self.contentView];
    return CGRectContainsPoint(self.minusBtn.frame, p);
}

@end

#pragma mark - Option Row (same layout/style as Video)

@interface ASImageQualityRow : UIControl
@property (nonatomic) ASImageCompressionQuality quality;
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

- (instancetype)initWithQuality:(ASImageCompressionQuality)q title:(NSString *)title subtitle:(NSString *)sub;
- (void)applySelectedState:(BOOL)selected;
@end

@implementation ASImageQualityRow

- (instancetype)initWithQuality:(ASImageCompressionQuality)q title:(NSString *)title subtitle:(NSString *)sub {
    if (self = [super initWithFrame:CGRectZero]) {
        self.quality = q;
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 16;
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

        [self as_applyRowLayout_PaddingH15_V12_ContentCenter];
        [self applySelectedState:NO];
    }
    return self;
}

- (void)as_applyRowLayout_PaddingH15_V12_ContentCenter {
    self.pad = [UIView new];
    self.pad.translatesAutoresizingMaskIntoConstraints = NO;
    self.pad.userInteractionEnabled = NO; // ✅ 防止抢点击
    [self addSubview:self.pad];

    self.padL = [self.pad.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:17];
    self.padR = [self.pad.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-17];
    self.padT = [self.pad.topAnchor constraintEqualToAnchor:self.topAnchor constant:14];
    self.padB = [self.pad.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14];
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
    h.spacing = 12;
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

    // move subviews into groups
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

    [NSLayoutConstraint activateConstraints:@[
        [self.radioIcon.leadingAnchor constraintEqualToAnchor:leftGroup.leadingAnchor],
        [self.radioIcon.centerYAnchor constraintEqualToAnchor:leftGroup.centerYAnchor],
        [self.radioIcon.widthAnchor constraintEqualToConstant:24],
        [self.radioIcon.heightAnchor constraintEqualToConstant:24],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.radioIcon.trailingAnchor constant:14],
        [self.titleLabel.topAnchor constraintEqualToAnchor:leftGroup.topAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:leftGroup.trailingAnchor],

        [self.subLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subLabel.trailingAnchor constraintEqualToAnchor:leftGroup.trailingAnchor],
        [self.subLabel.bottomAnchor constraintEqualToAnchor:leftGroup.bottomAnchor],
    ]];

    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.sizeLabel.textAlignment = NSTextAlignmentRight;

    [NSLayoutConstraint activateConstraints:@[
        [self.percentLabel.topAnchor constraintEqualToAnchor:rightGroup.topAnchor],
        [self.percentLabel.leadingAnchor constraintEqualToAnchor:rightGroup.leadingAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:rightGroup.trailingAnchor],

        [self.sizeLabel.topAnchor constraintEqualToAnchor:self.percentLabel.bottomAnchor constant:4],
        [self.sizeLabel.leadingAnchor constraintEqualToAnchor:rightGroup.leadingAnchor],
        [self.sizeLabel.trailingAnchor constraintEqualToAnchor:rightGroup.trailingAnchor],
        [self.sizeLabel.bottomAnchor constraintEqualToAnchor:rightGroup.bottomAnchor],
    ]];

    [rightGroup setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [rightGroup setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)applySelectedState:(BOOL)selected {
    if (@available(iOS 13.0, *)) {
        if (selected) {
            self.radioIcon.image = [[UIImage systemImageNamed:@"checkmark.circle.fill"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.radioIcon.tintColor = ASBlue();
            self.layer.borderWidth = 2;
            self.layer.borderColor = ASBlue().CGColor;
        } else {
            self.radioIcon.image = [[UIImage systemImageNamed:@"circle"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.radioIcon.tintColor = [UIColor colorWithWhite:0 alpha:0.25];
            self.layer.borderWidth = 0;
            self.layer.borderColor = UIColor.clearColor.CGColor;
        }
    } else {
        self.layer.borderWidth = selected ? 2 : 0;
        self.layer.borderColor = selected ? ASBlue().CGColor : UIColor.clearColor.CGColor;
    }
}

@end

#pragma mark - VC

@interface ImageCompressionQualityViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) NSMutableArray<PHAsset *> *assets;
@property (nonatomic) ASImageCompressionQuality quality;
@property (nonatomic) uint64_t totalBeforeBytes;

@property (nonatomic, strong) CAGradientLayer *bgGradient;

// Header
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

// Preview (grid)
@property (nonatomic, strong) UICollectionView *grid;

// Before/After
@property (nonatomic, strong) UILabel *beforeLabel;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) UILabel *afterLabel;
@property (nonatomic, strong) UILabel *saveLabel;

// Select card
@property (nonatomic, strong) UIView *selectCard;
@property (nonatomic, strong) UILabel *selectTitle;
@property (nonatomic, strong) UIView *whiteBox;
@property (nonatomic, strong) ASImageQualityRow *rowSmall;
@property (nonatomic, strong) ASImageQualityRow *rowMedium;
@property (nonatomic, strong) ASImageQualityRow *rowLarge;

// Bottom
@property (nonatomic, strong) UIButton *compressBtn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *scrollContentView;

@end

@implementation ImageCompressionQualityViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets {
    if (self = [super init]) {
        _assets = [assets mutableCopy] ?: [NSMutableArray array];
        _quality = ASImageCompressionQualityMedium;
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
    [self calcBefore];
    [self refreshAll];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.bgGradient.frame = self.view.bounds;
}

#pragma mark - Data

- (void)calcBefore {
    uint64_t t = 0;
    for (PHAsset *a in self.assets) t += ASAssetFileSize(a);
    self.totalBeforeBytes = t;

    NSInteger count = self.assets.count;
    self.titleLabel.text = (count <= 1)
    ? @"1 Photo Selected"
    : [NSString stringWithFormat:@"%ld Photos Selected", (long)count];
}

#pragma mark - UI

- (void)buildUI {
    CGFloat side = 20;

    // 背景渐变（不变）
    self.bgGradient = [CAGradientLayer layer];
    self.bgGradient.colors = @[
        (id)[UIColor colorWithRed:229/255.0 green:241/255.0 blue:251/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1].CGColor
    ];
    self.bgGradient.startPoint = CGPointMake(0.5, 0.0);
    self.bgGradient.endPoint   = CGPointMake(0.5, 1.0);
    [self.view.layer insertSublayer:self.bgGradient atIndex:0];

    // 底部按钮（固定，不变）
    self.compressBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.compressBtn setTitle:@"Compress" forState:UIControlStateNormal];
    self.compressBtn.titleLabel.font = ASRG(20);
    [self.compressBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.compressBtn.backgroundColor = ASBlue();
    self.compressBtn.layer.cornerRadius = 35;
    self.compressBtn.layer.masksToBounds = YES;
    [self.compressBtn addTarget:self action:@selector(onCompress) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.compressBtn];
    self.compressBtn.translatesAutoresizingMaskIntoConstraints = NO;

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

    self.titleLabel = [UILabel new];
    self.titleLabel.font = ASSB(24);
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:self.backBtn];
    [header addSubview:self.titleLabel];

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

    // ===== 原来的“内容区域”开始：都加到 scrollContentView 上 =====

    UIView *preview = [UIView new];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:preview];

    UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
    lay.minimumLineSpacing = 10;
    lay.minimumInteritemSpacing = 10;
    lay.sectionInset = UIEdgeInsetsZero;

    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.scrollEnabled = NO;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.grid registerClass:ASMinusCell.class forCellWithReuseIdentifier:@"g"];
    [preview addSubview:self.grid];

    preview.clipsToBounds = NO;
    preview.layer.masksToBounds = NO;
    self.grid.clipsToBounds = NO;
    self.grid.layer.masksToBounds = NO;

    // Before/After
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
    baStack.spacing = 17;
    baStack.translatesAutoresizingMaskIntoConstraints = NO;
    [ba addSubview:baStack];

    [self.arrowView.widthAnchor constraintEqualToConstant:29].active = YES;
    [self.arrowView.heightAnchor constraintEqualToConstant:29].active = YES;

    self.saveLabel = [UILabel new];
    self.saveLabel.font = ASRG(16);
    self.saveLabel.textColor = UIColor.blackColor;
    self.saveLabel.textAlignment = NSTextAlignmentCenter;
    self.saveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:self.saveLabel];

    // Select card
    self.selectCard = [UIView new];
    self.selectCard.backgroundColor = ASSelectCardBG();
    self.selectCard.layer.cornerRadius = 22;
    self.selectCard.layer.masksToBounds = YES;
    self.selectCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.selectTitle = [UILabel new];
    self.selectTitle.font = ASSB(20);
    self.selectTitle.textColor = UIColor.blackColor;
    self.selectTitle.text = @"Select size";
    self.selectTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.whiteBox = [UIView new];
    self.whiteBox.backgroundColor = UIColor.whiteColor;
    self.whiteBox.layer.cornerRadius = 16;
    self.whiteBox.layer.masksToBounds = YES;
    self.whiteBox.translatesAutoresizingMaskIntoConstraints = NO;

    [self.scrollContentView addSubview:self.selectCard];
    [self.selectCard addSubview:self.selectTitle];
    [self.selectCard addSubview:self.whiteBox];

    self.rowSmall = [[ASImageQualityRow alloc] initWithQuality:ASImageCompressionQualitySmall
                                                       title:@"Small Size"
                                                    subtitle:@"Compact and shareable"];
    self.rowMedium = [[ASImageQualityRow alloc] initWithQuality:ASImageCompressionQualityMedium
                                                        title:@"Medium Size"
                                                     subtitle:@"Balance quality and space"];
    self.rowLarge = [[ASImageQualityRow alloc] initWithQuality:ASImageCompressionQualityLarge
                                                       title:@"Large Size"
                                                    subtitle:@"Maximum quality, larger file"];
    [self.rowSmall addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.rowMedium addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.rowLarge addTarget:self action:@selector(onRowTap:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.rowSmall, self.rowMedium, self.rowLarge]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 5;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.whiteBox addSubview:stack];

    CGFloat gridItem = 80;
    CGFloat gridGap = 10;
    CGFloat gridSide = gridItem * 3 + gridGap * 2;
    CGFloat headerH = 56;

    [NSLayoutConstraint activateConstraints:@[
        [self.compressBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [self.compressBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
        [self.compressBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:0],
        [self.compressBtn.heightAnchor constraintEqualToConstant:70],

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
        [preview.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:10],
        [preview.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [preview.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        // grid centered in preview
        [self.grid.centerXAnchor constraintEqualToAnchor:preview.centerXAnchor],
        [self.grid.topAnchor constraintEqualToAnchor:preview.topAnchor],
        [self.grid.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
        [self.grid.widthAnchor constraintEqualToConstant:gridSide],
        [self.grid.heightAnchor constraintEqualToConstant:gridSide],

        // before/after
        [ba.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:10],
        [ba.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [ba.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],
        [ba.heightAnchor constraintEqualToConstant:34],

        [baStack.centerXAnchor constraintEqualToAnchor:ba.centerXAnchor],
        [baStack.centerYAnchor constraintEqualToAnchor:ba.centerYAnchor],
        [baStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:ba.leadingAnchor],
        [baStack.trailingAnchor constraintLessThanOrEqualToAnchor:ba.trailingAnchor],

        [self.saveLabel.topAnchor constraintEqualToAnchor:ba.bottomAnchor constant:4],
        [self.saveLabel.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [self.saveLabel.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        // select card
        [self.selectCard.topAnchor constraintEqualToAnchor:self.saveLabel.bottomAnchor constant:15],
        [self.selectCard.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:side],
        [self.selectCard.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-side],

        [self.selectTitle.topAnchor constraintEqualToAnchor:self.selectCard.topAnchor constant:13],
        [self.selectTitle.leadingAnchor constraintEqualToAnchor:self.selectCard.leadingAnchor constant:18],

        [self.whiteBox.topAnchor constraintEqualToAnchor:self.selectTitle.bottomAnchor constant:11],
        [self.whiteBox.leadingAnchor constraintEqualToAnchor:self.selectCard.leadingAnchor constant:0],
        [self.whiteBox.trailingAnchor constraintEqualToAnchor:self.selectCard.trailingAnchor constant:0],
        [self.whiteBox.bottomAnchor constraintEqualToAnchor:self.selectCard.bottomAnchor constant:0],

        [stack.topAnchor constraintEqualToAnchor:self.whiteBox.topAnchor constant:5],
        [stack.leadingAnchor constraintEqualToAnchor:self.whiteBox.leadingAnchor constant:15],
        [stack.trailingAnchor constraintEqualToAnchor:self.whiteBox.trailingAnchor constant:-15],
        [stack.bottomAnchor constraintEqualToAnchor:self.whiteBox.bottomAnchor constant:-5],

        [self.rowSmall.heightAnchor constraintEqualToConstant:74],
        [self.rowMedium.heightAnchor constraintEqualToConstant:74],
        [self.rowLarge.heightAnchor constraintEqualToConstant:74],

        [self.selectCard.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-16],
    ]];
}

- (void)notifySelectionChanged {
    if (self.onSelectionChanged) {
        self.onSelectionChanged([self.assets copy]);
    }
}

#pragma mark - Refresh

- (void)refreshAll {
    double r = ASImageRemainRatioForQuality(self.quality);
    uint64_t after = (uint64_t)llround((double)self.totalBeforeBytes * r);
    uint64_t saved = (self.totalBeforeBytes > after) ? (self.totalBeforeBytes - after) : 0;

    self.beforeLabel.text = (self.totalBeforeBytes > 0) ? ASMB1(self.totalBeforeBytes) : @"--";
    self.afterLabel.text  = (self.totalBeforeBytes > 0) ? ASMB1(after) : @"--";

    NSString *saveSize = (self.totalBeforeBytes > 0) ? ASMB1(saved) : @"--";
    NSString *prefix = @"You will save about ";

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

    [self.rowSmall applySelectedState:(self.quality == ASImageCompressionQualitySmall)];
    [self.rowMedium applySelectedState:(self.quality == ASImageCompressionQualityMedium)];
    [self.rowLarge applySelectedState:(self.quality == ASImageCompressionQualityLarge)];
}

- (void)updateRow:(ASImageQualityRow *)row {
    if (self.totalBeforeBytes == 0) {
        row.percentLabel.text = @"--";
        row.sizeLabel.text = @"--";
        return;
    }
    double r = ASImageRemainRatioForQuality(row.quality);
    NSInteger savePercent = (NSInteger)llround((1.0 - r) * 100.0);
    uint64_t after = (uint64_t)llround((double)self.totalBeforeBytes * r);

    row.percentLabel.text = [NSString stringWithFormat:@"-%ld%%", (long)savePercent];
    row.sizeLabel.text = ASMB1(after);
}

#pragma mark - Actions

- (void)onBack {
    [self notifySelectionChanged];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onRowTap:(ASImageQualityRow *)row {
    self.quality = row.quality;
    [self refreshAll];
}

- (void)onCompress {
    if (self.assets.count == 0) return;

    uint64_t before = self.totalBeforeBytes;
    double r = ASImageRemainRatioForQuality(self.quality);
    uint64_t estAfter = (uint64_t)llround((double)before * r);

    ImageCompressionProgressViewController *vc =
    [[ImageCompressionProgressViewController alloc] initWithAssets:self.assets
                                                           quality:self.quality
                                                   totalBeforeBytes:before
                                                estimatedAfterBytes:estAfter];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return MIN(self.assets.count, 9);
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASMinusCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"g" forIndexPath:indexPath];

    PHAsset *a = self.assets[indexPath.item];
    cell.iv.image = nil;
    cell.representedAssetId = a.localIdentifier;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    // 80x80 cell，给个稍大 targetSize 避免糊
    [[PHImageManager defaultManager] requestImageForAsset:a
                                              targetSize:CGSizeMake(360, 360)
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if ([cell.representedAssetId isEqualToString:a.localIdentifier]) {
            cell.iv.image = result;
        }
    }];

    [cell.minusBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.minusBtn addTarget:self action:@selector(onRemoveBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    return cell;
}

- (void)onRemoveBtn:(UIButton *)btn {
    CGPoint p = [btn convertPoint:CGPointMake(btn.bounds.size.width/2.0, btn.bounds.size.height/2.0)
                           toView:self.grid];
    NSIndexPath *ip = [self.grid indexPathForItemAtPoint:p];
    if (!ip) return;

    NSInteger i = ip.item;
    if (i < 0 || i >= self.assets.count) return;

    [self.assets removeObjectAtIndex:i];

    // ✅ 关键：每次删除都回传最新选择
    [self notifySelectionChanged];

    if (self.assets.count == 0) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [self.grid reloadData];
    [self calcBefore];
    [self refreshAll];
}

- (void)onRemove:(UIButton *)btn {
    NSInteger i = btn.tag;
    if (i < 0 || i >= self.assets.count) return;

    [self.assets removeObjectAtIndex:i];
    if (self.assets.count == 0) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self.grid reloadData];
    [self calcBefore];
    [self refreshAll];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout*)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // ✅ 固定 80x80
    return CGSizeMake(80, 80);
}

@end
