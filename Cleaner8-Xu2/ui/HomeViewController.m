#import "HomeViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import "ASPhotoScanManager.h"
#import "ASAssetListViewController.h"
#import "VideoSubPageViewController.h"
#import "ASPrivatePermissionBanner.h"
#import "Common.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UI Constants
typedef NS_ENUM(NSInteger, ASPhotoAuthLevel) {
    ASPhotoAuthLevelUnknown = -1,
    ASPhotoAuthLevelNone    = 0,   // Denied / Restricted / NotDetermined(未授权态)
    ASPhotoAuthLevelLimited = 1,
    ASPhotoAuthLevelFull    = 2
};

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}

static inline void ASLogCost(NSString *name, CFTimeInterval start) {
    NSLog(@"⏱️ %@ %.2fms", name, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
}

static NSString * const kASLastPhotoAuthLevelKey = @"as_last_photo_auth_level_v1";

static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / SWDesignWidth());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}

static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return SWFontS(size,weight);
}


//static const CGFloat kHomeSideInset = SW(16.0);
//static const CGFloat kHomeGridGap   = SW(12.0);

//static const CGFloat kHeaderHeight  = SW(200.0);
//static const CGFloat kLargeCellH    = SW(260.0);

#define kHomeSideInset   SW(16.0)
#define kHomeGridGap     SW(12.0)
#define kHeaderHeight    SW(200.0)
#define kLargeCellH      SW(260.0)

static UIColor *kHomeBgColor(void) { return ASRGB(246, 248, 251); }
static UIColor *kCardShadowColor(void) { return [UIColor colorWithWhite:0 alpha:0.10]; }
static UIColor *kTextGray(void) { return ASRGB(102, 102, 102); }

static UIColor *kClutterRed(void) { return ASRGB(245, 19, 19); }
static UIColor *kAppDataYellow(void) { return ASRGB(255, 181, 46); }
static UIColor *kTotalGray(void) { return ASRGB(218, 218, 218); }

static CGFloat ASHomeBgHeightForWidth(CGFloat width) {
    static UIImage *bgImg = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bgImg = [UIImage imageNamed:@"ic_home_bg"];
    });
    if (!bgImg || bgImg.size.width <= 0) return kHeaderHeight;
    return bgImg.size.height * (width / bgImg.size.width);
}

static NSString *ASMarketingTotalString(uint64_t totalBytes) {
    double gib = (double)totalBytes / (1024.0 * 1024.0 * 1024.0);
    if (gib < 192)  return @"128GB";
    if (gib < 384)  return @"256GB";
    if (gib < 768)  return @"512GB";
    if (gib < 1536) return @"1TB";
    return @"2TB";
}

static UIColor *kBadgeBlue(void) { return ASRGB(2, 77, 255); }

#pragma mark - Home Card Type

typedef NS_ENUM(NSUInteger, ASHomeCardType) {
    ASHomeCardTypeSimilarPhotos = 0,
    ASHomeCardTypeVideos,
    ASHomeCardTypeDuplicatePhotos,
    ASHomeCardTypeScreenshots,
    ASHomeCardTypeBlurryPhotos,
    ASHomeCardTypeOtherPhotos,
};

#pragma mark - Scan UI Result Model

@interface ASScanUIResult : NSObject
@property(nonatomic, assign) uint64_t diskTotal;
@property(nonatomic, assign) uint64_t diskFree;

@property(nonatomic, assign) uint64_t clutterBytes;
@property(nonatomic, assign) uint64_t appDataBytes;

// Similar Photos
@property(nonatomic, assign) uint64_t simBytes;
@property(nonatomic, assign) NSUInteger simCount;
@property(nonatomic, copy)   NSArray<NSString *> *simThumbs;

// Duplicate Photos
@property(nonatomic, assign) uint64_t dupBytes;
@property(nonatomic, assign) NSUInteger dupCount;
@property(nonatomic, copy)   NSArray<NSString *> *dupThumbs;

// Screenshots
@property(nonatomic, assign) uint64_t shotsBytes;
@property(nonatomic, assign) NSUInteger shotsCount;
@property(nonatomic, copy)   NSArray<NSString *> *shotsThumb;

// Blurry
@property(nonatomic, assign) uint64_t blurBytes;
@property(nonatomic, assign) NSUInteger blurCount;
@property(nonatomic, copy)   NSArray<NSString *> *blurThumb;

// Other
@property(nonatomic, assign) uint64_t otherBytes;
@property(nonatomic, assign) NSUInteger otherCount;
@property(nonatomic, copy)   NSArray<NSString *> *otherThumb;

// Videos (simVid + dupVid + bigVideos + screenRecordings)
@property(nonatomic, assign) uint64_t vBytes;
@property(nonatomic, assign) NSUInteger vCount;
@property(nonatomic, copy)   NSArray<NSString *> *videoThumb;
@end

@implementation ASScanUIResult @end

#pragma mark - Home Module Model

@interface ASHomeModuleVM : NSObject
@property (nonatomic) BOOL didSetThumb;
@property (nonatomic) ASHomeCardType type;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *countText;
@property (nonatomic) NSUInteger totalCount;
@property (nonatomic) uint64_t totalBytes;

@property (nonatomic, strong) NSArray<NSString *> *thumbLocalIds;
@property (nonatomic, copy) NSString *thumbKey;

@property (nonatomic) BOOL showsTwoThumbs;
@property (nonatomic) BOOL isVideoCover;
@end

@implementation ASHomeModuleVM @end

#pragma mark - Segmented Progress View

@interface ASSegmentedBarView : UIView
@property (nonatomic, strong) UIView *redView;
@property (nonatomic, strong) UIView *yellowView;
@property (nonatomic, strong) UIView *grayView;
@property (nonatomic) CGFloat redRatio;
@property (nonatomic) CGFloat yellowRatio;
@property (nonatomic) CGFloat grayRatio;
- (void)setRedRatio:(CGFloat)r yellowRatio:(CGFloat)y grayRatio:(CGFloat)g;
@end

@implementation ASSegmentedBarView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _grayView = [UIView new];
        _yellowView = [UIView new];
        _redView = [UIView new];

        _redView.backgroundColor = kClutterRed();
        _yellowView.backgroundColor = kAppDataYellow();
        _grayView.backgroundColor = kTotalGray();

        [self addSubview:_grayView];
        [self addSubview:_yellowView];
        [self addSubview:_redView];

        _redView.clipsToBounds = YES;
        _yellowView.clipsToBounds = YES;
        _grayView.clipsToBounds = YES;

        self.clipsToBounds = NO;
    }
    return self;
}

- (void)setRedRatio:(CGFloat)r yellowRatio:(CGFloat)y grayRatio:(CGFloat)g {
    _redRatio = MAX(0, MIN(1, r));
    _yellowRatio = MAX(0, MIN(1, y));
    _grayRatio = MAX(0, MIN(1, g));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    CGFloat radius = SW(6.0);
    CGFloat overlap = radius;

    CGFloat sum = self.redRatio + self.yellowRatio + self.grayRatio;
    if (sum <= 0.0001) {
        self.grayView.frame = CGRectMake(0, 0, w, h);
        self.yellowView.frame = CGRectZero;
        self.redView.frame = CGRectZero;
    } else {
        CGFloat r = self.redRatio / sum;
        CGFloat y = self.yellowRatio / sum;
        CGFloat g = self.grayRatio / sum;

        CGFloat rw = floor(w * r);
        CGFloat yw = floor(w * y);
        CGFloat gw = w - rw - yw;

        self.grayView.frame = CGRectMake(0, 0, w, h);

        if (yw > 0) {
            CGFloat yx = MAX(0, rw - overlap);
            CGFloat yRight = MIN(w, rw + yw);
            CGFloat yWidth = MAX(0, yRight - yx);
            self.yellowView.frame = CGRectMake(yx, 0, yWidth, h);
        } else {
            self.yellowView.frame = CGRectZero;
        }

        if (rw > 0) {
            CGFloat rWidth = MIN(w, rw + ((yw > 0 || gw > 0) ? overlap : 0));
            self.redView.frame = CGRectMake(0, 0, rWidth, h);
        } else {
            self.redView.frame = CGRectZero;
        }
    }

    void (^roundAll)(UIView *) = ^(UIView *v) {
        if (CGRectIsEmpty(v.frame)) return;
        v.layer.cornerRadius = radius;
        if (@available(iOS 11.0, *)) {
            v.layer.maskedCorners = (kCALayerMinXMinYCorner |
                                     kCALayerMaxXMinYCorner |
                                     kCALayerMinXMaxYCorner |
                                     kCALayerMaxXMaxYCorner);
        }
    };
    roundAll(self.grayView);
    roundAll(self.yellowView);
    roundAll(self.redView);
}

@end

#pragma mark - Header View

@interface ASHomeHeaderView : UICollectionReusableView
@property (nonatomic, strong) ASPrivatePermissionBanner *permissionBanner;
@property (nonatomic) BOOL showsLimitedBanner;
@property (nonatomic, copy) void (^onTapLimitedBanner)(void);
- (void)setShowsLimitedBanner:(BOOL)shows;

@property (nonatomic, strong) CAGradientLayer *proGradient;

@property (nonatomic, strong) UILabel *spaceTitleLabel;
@property (nonatomic, strong) UILabel *spaceLabel;
@property (nonatomic, strong) UIButton *proBtn;
@property (nonatomic, strong) ASSegmentedBarView *bar;

@property (nonatomic, strong) UIView *legend1Dot;
@property (nonatomic, strong) UILabel *legend1Name;
@property (nonatomic, strong) UILabel *legend1Value;

@property (nonatomic, strong) UIView *legend2Dot;
@property (nonatomic, strong) UILabel *legend2Name;
@property (nonatomic, strong) UILabel *legend2Value;

@property (nonatomic, strong) UIView *legend3Dot;
@property (nonatomic, strong) UILabel *legend3Name;
@property (nonatomic, strong) UILabel *legend3Value;

- (void)applyTotal:(uint64_t)total
           clutter:(uint64_t)clutter
           appData:(uint64_t)appData
              free:(uint64_t)freeBytes
       humanSizeFn:(NSString * _Nonnull (^)(uint64_t bytes))humanSize;
@end

#pragma mark - No Auth Cell

@interface ASNoAuthCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *t1;
@property (nonatomic, strong) UILabel *t2;
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation ASNoAuthCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.image = [UIImage imageNamed:@"ic_photo_permission_not"];
        [self.contentView addSubview:_iconView];

        _t1 = [UILabel new];
        _t1.text = NSLocalizedString(@"Allow Photo Access", nil);
        _t1.textColor = UIColor.blackColor;
        _t1.font = ASFont(20, UIFontWeightMedium);
        _t1.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_t1];

        _t2 = [UILabel new];
        _t2.text = NSLocalizedString(@"To compress photos, videos, and LivePhotos. please allow access to your photo library.", nil);
        _t2.textColor = ASRGB(102, 102, 102);
        _t2.font = ASFont(13, UIFontWeightRegular);
        _t2.numberOfLines = 3;
        _t2.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_t2];

        _btn = [UIButton buttonWithType:UIButtonTypeCustom];
        _btn.backgroundColor = ASBlue();
        _btn.layer.cornerRadius = SW(35);
        _btn.clipsToBounds = YES;
        [_btn setTitle:NSLocalizedString(@"Go to Settings", nil) forState:UIControlStateNormal];
        [_btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _btn.titleLabel.font = ASFont(20, UIFontWeightRegular);
        _btn.contentEdgeInsets = SWInsets(18, 0, 18, 0);
        [_btn addTarget:self action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_btn];
    }
    return self;
}

- (void)onBtn {
    if (self.onTap) self.onTap();
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.contentView.bounds.size.width;
    CGFloat top = SW(60);

    self.iconView.frame = CGRectMake((w - SW(96))/2.0, top, SW(96), SW(96));
    self.t1.frame = CGRectMake(SW(30), CGRectGetMaxY(self.iconView.frame) + SW(20), w - SW(60), SW(24));
    CGFloat t2W = w - SW(90);

    CGSize t2Size = [self.t2 sizeThatFits:CGSizeMake(t2W, CGFLOAT_MAX)];
    CGFloat lineH = self.t2.font.lineHeight;

    CGFloat t2H = MIN(t2Size.height, ceil(lineH * 3.0));

    self.t2.frame = CGRectMake(SW(45), CGRectGetMaxY(self.t1.frame) + SW(10), t2W, t2H);
    CGFloat btnW = w - SW(90);
    self.btn.frame = CGRectMake((w - btnW)/2.0,
                                CGRectGetMaxY(self.t2.frame) + SW(50),
                                btnW,
                                SW(70));
}

@end

@implementation ASHomeHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;

        _permissionBanner = [[ASPrivatePermissionBanner alloc] initWithFrame:CGRectZero];
        _permissionBanner.hidden = YES;

        __weak typeof(self) weakSelf = self;
        _permissionBanner.onGoSettings = ^{
            if (weakSelf.onTapLimitedBanner) weakSelf.onTapLimitedBanner();
        };

        [self addSubview:_permissionBanner];

        _spaceTitleLabel = [UILabel new];
        _spaceTitleLabel.text = NSLocalizedString(@"Space To Clean", nil);
        _spaceTitleLabel.font = ASFont(17, UIFontWeightBold);
        _spaceTitleLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceTitleLabel];

        _spaceLabel = [UILabel new];
        _spaceLabel.font = ASFont(34, UIFontWeightBold);
        _spaceLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceLabel];

        _proBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _proBtn.layer.cornerRadius = SW(18);
        _proBtn.clipsToBounds = YES;
        _proBtn.titleLabel.font = SWFontS(18, UIFontWeightMedium);
        [_proBtn setTitle:NSLocalizedString(@"Pro", nil) forState:UIControlStateNormal];
        [_proBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

        UIImage *vip = [[UIImage imageNamed:@"ic_vip"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (vip) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(SW(24), SW(24)), NO, 0);
            [vip drawInRect:CGRectMake(0, 0, SW(24), SW(24))];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_proBtn setImage:scaled forState:UIControlStateNormal];
            _proBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            _proBtn.contentEdgeInsets = SWInsets(4, 6, 4, 6);
            _proBtn.imageEdgeInsets = SWInsets(0, 4, 0, 8);
            _proBtn.titleEdgeInsets = UIEdgeInsetsZero;
        } else {
            _proBtn.contentEdgeInsets = SWInsets(4, 6, 4, 6);
        }

        _proBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _proBtn.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        [self addSubview:_proBtn];

        _proGradient = [CAGradientLayer layer];
        _proGradient.colors = @[
            (id)ASRGB(111, 71, 225).CGColor,
            (id)ASRGB(46, 59, 240).CGColor
        ];
        _proGradient.startPoint = CGPointMake(0, 0.5);
        _proGradient.endPoint = CGPointMake(1, 0.5);
        _proGradient.cornerRadius = SW(18);
        [_proBtn.layer insertSublayer:_proGradient atIndex:0];

        _bar = [[ASSegmentedBarView alloc] initWithFrame:CGRectZero];
        [self addSubview:_bar];

        _legend1Dot = [UIView new];
        _legend1Dot.backgroundColor = kClutterRed();
        _legend1Dot.layer.cornerRadius = SW(3);
        [self addSubview:_legend1Dot];

        _legend1Name = [UILabel new];
        _legend1Name.text = NSLocalizedString(@"Clutter", nil);
        _legend1Name.font = ASFont(12, UIFontWeightMedium);
        _legend1Name.textColor = kTextGray();
        [self addSubview:_legend1Name];

        _legend1Value = [UILabel new];
        _legend1Value.font = ASFont(12, UIFontWeightMedium);
        _legend1Value.textColor = UIColor.blackColor;
        [self addSubview:_legend1Value];

        _legend2Dot = [UIView new];
        _legend2Dot.backgroundColor = kAppDataYellow();
        _legend2Dot.layer.cornerRadius = SW(3);
        [self addSubview:_legend2Dot];

        _legend2Name = [UILabel new];
        _legend2Name.text = NSLocalizedString(@"App&Data", nil);
        _legend2Name.font = ASFont(12, UIFontWeightMedium);
        _legend2Name.textColor = kTextGray();
        [self addSubview:_legend2Name];

        _legend2Value = [UILabel new];
        _legend2Value.font = ASFont(12, UIFontWeightMedium);
        _legend2Value.textColor = UIColor.blackColor;
        [self addSubview:_legend2Value];

        _legend3Dot = [UIView new];
        _legend3Dot.backgroundColor = kTotalGray();
        _legend3Dot.layer.cornerRadius = SW(3);
        [self addSubview:_legend3Dot];

        _legend3Name = [UILabel new];
        _legend3Name.text = NSLocalizedString(@"Total", nil);
        _legend3Name.font = ASFont(12, UIFontWeightMedium);
        _legend3Name.textColor = kTextGray();
        [self addSubview:_legend3Name];

        _legend3Value = [UILabel new];
        _legend3Value.font = ASFont(12, UIFontWeightMedium);
        _legend3Value.textColor = UIColor.blackColor;
        [self addSubview:_legend3Value];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat left = SW(30.0);

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.window.safeAreaInsets.top;

    CGFloat top = safeTop;

    CGFloat proH = SW(36.0);
    [_proBtn sizeToFit];
    CGFloat proW = MAX(SW(78.0), _proBtn.bounds.size.width + SW(10.0));
    _proBtn.frame = CGRectMake(w - left - proW, top, proW, proH);
    _proBtn.layer.cornerRadius = SW(18.0);
    _proGradient.frame = _proBtn.bounds;
    _proGradient.cornerRadius = SW(18.0);

    CGFloat titleH = SW(20.0);
    CGFloat bigH   = SW(40.0);

    CGFloat textMaxW = CGRectGetMinX(_proBtn.frame) - left - SW(10.0);
    _spaceTitleLabel.frame = CGRectMake(left, top, MAX(0, textMaxW), titleH);

    _spaceLabel.frame = CGRectMake(left,
                                   CGRectGetMaxY(_spaceTitleLabel.frame) + SW(5.0),
                                   MAX(0, textMaxW),
                                   bigH);

    _bar.frame = CGRectMake(left,
                            CGRectGetMaxY(_spaceLabel.frame) + SW(10.0),
                            w - left * 2.0,
                            SW(12.0));

    CGFloat legendsTop = CGRectGetMaxY(_bar.frame) + SW(15.0);

    CGFloat dotD = SW(8.0);
    CGFloat dotToText = SW(6.0);

    CGFloat nameH = SW(14.0);
    CGFloat valueH = SW(14.0);
    CGFloat nameToValue = SW(2.0);

    CGFloat colW = (w - left * 2.0) / 3.0;

    void (^layoutLegend)(UIView *, UILabel *, UILabel *, CGFloat) =
    ^(UIView *dot, UILabel *name, UILabel *val, CGFloat x) {
        dot.frame = CGRectMake(x, legendsTop + (nameH - dotD)/2.0, dotD, dotD);
        dot.layer.cornerRadius = dotD / 2.0;

        CGFloat tx = CGRectGetMaxX(dot.frame) + dotToText;
        CGFloat tw = colW - (tx - x);

        name.frame = CGRectMake(tx, legendsTop, tw, nameH);
        val.frame  = CGRectMake(tx, CGRectGetMaxY(name.frame) + nameToValue, tw, valueH);
    };

    layoutLegend(_legend1Dot, _legend1Name, _legend1Value, left);
    layoutLegend(_legend2Dot, _legend2Name, _legend2Value, left + colW);
    layoutLegend(_legend3Dot, _legend3Name, _legend3Value, left + colW * 2.0);
    
    CGFloat bannerTop = CGRectGetMaxY(_legend1Value.frame) + SW(18.0);
    CGFloat bannerH = SW(150.0);
    CGFloat side = SW(16.0);

    if (self.showsLimitedBanner) {
        self.permissionBanner.frame = CGRectMake(side, bannerTop, w - side * 2.0, bannerH);
    } else {
        self.permissionBanner.frame = CGRectZero;
    }
}

- (void)setShowsLimitedBanner:(BOOL)shows {
    _showsLimitedBanner = shows;
    self.permissionBanner.hidden = !shows;
    [self setNeedsLayout];
}

- (void)applyTotal:(uint64_t)total
           clutter:(uint64_t)clutter
           appData:(uint64_t)appData
              free:(uint64_t)freeBytes
       humanSizeFn:(NSString * _Nonnull (^)(uint64_t bytes))humanSize {

    _spaceLabel.text = humanSize(clutter);

    _legend1Value.text = humanSize(clutter);
    _legend2Value.text = humanSize(appData);
    _legend3Value.text = ASMarketingTotalString(total);

    if (total > 0) {
        CGFloat red = (CGFloat)clutter / (CGFloat)total;
        CGFloat yellow = (CGFloat)appData / (CGFloat)total;
        CGFloat gray = (CGFloat)freeBytes / (CGFloat)total;
        [_bar setRedRatio:red yellowRatio:yellow grayRatio:gray];
    } else {
        [_bar setRedRatio:0 yellowRatio:0 grayRatio:1];
    }
}

@end

#pragma mark - Waterfall Layout

@protocol ASWaterfallLayoutDelegate <NSObject>
- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath;

@optional
- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
shouldFullSpanAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface ASWaterfallLayout : UICollectionViewLayout
@property (nonatomic, weak) id<ASWaterfallLayoutDelegate> delegate;
@property (nonatomic) NSInteger numberOfColumns;
@property (nonatomic) CGFloat interItemSpacing;
@property (nonatomic) CGFloat lineSpacing;
@property (nonatomic) UIEdgeInsets sectionInset;
@property (nonatomic) CGFloat headerHeight;
@end

@implementation ASWaterfallLayout {
    NSMutableArray<UICollectionViewLayoutAttributes *> *_cache;
    CGFloat _contentHeight;
}

- (instancetype)init {
    if (self = [super init]) {
        _numberOfColumns = 2;
        _interItemSpacing = SW(12);
        _lineSpacing = SW(12);
        _sectionInset = SWInsets(0, 16, 16, 16);
        _headerHeight = 0;
        _cache = [NSMutableArray array];
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];
    if (!self.collectionView) return;

    [_cache removeAllObjects];
    _contentHeight = 0;

    CGFloat width = self.collectionView.bounds.size.width;
    CGFloat contentW = width - self.sectionInset.left - self.sectionInset.right;
    CGFloat colW = (contentW - (self.numberOfColumns - 1) * self.interItemSpacing) / self.numberOfColumns;

    if (self.headerHeight > 0) {
        NSIndexPath *hp = [NSIndexPath indexPathForItem:0 inSection:0];
        UICollectionViewLayoutAttributes *ha =
        [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                       withIndexPath:hp];
        ha.frame = CGRectMake(0, 0, width, self.headerHeight);
        [_cache addObject:ha];
        _contentHeight = CGRectGetMaxY(ha.frame);
    }

    NSMutableArray<NSNumber *> *colY = [NSMutableArray arrayWithCapacity:self.numberOfColumns];
    for (NSInteger c = 0; c < self.numberOfColumns; c++) {
        [colY addObject:@(_contentHeight + self.sectionInset.top)];
    }

    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    for (NSInteger i = 0; i < count; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:0];

        BOOL fullSpan = NO;
        if ([self.delegate respondsToSelector:@selector(collectionView:layout:shouldFullSpanAtIndexPath:)]) {
            fullSpan = [self.delegate collectionView:self.collectionView layout:self shouldFullSpanAtIndexPath:ip];
        }

        CGFloat h = 0;
        if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:)]) {
            h = [self.delegate collectionView:self.collectionView layout:self heightForItemAtIndexPath:ip];
        }

        if (fullSpan) {
            CGFloat y = colY[0].doubleValue;
            for (NSInteger c = 1; c < colY.count; c++) y = MAX(y, colY[c].doubleValue);

            UICollectionViewLayoutAttributes *a =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:ip];
            a.frame = CGRectMake(self.sectionInset.left, y, contentW, h);
            [_cache addObject:a];

            CGFloat nextY = CGRectGetMaxY(a.frame) + self.lineSpacing;
            for (NSInteger c = 0; c < colY.count; c++) colY[c] = @(nextY);
            _contentHeight = MAX(_contentHeight, CGRectGetMaxY(a.frame));
            continue;
        }

        NSInteger targetCol = 0;
        CGFloat minY = colY[0].doubleValue;
        for (NSInteger c = 1; c < colY.count; c++) {
            CGFloat y = colY[c].doubleValue;
            if (y < minY) { minY = y; targetCol = c; }
        }

        CGFloat x = self.sectionInset.left + targetCol * (colW + self.interItemSpacing);
        CGFloat y = colY[targetCol].doubleValue;

        UICollectionViewLayoutAttributes *a =
        [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:ip];
        a.frame = CGRectMake(x, y, colW, h);
        [_cache addObject:a];

        colY[targetCol] = @(CGRectGetMaxY(a.frame) + self.lineSpacing);
        _contentHeight = MAX(_contentHeight, CGRectGetMaxY(a.frame));
    }

    _contentHeight += self.sectionInset.bottom;
}

- (nullable NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect { NSMutableArray<UICollectionViewLayoutAttributes *> *out = [NSMutableArray array]; for (UICollectionViewLayoutAttributes *a in _cache) { if (CGRectIntersectsRect(a.frame, rect)) [out addObject:a]; } return out; } - (nullable UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath { for (UICollectionViewLayoutAttributes *a in _cache) { if (a.representedElementCategory == UICollectionElementCategorySupplementaryView && [a.representedElementKind isEqualToString:elementKind] && [a.indexPath isEqual:indexPath]) { return a; } } return nil; }

- (CGSize)collectionViewContentSize {
    CGFloat w = self.collectionView ? self.collectionView.bounds.size.width : 0;
    return CGSizeMake(w, _contentHeight);
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    if (!self.collectionView) return NO;
    return fabs(newBounds.size.width - self.collectionView.bounds.size.width) > 0.5;
}

@end

#pragma mark - Home Module Cell

@interface HomeModuleCell : UICollectionViewCell
@property (nonatomic, copy) NSString *appliedCoverKey;

@property (nonatomic) BOOL hasFinalThumb1;
@property (nonatomic) BOOL hasFinalThumb2;
@property (nonatomic, copy) NSString *coverRequestKey; // 防止扫描中重复触发同一 key 的封面请求

@property (nonatomic) BOOL isLargeCard;
@property (nonatomic, assign) PHImageRequestID videoReqId;
@property (nonatomic, assign) NSInteger renderToken;

@property (nonatomic, copy) NSArray<NSString *> *representedLocalIds;
@property (nonatomic, copy) NSString *thumbKey;

@property (nonatomic, strong) UIView *shadowContainer;
@property (nonatomic, strong) UIView *cardView;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;

@property (nonatomic, strong) UIImageView *img1;
@property (nonatomic, strong) UIImageView *img2;

@property (nonatomic, strong) UIButton *badgeBtn;
@property (nonatomic, strong) UIImageView *playIconView;

@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerLooper *looper;

@property (nonatomic, assign) PHImageRequestID reqId1;
@property (nonatomic, assign) PHImageRequestID reqId2;

@property (nonatomic) BOOL showsTwoThumbs;
@property (nonatomic) BOOL isVideoCover;

- (void)applyVM:(ASHomeModuleVM *)vm humanSizeFn:(NSString * _Nonnull (^)(uint64_t bytes))humanSize;
+ (NSString *)humanSize:(uint64_t)bytes;
- (void)stopVideoIfNeeded;
@end

@implementation HomeModuleCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.backgroundColor = UIColor.clearColor;
        _videoReqId = PHInvalidImageRequestID;
        _renderToken = 0;

        _shadowContainer = [UIView new];
        _shadowContainer.backgroundColor = UIColor.clearColor;
        _shadowContainer.layer.shadowColor = kCardShadowColor().CGColor;
        _shadowContainer.layer.shadowOpacity = 1;
        _shadowContainer.layer.shadowOffset = CGSizeMake(0, SW(2));
        _shadowContainer.layer.shadowRadius = SW(8);
        [self.contentView addSubview:_shadowContainer];

        _cardView = [UIView new];
        _cardView.backgroundColor = UIColor.whiteColor;
        _cardView.layer.cornerRadius = SW(24);
        _cardView.clipsToBounds = YES;
        [_shadowContainer addSubview:_cardView];

        _titleLabel = [UILabel new];
        _titleLabel.font = SWFontS(20, UIFontWeightRegular);
        _titleLabel.textColor = UIColor.blackColor;

        _countLabel = [UILabel new];
        _countLabel.font = SWFontS(12, UIFontWeightRegular);
        _countLabel.textColor = kTextGray();

        _img1 = [UIImageView new];
        _img2 = [UIImageView new];
        _img1.backgroundColor = ASRGB(240, 242, 247);
        _img2.backgroundColor = ASRGB(240, 242, 247);
        _img1.contentMode = UIViewContentModeScaleAspectFill;
        _img2.contentMode = UIViewContentModeScaleAspectFill;
        _img1.clipsToBounds = YES;
        _img2.clipsToBounds = YES;
        _img1.layer.cornerRadius = SW(24);
        _img2.layer.cornerRadius = SW(24);

        _badgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _badgeBtn.titleLabel.numberOfLines = 1;
        _badgeBtn.titleLabel.lineBreakMode = NSLineBreakByClipping;
        _badgeBtn.titleLabel.adjustsFontSizeToFitWidth = NO;

        _badgeBtn.backgroundColor = kBadgeBlue();
        _badgeBtn.layer.cornerRadius = SW(23);
        _badgeBtn.clipsToBounds = YES;

        _badgeBtn.titleLabel.font = SWFontS(20, UIFontWeightRegular);
        [_badgeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [_badgeBtn setTitle:@"--" forState:UIControlStateNormal];

        _badgeBtn.contentEdgeInsets = SWInsets(11, 15, 11, 18);
        _badgeBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _badgeBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

        _badgeBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        _badgeBtn.userInteractionEnabled = NO;

        UIImage *todo = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (todo) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(SW(9), SW(16)), NO, 0);
            [todo drawInRect:CGRectMake(0, 0, SW(9), SW(16))];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_badgeBtn setImage:scaled forState:UIControlStateNormal];
            _badgeBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            CGFloat spacing = SW(9.0);
            _badgeBtn.imageEdgeInsets = UIEdgeInsetsMake(0, spacing, 0, 0);
            _badgeBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, spacing);
        }

        _playIconView = [UIImageView new];
        _playIconView.image = [UIImage imageNamed:@"ic_play"];
        _playIconView.contentMode = UIViewContentModeScaleAspectFit;
        _playIconView.hidden = YES;

        [_cardView addSubview:_titleLabel];
        [_cardView addSubview:_countLabel];
        [_cardView addSubview:_img1];
        [_cardView addSubview:_img2];

        [_shadowContainer addSubview:_badgeBtn];
        _shadowContainer.clipsToBounds = NO;

        [_cardView addSubview:_playIconView];

        _reqId1 = PHInvalidImageRequestID;
        _reqId2 = PHInvalidImageRequestID;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.shadowContainer.frame = self.contentView.bounds;
    self.cardView.frame = self.shadowContainer.bounds;

    CGFloat w = self.cardView.bounds.size.width;
    CGFloat h = self.cardView.bounds.size.height;

    CGFloat pad = SW(15.0);

    self.titleLabel.frame = CGRectMake(pad, pad, w - pad * 2.0, SW(20));

    self.countLabel.frame = CGRectMake(pad,
                                       CGRectGetMaxY(self.titleLabel.frame) + SW(4),
                                       w - pad * 2.0,
                                       SW(16));

    CGFloat imgTop = CGRectGetMaxY(self.countLabel.frame) + SW(12);
    CGFloat imgBottomPad = pad;
    CGFloat imgH = MAX(0, h - imgTop - imgBottomPad);

    if (self.showsTwoThumbs) {
        CGFloat gap = SW(10.0);
        CGFloat imgW = (w - pad * 2.0 - gap) / 2.0;

        self.img1.hidden = NO;
        self.img2.hidden = NO;

        self.img1.layer.cornerRadius = SW(24);
        self.img2.layer.cornerRadius = SW(24);

        self.img1.frame = CGRectMake(pad, imgTop, imgW, imgH);
        self.img2.frame = CGRectMake(CGRectGetMaxX(self.img1.frame) + gap, imgTop, imgW, imgH);
    } else {
        self.img1.hidden = NO;
        self.img2.hidden = YES;

        if (!self.isLargeCard) {
            self.img1.layer.cornerRadius = 0;
            self.img1.frame = CGRectMake(0, imgTop, w, h - imgTop);
        } else {
            self.img1.layer.cornerRadius = SW(24);
            self.img1.frame = CGRectMake(pad, imgTop, w - pad * 2.0, imgH);
        }

        self.img2.frame = CGRectZero;
    }

    NSString *t = self.badgeBtn.currentTitle ?: @"";
    UIFont *f = self.badgeBtn.titleLabel.font ?: SWFontS(20, UIFontWeightRegular);
    CGSize textSize = [t sizeWithAttributes:@{NSFontAttributeName: f}];

    UIImage *img = [self.badgeBtn imageForState:UIControlStateNormal];
    CGSize imgSize = img ? img.size : CGSizeZero;

    CGFloat spacing = img ? SW(9.0) : 0.0;
    UIEdgeInsets in = self.badgeBtn.contentEdgeInsets;

    CGFloat badgeW = ceil(in.left + textSize.width + spacing + imgSize.width + in.right);
    CGFloat badgeH = ceil(in.top + MAX(textSize.height, imgSize.height) + in.bottom);

    if (self.isLargeCard) {
        CGFloat x = w - pad - badgeW;
        self.badgeBtn.frame = CGRectMake(x, pad - SW(3.0), badgeW, badgeH);
    } else {
        CGFloat rightInset = SW(10.0);
        CGFloat by = CGRectGetMaxY(self.img1.frame) - badgeH - rightInset;
        CGFloat bx = CGRectGetMaxX(self.img1.frame) - rightInset - badgeW;
        self.badgeBtn.frame = CGRectMake(bx, by, badgeW, badgeH);
    }

    [self.shadowContainer bringSubviewToFront:self.badgeBtn];
    [self.cardView bringSubviewToFront:self.playIconView];

    self.playIconView.hidden = !self.isVideoCover;
    self.playIconView.frame = CGRectMake(CGRectGetMinX(self.img1.frame) + SW(10),
                                         CGRectGetMinY(self.img1.frame) + SW(10),
                                         SW(18), SW(18));

    if (self.playerLayer) {
        self.playerLayer.frame = self.img1.bounds;
    }
    
    UIBezierPath *path =
        [UIBezierPath bezierPathWithRoundedRect:self.cardView.bounds
                                   cornerRadius:self.cardView.layer.cornerRadius];
    self.shadowContainer.layer.shadowPath = path.CGPath;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.renderToken += 1;
    self.videoReqId = PHInvalidImageRequestID;
    [self stopVideoIfNeeded];

    self.representedLocalIds = @[];
    self.thumbKey = nil;

    self.appliedCoverKey = nil;    

    self.reqId1 = PHInvalidImageRequestID;
    self.reqId2 = PHInvalidImageRequestID;

    self.img1.image = nil;
    self.img2.image = nil;

    self.hasFinalThumb1 = NO;
    self.hasFinalThumb2 = NO;
    self.coverRequestKey = nil;

    [self stopVideoIfNeeded];
    self.playIconView.hidden = YES;
}


- (void)stopVideoIfNeeded {
    if (self.player) [self.player pause];
    if (self.playerLayer) [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.looper = nil;
    self.player = nil;
}

- (void)applyVM:(ASHomeModuleVM *)vm humanSizeFn:(NSString * _Nonnull (^)(uint64_t bytes))humanSize {

    BOOL needLayout = NO;

    if (self.showsTwoThumbs != vm.showsTwoThumbs) { self.showsTwoThumbs = vm.showsTwoThumbs; needLayout = YES; }
    if (self.isVideoCover != vm.isVideoCover)     { self.isVideoCover = vm.isVideoCover; needLayout = YES; }

    BOOL newLarge = (vm.type == ASHomeCardTypeSimilarPhotos);
    if (self.isLargeCard != newLarge) { self.isLargeCard = newLarge; needLayout = YES; }

    if (![self.titleLabel.text ?: @"" isEqualToString:vm.title ?: @""]) {
        self.titleLabel.text = vm.title ?: @"";
    }
    if (![self.countLabel.text ?: @"" isEqualToString:vm.countText ?: @""]) {
        self.countLabel.text = vm.countText ?: @"";
    }

    NSString *sizeText = humanSize(vm.totalBytes);
    if (![[self.badgeBtn currentTitle] ?: @"" isEqualToString:sizeText ?: @""]) {
        [self.badgeBtn setTitle:sizeText forState:UIControlStateNormal];
        needLayout = YES; // badge 宽度可能变化
    }

    if (needLayout) [self setNeedsLayout];
}

+ (NSString *)humanSize:(uint64_t)bytes {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024;
    if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024;
    if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024;
    return [NSString stringWithFormat:@"%.2f GB", b];
}

@end

#pragma mark - HomeViewController

@interface HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate, ASWaterfallLayoutDelegate>
@property (nonatomic) BOOL didInitialBuild;

@property (nonatomic, strong) ASPrivatePermissionBanner *limBanner;

@property (nonatomic, strong) CAGradientLayer *topGradient;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<ASHomeModuleVM *> *modules;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic) uint64_t diskTotalBytes;
@property (nonatomic) uint64_t diskFreeBytes;
@property (nonatomic) uint64_t clutterBytes;
@property (nonatomic) uint64_t appDataBytes;

@property (nonatomic, strong) NSTimer *scanUITimer;
@property (nonatomic) BOOL pendingScanUIUpdate;
@property (nonatomic) CFTimeInterval lastScanUIFire;

@property (nonatomic, strong) NSSet<NSString *> *allCleanableIds;
@property (nonatomic) uint64_t allCleanableBytes;

@property (nonatomic, strong) dispatch_queue_t homeBuildQueue;
@property (nonatomic) CGFloat lastHeaderHeight;

@property (nonatomic, strong) NSUUID *scanProgressToken;

@property (nonatomic) BOOL isLimitedAuth;

@property(nonatomic, assign) ASPhotoAuthLevel lastAppliedAuthLevel;
@property(nonatomic, assign) BOOL lastAppliedLimited;

@property(nonatomic, strong) NSCache<NSString*, PHAsset*> *assetCache;
@property(nonatomic, strong) dispatch_queue_t photoFetchQueue;
@end

@implementation HomeViewController


- (PHAuthorizationStatus)currentPHAuthStatus {
    if (@available(iOS 14.0, *)) {
        return [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [PHPhotoLibrary authorizationStatus];
#pragma clang diagnostic pop
    }
}

- (ASPhotoAuthLevel)mapToAuthLevel:(PHAuthorizationStatus)st {
    if (st == PHAuthorizationStatusAuthorized) return ASPhotoAuthLevelFull;
    if (st == PHAuthorizationStatusLimited)    return ASPhotoAuthLevelLimited;
    return ASPhotoAuthLevelNone;
}

- (ASPhotoAuthLevel)storedAuthLevel {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if ([ud objectForKey:kASLastPhotoAuthLevelKey] == nil) return ASPhotoAuthLevelUnknown;
    return (ASPhotoAuthLevel)[ud integerForKey:kASLastPhotoAuthLevelKey];
}

- (void)storeAuthLevel:(ASPhotoAuthLevel)lvl {
    [NSUserDefaults.standardUserDefaults setInteger:lvl forKey:kASLastPhotoAuthLevelKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)hasPhotoAccess {
    PHAuthorizationStatus st = [self currentPHAuthStatus];
    return (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited);
}

- (BOOL)isNotDetermined {
    return [self currentPHAuthStatus] == PHAuthorizationStatusNotDetermined;
}

- (void)dealloc {
    if (self.scanProgressToken) {
         [[ASPhotoScanManager shared] removeProgressObserver:self.scanProgressToken];
         self.scanProgressToken = nil;
     }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.scanUITimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self resumeVisibleVideoCovers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PHAuthorizationStatus st = [self currentPHAuthStatus];
    [self updatePermissionUIForStatus:st];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pauseVisibleVideoCovers];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self computeDiskSpace];
    
    self.assetCache = [NSCache new];
    self.photoFetchQueue = dispatch_queue_create("com.xiaoxu2.home.photoFetch", DISPATCH_QUEUE_CONCURRENT);

    self.homeBuildQueue = dispatch_queue_create("com.xiaoxu2.home.build", DISPATCH_QUEUE_SERIAL);
    self.lastAppliedAuthLevel = ASPhotoAuthLevelUnknown;
    self.lastAppliedLimited = NO;

    self.imgMgr = [[PHCachingImageManager alloc] init];
    self.scanMgr = [ASPhotoScanManager shared];

    self.scanProgressToken = [[ASPhotoScanManager shared] addProgressObserver:^(ASScanSnapshot *snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (snapshot.state == ASScanStateScanning) {
                [self scheduleScanUIUpdateCoalesced];
            } else {
                [self.scanUITimer invalidate];
                self.scanUITimer = nil;
                self.pendingScanUIUpdate = NO;
                [self rebuildModulesAndReload];
            }
        });
    }];
    [self bootstrapScanFlow];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAppWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAppDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
     
}

- (void)onAppWillResignActive:(NSNotification *)n {
    [self pauseVisibleVideoCovers];
}

- (void)onAppDidBecomeActive:(NSNotification *)n {
    [self resumeVisibleVideoCovers];
}

- (void)onTapPermissionGate {
    PHAuthorizationStatus st = [self currentPHAuthStatus];

    // 1) 未决定：直接弹系统授权
    if (st == PHAuthorizationStatusNotDetermined) {
        [self bootstrapScanFlow];
        return;
    }

    // 2) Limited：弹“选择更多照片”
    if (@available(iOS 14.0, *)) {
        if (st == PHAuthorizationStatusLimited) {
            [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:self];
            return;
        }
    }

    // 3) Denied/Restricted：跳系统设置
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)bootstrapScanFlow {
    __weak typeof(self) weakSelf = self;

    [self.scanMgr startupForHomeWithProgress:^(ASScanSnapshot *snap) {
        // 扫描开始/进行中，也顺便刷新一次权限UI（防止授权后不切换）
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PHAuthorizationStatus st = [self currentPHAuthStatus];
            [self updatePermissionUIForStatus:st];
        });
    } completion:^(ASScanSnapshot *snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PHAuthorizationStatus st = [self currentPHAuthStatus];
            [self updatePermissionUIForStatus:st];

            // 有权限后，强制重建一次模块（避免仍停留在 no-auth cell）
            if ([self hasPhotoAccess]) {
                [self rebuildModulesAndReload];
            }
        });
    } showPermissionPlaceholder:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PHAuthorizationStatus st = [self currentPHAuthStatus];
            [self updatePermissionUIForStatus:st];
            [self rebuildModulesAndReload];
        });
    }];
}


- (void)updatePermissionUIForStatus:(PHAuthorizationStatus)st {

    ASPhotoAuthLevel lvl = [self mapToAuthLevel:st];
    BOOL limited = (@available(iOS 14.0, *) && st == PHAuthorizationStatusLimited);

    BOOL authChanged = (self.lastAppliedAuthLevel != lvl) || (self.lastAppliedLimited != limited);

    self.lastAppliedAuthLevel = lvl;
    self.lastAppliedLimited = limited;
    self.isLimitedAuth = limited;

    self.cv.hidden = NO;

    // 布局/头部高度可能跟权限有关，仍然更新
    [self applyLayoutForCurrentAuth];
    [self invalidateHeaderLayoutIfNeeded];

    // 只有权限/limited 真变化才 reload
    if (authChanged) {
        [self ensureModulesIfNeeded];        // ✅ 新增
        [self resetCoverStateForAuthChange];
        [self.cv reloadData];
    } else {
        // 不 reload 的情况下，至少把 header 文案/ banner 状态更新一下
        [self updateHeaderDuringScanning];
    }
}

- (void)applyLayoutForCurrentAuth {
    ASWaterfallLayout *wf = (ASWaterfallLayout *)self.cv.collectionViewLayout;
    if (![wf isKindOfClass:ASWaterfallLayout.class]) return;

    if (![self hasPhotoAccess]) {
        wf.sectionInset = UIEdgeInsetsMake(0, 0, SW(16), 0);
        wf.interItemSpacing = 0;
        wf.lineSpacing = SW(12);
    } else {
        wf.sectionInset = UIEdgeInsetsMake(0, kHomeSideInset, kHomeSideInset, kHomeSideInset);
        wf.interItemSpacing = kHomeGridGap;
        wf.lineSpacing = kHomeGridGap;
    }

    CGFloat newH = [self collectionView:self.cv layout:wf referenceSizeForHeaderInSection:0].height;
    if (fabs(wf.headerHeight - newH) > 0.5) wf.headerHeight = newH;

    [wf invalidateLayout];
}

- (void)invalidateHeaderLayoutIfNeeded {
    ASWaterfallLayout *wf = (ASWaterfallLayout *)self.cv.collectionViewLayout;
    if (![wf isKindOfClass:ASWaterfallLayout.class]) return;

    CGFloat newH = [self collectionView:self.cv layout:wf referenceSizeForHeaderInSection:0].height;
    if (fabs(wf.headerHeight - newH) > 0.5) {
        wf.headerHeight = newH;
        [wf invalidateLayout];
    }
}

#pragma mark - UI

- (void)setupUI {
    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];

    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0]; // #E0E0E0FF
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0]; // #008DFF00 (透明)

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    ASWaterfallLayout *layout = [ASWaterfallLayout new];
    layout.delegate = (id)self;
    layout.numberOfColumns = 2;
    layout.interItemSpacing = kHomeGridGap;
    layout.lineSpacing = kHomeGridGap;
    layout.sectionInset = UIEdgeInsetsMake(0, kHomeSideInset, kHomeSideInset, kHomeSideInset);

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];

    [self.cv registerClass:ASNoAuthCell.class forCellWithReuseIdentifier:@"ASNoAuthCell"];

    if (@available(iOS 11.0, *)) {
        self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.automaticallyAdjustsScrollViewInsets = NO;
#pragma clang diagnostic pop
    }

    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;

    [self.cv registerClass:HomeModuleCell.class forCellWithReuseIdentifier:@"HomeModuleCell"];
    [self.cv registerClass:ASHomeHeaderView.class
forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
       withReuseIdentifier:@"ASHomeHeaderView"];

    [self.view addSubview:self.cv];
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.cv.frame = self.view.bounds;
    [self applyLayoutForCurrentAuth];

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat gradientH = safeTop + SW(402.0);
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);

    UIEdgeInsets safe = self.view.safeAreaInsets;
    self.cv.contentInset = SWInsets(20, 0, safe.bottom + 70, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;
}


#pragma mark - Data Build

- (NSString *)contentKeyForVM:(ASHomeModuleVM *)vm {
    return [NSString stringWithFormat:@"%lu|%@|%llu|%lu|%@|%d|%d",
            (unsigned long)vm.type,
            vm.thumbKey ?: @"",
            (unsigned long long)vm.totalBytes,
            (unsigned long)vm.totalCount,
            vm.countText ?: @"",
            vm.showsTwoThumbs,
            vm.isVideoCover];
}

- (void)refreshVisibleCellsAndCovers {
    NSArray<NSIndexPath *> *vis = [self.cv indexPathsForVisibleItems];
    for (NSIndexPath *ip in vis) {
        if (ip.item >= self.modules.count) continue;

        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (![cell isKindOfClass:HomeModuleCell.class]) continue;

        ASHomeModuleVM *vm = self.modules[ip.item];

        [cell applyVM:vm humanSizeFn:^NSString *(uint64_t bytes) {
            return [HomeModuleCell humanSize:bytes];
        }];

        [self requestCoverIfNeededForCell:cell vm:vm indexPath:ip];
    }
}

#pragma mark - Helpers

- (void)ensureModulesIfNeeded {
    if (![self hasPhotoAccess]) return;
    if (self.modules.count > 0) return;

    // 扫描中先给 6 个占位模块，避免第二次进来 reload 后 item=0
    self.modules = [self buildModulesFromManagerAndComputeClutterIsFinal:NO];
    [self.cv reloadData];
    [self updateHeaderDuringScanning];
}

- (void)resetHomeCell:(HomeModuleCell *)cell vm:(ASHomeModuleVM *)vm {
    [self cancelCellRequests:cell];
    [cell stopVideoIfNeeded];

    cell.appliedCoverKey = nil;
    cell.representedLocalIds = @[];
    cell.coverRequestKey = nil;

    cell.hasFinalThumb1 = NO;
    cell.hasFinalThumb2 = NO;

    cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
    cell.img2.image = (vm.showsTwoThumbs ? [UIImage imageNamed:@"ic_placeholder"] : nil);
    cell.playIconView.hidden = YES;
}

- (void)rebuildModulesAndReload {
    [self rebuildModulesAndReloadIsFinal:YES];
}

- (void)rebuildModulesAndReloadIsFinal:(BOOL)isFinal {
    CFTimeInterval t0 = CFAbsoluteTimeGetCurrent();

    if (self.scanMgr.snapshot.state == ASScanStateScanning && isFinal) {
        [self scheduleScanUIUpdateCoalesced];
        ASLogCost(@"TOTAL rebuildModulesAndReload (scanning)", t0);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.homeBuildQueue, ^{
        @autoreleasepool {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [self computeDiskSpace];

            NSArray<ASHomeModuleVM *> *newMods =
            [self buildModulesFromManagerAndComputeClutterIsFinal:isFinal];

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self2 = weakSelf;
                if (!self2) return;

                NSArray<ASHomeModuleVM *> *old = self2.modules ?: @[];
                self2.modules = newMods;

                if (old.count == 0 || old.count != newMods.count) {
                    [self2.cv reloadData];
                } else {
                    NSMutableArray<NSIndexPath *> *reloadIPs = [NSMutableArray array];
                    for (NSInteger i = 0; i < newMods.count; i++) {
                        NSString *ok = [self2 contentKeyForVM:old[i]];
                        NSString *nk = [self2 contentKeyForVM:newMods[i]];
                        if (![ok isEqualToString:nk]) {
                            [reloadIPs addObject:[NSIndexPath indexPathForItem:i inSection:0]];
                        }
                    }
                    if (reloadIPs.count) {
                        [UIView performWithoutAnimation:^{
                            [self2.cv reloadItemsAtIndexPaths:reloadIPs];
                        }];
                    }
                }

                [self2 updateHeaderDuringScanning];
                [self2 refreshVisibleCellsAndCovers];

                ASLogCost(@"TOTAL rebuildModulesAndReload (async)", t0);
            });
        }
    });
}

- (NSString *)coverKeyForVM:(ASHomeModuleVM *)vm {
    NSString *k = vm.thumbKey ?: @"";
    return [NSString stringWithFormat:@"%lu|%@", (unsigned long)vm.type, k];
}

- (BOOL)as_allLocalIdsValid:(NSArray<NSString *> *)ids {
    if (ids.count == 0) return NO;
    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    return fr.count == ids.count;
}

- (void)preserveCoversFromOld:(NSArray<ASHomeModuleVM *> *)oldMods
                        toNew:(NSArray<ASHomeModuleVM *> *)newMods {

    if (oldMods.count == 0 || newMods.count == 0) return;

    NSMutableDictionary<NSNumber *, ASHomeModuleVM *> *oldByType = [NSMutableDictionary dictionary];
    for (ASHomeModuleVM *o in oldMods) {
        oldByType[@(o.type)] = o;
    }

    for (ASHomeModuleVM *n in newMods) {
        ASHomeModuleVM *o = oldByType[@(n.type)];
        if (!o) continue;

        if (o.thumbLocalIds.count > 0 && [self as_allLocalIdsValid:o.thumbLocalIds]) {
            n.thumbLocalIds = o.thumbLocalIds;
            n.thumbKey = o.thumbKey;
            n.didSetThumb = o.didSetThumb;
        } else {
            if (n.thumbLocalIds.count > 0) n.didSetThumb = YES;
        }
    }
}

- (void)resetCoverStateForAuthChange {
    for (ASHomeModuleVM *vm in self.modules) {
        vm.didSetThumb = NO;
        vm.thumbLocalIds = @[];
        vm.thumbKey = @"";
    }

    for (NSIndexPath *ip in [self.cv indexPathsForVisibleItems]) {
        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (![cell isKindOfClass:HomeModuleCell.class]) continue;
        [self cancelCellRequests:cell];
        [cell stopVideoIfNeeded];

        cell.hasFinalThumb1 = NO;
        cell.hasFinalThumb2 = NO;
        cell.coverRequestKey = nil;

        cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
        cell.img2.image = [UIImage imageNamed:@"ic_placeholder"];
    }
}

- (void)computeDiskSpace {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    uint64_t total = [attrs[NSFileSystemSize] unsignedLongLongValue];
    uint64_t free  = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
    self.diskTotalBytes = total;
    self.diskFreeBytes = free;
}

#pragma mark - Scan UI Throttle

- (void)scheduleScanUIUpdateCoalesced {
    self.pendingScanUIUpdate = YES;

    if (!self.scanUITimer) {
        self.scanUITimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                           target:self
                                                         selector:@selector(handleScanUITimerFire)
                                                         userInfo:nil
                                                          repeats:YES];
        self.scanUITimer.tolerance = 0.2;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self hasPhotoAccess];
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self hasPhotoAccess];
}

#pragma mark - Build scan UI snapshot (background-safe)

- (ASScanUIResult *)buildScanUIResultDuringScanning {
    ASScanUIResult *r = [ASScanUIResult new];

    // 1) disk
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfFileSystemForPath:NSHomeDirectory()
                           error:nil];
    uint64_t total = [attrs[NSFileSystemSize] unsignedLongLongValue];
    uint64_t free  = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
    r.diskTotal = total;
    r.diskFree  = free;

    // 2) input from scan manager (no PhotoKit fetch here)
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];

    NSArray<ASAssetModel *> *shots  = self.scanMgr.screenshots      ?: @[];
    NSArray<ASAssetModel *> *recs   = self.scanMgr.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigs   = self.scanMgr.bigVideos        ?: @[];
    NSArray<ASAssetModel *> *blurs  = self.scanMgr.blurryPhotos     ?: @[];
    NSArray<ASAssetModel *> *others = self.scanMgr.otherPhotos      ?: @[];

    // 3) unique clutter bytes (by localId)
    NSMutableDictionary<NSString *, NSNumber *> *uniqBytesById = [NSMutableDictionary dictionary];

    void (^addUniq)(ASAssetModel *m) = ^(ASAssetModel *m) {
        if (!m.localId.length) return;
        if (!uniqBytesById[m.localId]) {
            uniqBytesById[m.localId] = @(m.fileSizeBytes);
        }
    };

    // helpers: pick thumbs quickly
    NSArray<NSString *> *(^thumbsFromFirstGroup)(NSArray<ASAssetGroup *> *, ASGroupType, NSUInteger) =
    ^NSArray<NSString *> *(NSArray<ASAssetGroup *> *groups, ASGroupType type, NSUInteger maxCount) {
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;
            if (g.assets.count < 2) continue;
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                [ids addObject:m.localId];
                if (ids.count == maxCount) break;
            }
            if (ids.count) return ids;
        }
        return @[];
    };

    NSString *(^firstLocalId)(NSArray<ASAssetModel *> *) =
    ^NSString *(NSArray<ASAssetModel *> *arr) {
        for (ASAssetModel *m in arr) {
            if (m.localId.length) return m.localId;
        }
        return (NSString *)nil;
    };

    // 4) Similar Images
    {
        uint64_t bytes = 0;
        NSUInteger cnt = 0;

        for (ASAssetGroup *g in sim) {
            if (g.type != ASGroupTypeSimilarImage) continue;
            if (g.assets.count < 2) continue;
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                cnt += 1;
                bytes += m.fileSizeBytes;
                addUniq(m);
            }
        }
        r.simBytes  = bytes;
        r.simCount  = cnt;
        r.simThumbs = thumbsFromFirstGroup(sim, ASGroupTypeSimilarImage, 2);
    }

    // 5) Duplicate Images
    {
        uint64_t bytes = 0;
        NSUInteger cnt = 0;

        for (ASAssetGroup *g in dup) {
            if (g.type != ASGroupTypeDuplicateImage) continue;
            if (g.assets.count < 2) continue;
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                cnt += 1;
                bytes += m.fileSizeBytes;
                addUniq(m);
            }
        }
        r.dupBytes  = bytes;
        r.dupCount  = cnt;
        r.dupThumbs = thumbsFromFirstGroup(dup, ASGroupTypeDuplicateImage, 2);
    }

    // 6) Screenshots / Blurry / Other
    {
        uint64_t bytes = 0; NSUInteger cnt = 0;
        for (ASAssetModel *m in shots) { if (!m.localId.length) continue; cnt++; bytes += m.fileSizeBytes; addUniq(m); }
        r.shotsBytes = bytes;
        r.shotsCount = cnt;
        NSString *lid = firstLocalId(shots);
        r.shotsThumb = lid ? @[lid] : @[];
    }
    {
        uint64_t bytes = 0; NSUInteger cnt = 0;
        for (ASAssetModel *m in blurs) { if (!m.localId.length) continue; cnt++; bytes += m.fileSizeBytes; addUniq(m); }
        r.blurBytes = bytes;
        r.blurCount = cnt;
        NSString *lid = firstLocalId(blurs);
        r.blurThumb = lid ? @[lid] : @[];
    }
    {
        uint64_t bytes = 0; NSUInteger cnt = 0;
        for (ASAssetModel *m in others) { if (!m.localId.length) continue; cnt++; bytes += m.fileSizeBytes; addUniq(m); }
        r.otherBytes = bytes;
        r.otherCount = cnt;
        NSString *lid = firstLocalId(others);
        r.otherThumb = lid ? @[lid] : @[];
    }

    // 7) Videos (simVid + dupVid + bigs + recs)
    {
        uint64_t bytes = 0;
        NSUInteger cnt = 0;

        // similar video groups
        for (ASAssetGroup *g in sim) {
            if (g.type != ASGroupTypeSimilarVideo) continue;
            if (g.assets.count < 2) continue;
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                cnt += 1;
                bytes += m.fileSizeBytes;
                addUniq(m);
            }
        }
        // duplicate video groups
        for (ASAssetGroup *g in dup) {
            if (g.type != ASGroupTypeDuplicateVideo) continue;
            if (g.assets.count < 2) continue;
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                cnt += 1;
                bytes += m.fileSizeBytes;
                addUniq(m);
            }
        }
        // big videos
        for (ASAssetModel *m in bigs) {
            if (!m.localId.length) continue;
            cnt += 1;
            bytes += m.fileSizeBytes;
            addUniq(m);
        }
        // screen recordings
        for (ASAssetModel *m in recs) {
            if (!m.localId.length) continue;
            cnt += 1;
            bytes += m.fileSizeBytes;
            addUniq(m);
        }

        r.vBytes = bytes;
        r.vCount = cnt;

        // video cover：优先 bigs -> recs -> 任意一个视频组里的第一个
        NSString *cover = firstLocalId(bigs);
        if (!cover) cover = firstLocalId(recs);
        if (!cover) {
            // fallback: first from similar/dup video group assets
            for (ASAssetGroup *g in sim) {
                if (g.type != ASGroupTypeSimilarVideo || g.assets.count < 1) continue;
                cover = firstLocalId(g.assets);
                if (cover) break;
            }
        }
        if (!cover) {
            for (ASAssetGroup *g in dup) {
                if (g.type != ASGroupTypeDuplicateVideo || g.assets.count < 1) continue;
                cover = firstLocalId(g.assets);
                if (cover) break;
            }
        }
        r.videoThumb = cover ? @[cover] : @[];
    }

    // 8) clutter/appData
    uint64_t uniqBytes = 0;
    for (NSNumber *n in uniqBytesById.allValues) uniqBytes += n.unsignedLongLongValue;

    r.clutterBytes = uniqBytes;

    uint64_t used = (total > free) ? (total - free) : 0;
    r.appDataBytes = (used > uniqBytes) ? (used - uniqBytes) : 0;

    return r;
}


- (void)handleScanUITimerFire {
    if (!self.pendingScanUIUpdate) return;
    if (self.scanMgr.snapshot.state != ASScanStateScanning) {
        self.pendingScanUIUpdate = NO;
        [self.scanUITimer invalidate];
        self.scanUITimer = nil;
        return;
    }

    // 你现在用 0.25s timer + 0.6s gate，建议直接把 timer 改成 0.6s（见后面 D）
    self.pendingScanUIUpdate = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.homeBuildQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        ASScanUIResult *r = [self buildScanUIResultDuringScanning]; // 重活：后台算

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) return;
            if (self2.scanMgr.snapshot.state != ASScanStateScanning) return;

            // 只在主线程赋值 + 刷 UI
            self2.diskTotalBytes = r.diskTotal;
            self2.diskFreeBytes  = r.diskFree;
            self2.clutterBytes   = r.clutterBytes;
            self2.appDataBytes   = r.appDataBytes;

            // 更新 modules（modules 只有 6 个，主线程改很轻）
            for (ASHomeModuleVM *vm in self2.modules) {
                switch (vm.type) {
                    case ASHomeCardTypeSimilarPhotos:
                        vm.totalBytes = r.simBytes; vm.totalCount = r.simCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil),(unsigned long)r.simCount];
                        if (!vm.didSetThumb && r.simThumbs.count) { vm.thumbLocalIds = r.simThumbs; vm.thumbKey = [r.simThumbs componentsJoinedByString:@"|"]; vm.didSetThumb = YES; }
                        break;
                    case ASHomeCardTypeDuplicatePhotos:
                        vm.totalBytes = r.dupBytes; vm.totalCount = r.dupCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil),(unsigned long)r.dupCount];
                        if (!vm.didSetThumb && r.dupThumbs.count) { vm.thumbLocalIds = r.dupThumbs; vm.thumbKey = [r.dupThumbs componentsJoinedByString:@"|"]; vm.didSetThumb = YES; }
                        break;
                    case ASHomeCardTypeScreenshots:
                        vm.totalBytes = r.shotsBytes; vm.totalCount = r.shotsCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil),(unsigned long)r.shotsCount];
                        if (!vm.didSetThumb && r.shotsThumb.count) { vm.thumbLocalIds = r.shotsThumb; vm.thumbKey = r.shotsThumb.firstObject; vm.didSetThumb = YES; }
                        break;
                    case ASHomeCardTypeBlurryPhotos:
                        vm.totalBytes = r.blurBytes; vm.totalCount = r.blurCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil),(unsigned long)r.blurCount];
                        if (!vm.didSetThumb && r.blurThumb.count) { vm.thumbLocalIds = r.blurThumb; vm.thumbKey = r.blurThumb.firstObject; vm.didSetThumb = YES; }
                        break;
                    case ASHomeCardTypeOtherPhotos:
                        vm.totalBytes = r.otherBytes; vm.totalCount = r.otherCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil),(unsigned long)r.otherCount];
                        if (!vm.didSetThumb && r.otherThumb.count) { vm.thumbLocalIds = r.otherThumb; vm.thumbKey = r.otherThumb.firstObject; vm.didSetThumb = YES; }
                        break;
                    case ASHomeCardTypeVideos:
                        vm.totalBytes = r.vBytes; vm.totalCount = r.vCount;
                        vm.countText  = [NSString stringWithFormat:NSLocalizedString(@"%lu Videos", nil),(unsigned long)r.vCount];
                        if (!vm.didSetThumb && r.videoThumb.count) { vm.thumbLocalIds = r.videoThumb; vm.thumbKey = r.videoThumb.firstObject; vm.didSetThumb = YES; }
                        break;
                }
            }

            [self2 updateHeaderDuringScanning];

            // 刷可见 cell 文案/封面（见 B/C：封面也要降载）
            [self2 refreshVisibleCellsAndCovers];
        });
    });
}

- (void)requestCoverIfNeededForCell:(HomeModuleCell *)cell
                                 vm:(ASHomeModuleVM *)vm
                          indexPath:(NSIndexPath *)indexPath {

    if (![self hasPhotoAccess]) return;

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    NSString *coverKey = [self coverKeyForVM:vm];
    BOOL sameKey = (cell.appliedCoverKey && [cell.appliedCoverKey isEqualToString:coverKey]);

    if (sameKey && vm.isVideoCover) {
        // 同一个 coverKey：如果 player 丢了（前后台/复用/系统回收），要重建
        if (!cell.player || !cell.playerLayer) {
            // 走下面正常流程，会 loadVideoPreviewForVM
        } else {
            // player 还在：确保恢复播放
            [cell.player play];
            return;
        }
    }
    
    if (sameKey) {
        BOOL inFlight = (cell.reqId1 != PHInvalidImageRequestID) ||
                        (cell.reqId2 != PHInvalidImageRequestID) ||
                        (cell.videoReqId != PHInvalidImageRequestID);
        if (inFlight) return;

        BOOL hasAllFinal = cell.hasFinalThumb1 && (!vm.showsTwoThumbs || cell.hasFinalThumb2);
        if (hasAllFinal) return;

    } else {
        [self cancelCellRequests:cell];
        [cell stopVideoIfNeeded];

        cell.hasFinalThumb1 = NO;
        cell.hasFinalThumb2 = NO;

        cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
        cell.img2.image = (vm.showsTwoThumbs ? [UIImage imageNamed:@"ic_placeholder"] : nil);
    }

    cell.appliedCoverKey = coverKey;
    cell.thumbKey = coverKey;               
    cell.representedLocalIds = ids;

    [cell setNeedsLayout];
//    [cell layoutIfNeeded];

    if (vm.isVideoCover) {
        [self loadVideoPreviewForVM:vm intoCell:cell atIndexPath:indexPath];
    } else {
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
    }
}

- (void)updateHeaderDuringScanning {
    ASHomeHeaderView *hv = (ASHomeHeaderView *)[self.cv supplementaryViewForElementKind:UICollectionElementKindSectionHeader
                                                                            atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    if (![hv isKindOfClass:ASHomeHeaderView.class]) return;

    [hv applyTotal:self.diskTotalBytes
           clutter:self.clutterBytes
           appData:self.appDataBytes
              free:self.diskFreeBytes
       humanSizeFn:^NSString * _Nonnull(uint64_t bytes) {
        return [HomeModuleCell humanSize:bytes];
    }];
}

- (NSArray<NSString *> *)thumbsFromFirstGroup:(NSArray<ASAssetGroup *> *)groups
                                        type:(ASGroupType)type
                                    maxCount:(NSUInteger)maxCount {
    for (ASAssetGroup *g in groups) {
        if (g.type != type) continue;
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (ASAssetModel *m in g.assets) {
            if (!m.localId.length) continue;
            [ids addObject:m.localId];
            if (ids.count == maxCount) break;
        }
        if (ids.count >= 1) return ids;
    }
    return @[];
}

#pragma mark - Final Build (finished 时做存在性校验，确保封面/计数准确)

- (NSDate *)as_assetBestDate:(PHAsset *)a {
    return a.creationDate ?: a.modificationDate ?: [NSDate distantPast];
}

- (NSArray<NSString *> *)as_pickNewestLocalIds:(NSArray<NSString *> *)localIds limit:(NSUInteger)limit {
    if (limit == 0 || localIds.count == 0) return @[];

    NSUInteger cap = MIN(localIds.count, 300);
    NSArray<NSString *> *cands = [localIds subarrayWithRange:NSMakeRange(0, cap)];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:cands options:nil];
    if (fr.count == 0) return @[];

    NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:fr.count];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [arr addObject:obj];
    }];

    [arr sortUsingComparator:^NSComparisonResult(PHAsset *a, PHAsset *b) {
        return [[self as_assetBestDate:b] compare:[self as_assetBestDate:a]];
    }];

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (PHAsset *a in arr) {
        if (a.localIdentifier.length) {
            [out addObject:a.localIdentifier];
            if (out.count == limit) break;
        }
    }
    return out;
}
- (NSArray<NSString *> *)as_thumbsFromNewestGroup:(NSArray<ASAssetGroup *> *)groups
                                           type:(ASGroupType)type
                                       maxCount:(NSUInteger)maxCount
                                        isValid:(BOOL(^)(NSString *lid))isValidId {

    if (groups.count == 0 || maxCount == 0) return @[];

    NSMutableArray<NSString *> *repIds = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *groupIds = [NSMutableArray array];

    for (ASAssetGroup *g in groups) {
        if (g.type != type) continue;

        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (ASAssetModel *m in g.assets) {
            if (!m.localId.length) continue;
            if (isValidId && !isValidId(m.localId)) continue;
            [ids addObject:m.localId];
        }
        if (ids.count < 2) continue;

        [repIds addObject:ids.firstObject];
        [groupIds addObject:ids];
    }

    if (repIds.count == 0) return @[];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:repIds options:nil];
    if (fr.count == 0) {
        return [self as_pickNewestLocalIds:groupIds.firstObject limit:maxCount];
    }

    NSMutableDictionary<NSString *, NSDate *> *dateById = [NSMutableDictionary dictionary];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) dateById[obj.localIdentifier] = [self as_assetBestDate:obj];
    }];

    NSInteger bestIdx = 0;
    NSDate *bestDate = [NSDate distantPast];

    for (NSInteger i = 0; i < repIds.count; i++) {
        NSString *rid = repIds[i];
        NSDate *d = dateById[rid] ?: [NSDate distantPast];
        if ([d compare:bestDate] == NSOrderedDescending) {
            bestDate = d;
            bestIdx = i;
        }
    }

    NSArray<NSString *> *bestGroupAllIds = groupIds[bestIdx];
    return [self as_pickNewestLocalIds:bestGroupAllIds limit:maxCount];
}

- (NSArray<ASHomeModuleVM *> *)buildModulesFromManagerAndComputeClutterIsFinal:(BOOL)isFinal {

    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups   ?: @[];

    NSArray<ASAssetModel *> *shots  = self.scanMgr.screenshots       ?: @[];
    NSArray<ASAssetModel *> *recs   = self.scanMgr.screenRecordings  ?: @[];
    NSArray<ASAssetModel *> *bigs   = self.scanMgr.bigVideos         ?: @[];
    NSArray<ASAssetModel *> *blurs  = self.scanMgr.blurryPhotos      ?: @[];
    NSArray<ASAssetModel *> *others = self.scanMgr.otherPhotos       ?: @[];

    NSMutableSet<NSString *> *existIdSet = nil;
    if (isFinal) {
        NSMutableOrderedSet<NSString *> *candidate = [NSMutableOrderedSet orderedSet];

        void (^collectIdsFromModels)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
            for (ASAssetModel *m in arr) {
                if (m.localId.length) [candidate addObject:m.localId];
            }
        };
        void (^collectIdsFromGroups)(NSArray<ASAssetGroup *> *) = ^(NSArray<ASAssetGroup *> *groups) {
            for (ASAssetGroup *g in groups) {
                for (ASAssetModel *m in g.assets) {
                    if (m.localId.length) [candidate addObject:m.localId];
                }
            }
        };

        collectIdsFromGroups(sim);
        collectIdsFromGroups(dup);
        collectIdsFromModels(shots);
        collectIdsFromModels(recs);
        collectIdsFromModels(bigs);
        collectIdsFromModels(blurs);
        collectIdsFromModels(others);

        NSArray<NSString *> *candidateIds = candidate.array;
        if (candidateIds.count > 0) {
            PHFetchResult<PHAsset *> *existFR = [PHAsset fetchAssetsWithLocalIdentifiers:candidateIds options:nil];
            existIdSet = [NSMutableSet setWithCapacity:existFR.count];
            [existFR enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (obj.localIdentifier.length) [existIdSet addObject:obj.localIdentifier];
            }];
        } else {
            existIdSet = [NSMutableSet set];
        }
    }

    BOOL (^isValidId)(NSString *) = ^BOOL(NSString *lid) {
        if (!lid.length) return NO;
        if (!existIdSet) return YES;
        return [existIdSet containsObject:lid];
    };

    NSArray<ASAssetModel *> *(^flattenGroups)(NSArray<ASAssetGroup *> *, ASGroupType) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetGroup *> *groups, ASGroupType type) {
        NSMutableArray<ASAssetModel *> *arr = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;

            NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (isValidId(m.localId)) [valid addObject:m];
            }
            if (valid.count < 2) continue;
            [arr addObjectsFromArray:valid];
        }
        return arr;
    };

    NSArray<ASAssetModel *> *(^filterValidModels)(NSArray<ASAssetModel *> *) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetModel *> *arr) {
        NSMutableArray<ASAssetModel *> *out = [NSMutableArray array];
        for (ASAssetModel *m in arr) {
            if (isValidId(m.localId)) [out addObject:m];
        }
        return out;
    };

    NSArray<ASAssetModel *> *simImg = flattenGroups(sim, ASGroupTypeSimilarImage);
    NSArray<ASAssetModel *> *dupImg = flattenGroups(dup, ASGroupTypeDuplicateImage);
    NSArray<ASAssetModel *> *simVid = flattenGroups(sim, ASGroupTypeSimilarVideo);
    NSArray<ASAssetModel *> *dupVid = flattenGroups(dup, ASGroupTypeDuplicateVideo);

    shots  = filterValidModels(shots);
    recs   = filterValidModels(recs);
    bigs   = filterValidModels(bigs);
    blurs  = filterValidModels(blurs);
    others = filterValidModels(others);

    NSMutableDictionary<NSString*, NSNumber*> *bytesById = [NSMutableDictionary dictionary];
    void (^collectUniq)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
        for (ASAssetModel *m in arr) {
            if (!isValidId(m.localId)) continue;
            if (!bytesById[m.localId]) bytesById[m.localId] = @(m.fileSizeBytes);
        }
    };

    collectUniq(simImg);
    collectUniq(dupImg);
    collectUniq(simVid);
    collectUniq(dupVid);
    collectUniq(shots);
    collectUniq(recs);
    collectUniq(bigs);
    collectUniq(blurs);
    collectUniq(others);

    uint64_t uniqBytes = 0;
    for (NSNumber *n in bytesById.allValues) uniqBytes += n.unsignedLongLongValue;

    self.allCleanableIds = [NSSet setWithArray:bytesById.allKeys];
    self.allCleanableBytes = uniqBytes;

    self.clutterBytes = uniqBytes;

    uint64_t used = (self.diskTotalBytes > self.diskFreeBytes) ? (self.diskTotalBytes - self.diskFreeBytes) : 0;
    self.appDataBytes = (used > self.clutterBytes) ? (used - self.clutterBytes) : 0;

    NSArray<NSString *> *simThumbs =
    [self as_thumbsFromNewestGroup:sim type:ASGroupTypeSimilarImage maxCount:2 isValid:isValidId];

    NSArray<NSString *> *dupThumbs =
    [self as_thumbsFromNewestGroup:dup type:ASGroupTypeDuplicateImage maxCount:2 isValid:isValidId];

    NSMutableArray<NSString *> *shotIds = [NSMutableArray arrayWithCapacity:shots.count];
    for (ASAssetModel *m in shots)  if (isValidId(m.localId)) [shotIds addObject:m.localId];
    NSArray<NSString *> *shotThumb = [self as_pickNewestLocalIds:shotIds limit:1];

    NSMutableArray<NSString *> *blurIds = [NSMutableArray arrayWithCapacity:blurs.count];
    for (ASAssetModel *m in blurs)  if (isValidId(m.localId)) [blurIds addObject:m.localId];
    NSArray<NSString *> *blurThumb = [self as_pickNewestLocalIds:blurIds limit:1];

    NSMutableArray<NSString *> *otherIds = [NSMutableArray arrayWithCapacity:others.count];
    for (ASAssetModel *m in others) if (isValidId(m.localId)) [otherIds addObject:m.localId];
    NSArray<NSString *> *otherThumb = [self as_pickNewestLocalIds:otherIds limit:1];

    NSMutableArray<NSString *> *videoIds = [NSMutableArray array];
    for (ASAssetModel *m in bigs)   if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in recs)   if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in simVid) if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in dupVid) if (isValidId(m.localId)) [videoIds addObject:m.localId];

    NSString *videoCoverId = [self as_pickNewestLocalIds:videoIds limit:1].firstObject;
    NSArray<NSString *> *videoThumb = videoCoverId.length ? @[videoCoverId] : @[];

    ASHomeModuleVM *(^makeVM)(ASHomeCardType, NSString *, NSString *, uint64_t, NSUInteger, NSArray<NSString *> *, BOOL, BOOL) =
    ^ASHomeModuleVM *(ASHomeCardType type,
                      NSString *title,
                      NSString *countText,
                      uint64_t totalBytes,
                      NSUInteger totalCount,
                      NSArray<NSString *> *thumbIds,
                      BOOL showsTwo,
                      BOOL isVideoCover) {

        ASHomeModuleVM *vm = [ASHomeModuleVM new];
        vm.type = type;
        vm.title = title ?: @"";
        vm.countText = countText ?: @"";
        vm.totalBytes = totalBytes;
        vm.totalCount = totalCount;

        vm.thumbLocalIds = thumbIds ?: @[];
        vm.thumbKey = [vm.thumbLocalIds componentsJoinedByString:@"|"];

        vm.showsTwoThumbs = showsTwo;
        vm.isVideoCover = isVideoCover;

        vm.didSetThumb = (vm.thumbLocalIds.count > 0);

        return vm;
    };

    uint64_t simBytes = 0; for (ASAssetModel *m in simImg) simBytes += m.fileSizeBytes;
    NSString *simCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil), (unsigned long)simImg.count];
    ASHomeModuleVM *vmSimilar =
    makeVM(ASHomeCardTypeSimilarPhotos, NSLocalizedString(@"Similar Photos", nil), simCountText, simBytes, simImg.count, simThumbs, YES, NO);

    uint64_t dupBytes = 0; for (ASAssetModel *m in dupImg) dupBytes += m.fileSizeBytes;
    NSString *dupCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil), (unsigned long)dupImg.count];
    ASHomeModuleVM *vmDup =
    makeVM(ASHomeCardTypeDuplicatePhotos, NSLocalizedString(@"Duplicate Photos", nil), dupCountText, dupBytes, dupImg.count, dupThumbs, NO, NO);

    uint64_t shotsBytes = 0; for (ASAssetModel *m in shots) shotsBytes += m.fileSizeBytes;
    NSString *shotsCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil), (unsigned long)shots.count];
    ASHomeModuleVM *vmShots =
    makeVM(ASHomeCardTypeScreenshots, NSLocalizedString(@"Screenshots", nil), shotsCountText, shotsBytes, shots.count, shotThumb, NO, NO);

    uint64_t blurBytes = 0; for (ASAssetModel *m in blurs) blurBytes += m.fileSizeBytes;
    NSString *blurCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil), (unsigned long)blurs.count];
    ASHomeModuleVM *vmBlur =
    makeVM(ASHomeCardTypeBlurryPhotos, NSLocalizedString(@"Blurry Photos", nil), blurCountText, blurBytes, blurs.count, blurThumb, NO, NO);

    uint64_t otherBytes = 0; for (ASAssetModel *m in others) otherBytes += m.fileSizeBytes;
    NSString *otherCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Photos", nil), (unsigned long)others.count];
    ASHomeModuleVM *vmOther =
    makeVM(ASHomeCardTypeOtherPhotos, NSLocalizedString(@"Other photos", nil), otherCountText, otherBytes, others.count, otherThumb, NO, NO);

    NSUInteger vCount = simVid.count + dupVid.count + bigs.count + recs.count;
    uint64_t vBytes = 0;
    for (ASAssetModel *m in simVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in dupVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in bigs)   vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in recs)   vBytes += m.fileSizeBytes;

    NSString *vCountText = [NSString stringWithFormat:NSLocalizedString(@"%lu Videos", nil), (unsigned long)vCount];
    ASHomeModuleVM *vmVideos =
    makeVM(ASHomeCardTypeVideos, NSLocalizedString(@"Videos", nil), vCountText, vBytes, vCount, videoThumb, NO, YES);

    return @[ vmSimilar, vmVideos, vmDup, vmShots, vmBlur, vmOther ];
}

- (NSString *)renderKeyForVM:(ASHomeModuleVM *)vm indexPath:(NSIndexPath *)ip {
    return [self coverKeyForVM:vm];
}

- (void)cancelCellRequests:(HomeModuleCell *)cell {
    if (cell.reqId1 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId1];
        cell.reqId1 = PHInvalidImageRequestID;
    }
    if (cell.reqId2 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId2];
        cell.reqId2 = PHInvalidImageRequestID;
    }
    if (cell.videoReqId != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.videoReqId];
        cell.videoReqId = PHInvalidImageRequestID;
    }
}

#pragma mark - Collection DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (![self hasPhotoAccess]) return 1;
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                          cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    if (![self hasPhotoAccess]) {
        ASNoAuthCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASNoAuthCell"
                                                                       forIndexPath:indexPath];
        __weak typeof(self) weakSelf = self;
        cell.onTap = ^{
            [weakSelf onTapPermissionGate]; // NotDetermined 会触发系统授权；Denied/Restricted 会去设置
        };
        return cell;
    }

    HomeModuleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeModuleCell"
                                                                     forIndexPath:indexPath];
    ASHomeModuleVM *vm = self.modules[indexPath.item];

    [cell applyVM:vm humanSizeFn:^NSString * _Nonnull(uint64_t bytes) {
        return [HomeModuleCell humanSize:bytes];
    }];

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) {
        [self cancelCellRequests:cell];
        [cell stopVideoIfNeeded];

        cell.appliedCoverKey = nil;
        cell.thumbKey = nil;
        cell.representedLocalIds = @[];

        cell.hasFinalThumb1 = NO;
        cell.hasFinalThumb2 = NO;

        cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
        cell.img2.image = (vm.showsTwoThumbs ? [UIImage imageNamed:@"ic_placeholder"] : nil);
        cell.playIconView.hidden = YES;
        return cell;
    }

    if (!vm.isVideoCover) {
        if (cell.videoReqId != PHInvalidImageRequestID) {
            [self.imgMgr cancelImageRequest:cell.videoReqId];
            cell.videoReqId = PHInvalidImageRequestID;
        }
        [cell stopVideoIfNeeded];
    }

//    [self requestCoverIfNeededForCell:cell vm:vm indexPath:indexPath];

    return cell;
}

#pragma mark - Header

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {

    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) {
        return [UICollectionReusableView new];
    }

    ASHomeHeaderView *v = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                             withReuseIdentifier:@"ASHomeHeaderView"
                                                                    forIndexPath:indexPath];

    [v applyTotal:self.diskTotalBytes
          clutter:self.clutterBytes
          appData:self.appDataBytes
             free:self.diskFreeBytes
      humanSizeFn:^NSString * _Nonnull(uint64_t bytes) {
        return [HomeModuleCell humanSize:bytes];
    }];
    
    v.showsLimitedBanner = self.isLimitedAuth;

    __weak typeof(self) weakSelf = self;
    v.onTapLimitedBanner = ^{
        [weakSelf openSettings];
    };

    return v;
}

#pragma mark - Layout

- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
shouldFullSpanAtIndexPath:(NSIndexPath *)indexPath {

    if (![self hasPhotoAccess]) return YES;
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    return (vm.type == ASHomeCardTypeSimilarPhotos);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![self hasPhotoAccess]) {
        return SW(420.0);
    }

    ASHomeModuleVM *vm = self.modules[indexPath.item];
    if (vm.type == ASHomeCardTypeSimilarPhotos) return kLargeCellH;

    NSInteger smallIdx = (NSInteger)indexPath.item - 1;
    if (smallIdx < 0) smallIdx = 0;
    return (smallIdx % 3 == 0) ? SW(306.0) : SW(246.0);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {

    CGFloat w = collectionView.bounds.size.width;

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = collectionView.safeAreaInsets.top;

    CGFloat top = safeTop + SW(12);
    CGFloat proH = SW(28);

    CGFloat spaceTitleH = SW(16);
    CGFloat spaceValueH = SW(40);
    CGFloat spaceTitleGap = SW(2);

    CGFloat barTopGap = SW(10);
    CGFloat barH = SW(12);
    CGFloat legendH = SW(24);
    CGFloat legendTopGap = SW(12);
    CGFloat bottomPad = SW(30);

    CGFloat contentH =
    top + SW(8)
    + MAX(proH, (spaceTitleH + spaceTitleGap + spaceValueH))
    + barTopGap + barH
    + legendTopGap + legendH
    + bottomPad;

    CGFloat bannerExtra = 0;
    if (self.isLimitedAuth) {
        bannerExtra = SW(18.0) + SW(150.0);
    }

    return CGSizeMake(w, contentH + bannerExtra);
}

#pragma mark - Tap

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (![self hasPhotoAccess]) {
        [self onTapPermissionGate];
        return;
    }
 
    if (indexPath.item >= self.modules.count) return;
    ASHomeModuleVM *vm = self.modules[indexPath.item];

    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;

    switch (vm.type) {
        case ASHomeCardTypeSimilarPhotos: {
            ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:ASAssetListModeSimilarImage];
            [nav pushViewController:vc animated:YES];
        } break;

        case ASHomeCardTypeDuplicatePhotos: {
            ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:ASAssetListModeDuplicateImage];
            [nav pushViewController:vc animated:YES];
        } break;

        case ASHomeCardTypeScreenshots: {
            ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:ASAssetListModeScreenshots];
            [nav pushViewController:vc animated:YES];
        } break;

        case ASHomeCardTypeBlurryPhotos: {
            ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:ASAssetListModeBlurryPhotos];
            [nav pushViewController:vc animated:YES];
        } break;

        case ASHomeCardTypeOtherPhotos: {
            ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:ASAssetListModeOtherPhotos];
            [nav pushViewController:vc animated:YES];
        } break;

        case ASHomeCardTypeVideos: {
            VideoSubPageViewController *vc = [[VideoSubPageViewController alloc] init];
            [nav pushViewController:vc animated:YES];
        } break;
    }
}

- (void)collectionView:(UICollectionView *)collectionView
      willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![cell isKindOfClass:HomeModuleCell.class]) return;
    if (![self hasPhotoAccess]) return;
    if (indexPath.item >= self.modules.count) return;

    HomeModuleCell *c = (HomeModuleCell *)cell;
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    if (vm.thumbLocalIds.count == 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        HomeModuleCell *now = (HomeModuleCell *)[collectionView cellForItemAtIndexPath:indexPath];
        if (now != c) return;
        [self requestCoverIfNeededForCell:now vm:vm indexPath:indexPath];
    });
}

- (void)collectionView:(UICollectionView *)collectionView
didEndDisplayingCell:(UICollectionViewCell *)cell
   forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![cell isKindOfClass:HomeModuleCell.class]) return;
    HomeModuleCell *c = (HomeModuleCell *)cell;

    [self cancelCellRequests:c];
    [c stopVideoIfNeeded];
}

- (NSArray<PHAsset *> *)assetsForLocalIdsCached:(NSArray<NSString *> *)ids {
    if (ids.count == 0) return @[];

    NSMutableArray<NSString *> *miss = [NSMutableArray array];
    for (NSString *lid in ids) {
        if (lid.length == 0) continue;
        if (![self.assetCache objectForKey:lid]) {
            [miss addObject:lid];
        }
    }

    if (miss.count) {
        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:miss options:nil];
        [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *lid = obj.localIdentifier;
            if (lid.length) {
                [self.assetCache setObject:obj forKey:lid];
            }
        }];
    }

    NSMutableArray<PHAsset *> *out = [NSMutableArray arrayWithCapacity:ids.count];
    for (NSString *lid in ids) {
        PHAsset *a = (lid.length ? [self.assetCache objectForKey:lid] : nil);
        if (a) [out addObject:a];
    }
    return out;
}

#pragma mark - Thumbnails (Images)

- (void)loadThumbsForVM:(ASHomeModuleVM *)vm
               intoCell:(HomeModuleCell *)cell
            atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    // 这些都在主线程读取一次，后面异步对齐校验用
    NSString *expectedKey = cell.appliedCoverKey ?: @"";
    NSInteger token = cell.renderToken;
    BOOL needsTwo = vm.showsTwoThumbs;

    // 先取消旧请求（主线程安全地改 cell 状态）
    [self cancelCellRequests:cell];
    [cell stopVideoIfNeeded];

    // 计算 targetSize（主线程，避免并发读 cell bounds/frame）
    CGFloat scale = UIScreen.mainScreen.scale;

    CGSize s1 = cell.img1.bounds.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = cell.img1.frame.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = CGSizeMake(SW(120), SW(120));
    CGSize t1 = CGSizeMake(MAX(1, s1.width * scale), MAX(1, s1.height * scale));

    CGSize s2 = cell.img2.bounds.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = cell.img2.frame.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = CGSizeMake(SW(120), SW(120));
    CGSize t2 = CGSizeMake(MAX(1, s2.width * scale), MAX(1, s2.height * scale));

    // options（可复用你原来的配置）
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *idsCopy = [ids copy]; // 防止外面改动

    // 1) 后台取 PHAsset（缓存 + 批量 fetch）
    dispatch_async(self.photoFetchQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSArray<PHAsset *> *assets = [self assetsForLocalIdsCached:idsCopy];
        if (assets.count == 0) return;

        PHAsset *a0 = assets.count > 0 ? assets[0] : nil;
        PHAsset *a1 = assets.count > 1 ? assets[1] : nil;

        // 2) 回主线程做 requestImage + UI set（避免跨线程写 cell/collectionView）
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) return;

            HomeModuleCell *nowCell = (HomeModuleCell *)[self2.cv cellForItemAtIndexPath:indexPath];
            if (![nowCell isKindOfClass:HomeModuleCell.class]) return;

            // 复用/滚动校验：token + key + ids 必须一致
            if (nowCell.renderToken != token) return;
            NSString *k = (nowCell.appliedCoverKey != nil) ? nowCell.appliedCoverKey : @"";
            if (![k isEqualToString:(expectedKey != nil ? expectedKey : @"")]) return;

            if (![nowCell.representedLocalIds isEqualToArray:idsCopy]) return;

            // 如果只需要一张图，确保第二张清空
            if (!needsTwo) {
                nowCell.img2.image = nil;
                nowCell.hasFinalThumb2 = YES;
            }

            // 通用 setImg：degraded 先上屏但不置 final
            void (^setImg)(NSInteger idx, UIImage *img, NSDictionary *info) = ^(NSInteger idx, UIImage *img, NSDictionary *info) {
                BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];

                dispatch_async(dispatch_get_main_queue(), ^{
                    HomeModuleCell *againCell = (HomeModuleCell *)[self2.cv cellForItemAtIndexPath:indexPath];
                    if (![againCell isKindOfClass:HomeModuleCell.class]) return;

                    if (againCell.renderToken != token) return;
                    NSString *k = (againCell.appliedCoverKey != nil) ? againCell.appliedCoverKey : @"";
                    if (![k isEqualToString:(expectedKey != nil ? expectedKey : @"")]) return;

                    if (![againCell.representedLocalIds isEqualToArray:idsCopy]) return;

                    if (idx == 0) {
                        if (!degraded || !againCell.hasFinalThumb1) {
                            againCell.img1.image = img;
                            if (!degraded) againCell.hasFinalThumb1 = YES;
                        }
                    } else {
                        if (!degraded || !againCell.hasFinalThumb2) {
                            againCell.img2.image = img;
                            if (!degraded) againCell.hasFinalThumb2 = YES;
                        }
                    }
                });
            };

            // 发起 requestImage（主线程写 reqId）
            if (a0) {
                nowCell.reqId1 = [self2.imgMgr requestImageForAsset:a0
                                                         targetSize:t1
                                                        contentMode:PHImageContentModeAspectFill
                                                            options:opt
                                                      resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
                    if (!result) return;
                    if ([info[PHImageCancelledKey] boolValue]) return;
                    setImg(0, result, info ?: @{});
                }];
            }

            if (needsTwo && a1) {
                nowCell.reqId2 = [self2.imgMgr requestImageForAsset:a1
                                                         targetSize:t2
                                                        contentMode:PHImageContentModeAspectFill
                                                            options:opt
                                                      resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
                    if (!result) return;
                    if ([info[PHImageCancelledKey] boolValue]) return;
                    setImg(1, result, info ?: @{});
                }];
            } else {
                // 第二张不存在/不需要：避免残留
                nowCell.img2.image = needsTwo ? nowCell.img2.image : nil;
            }
        });
    });
}


#pragma mark - Video Preview

- (void)loadVideoPreviewForVM:(ASHomeModuleVM *)vm
                     intoCell:(HomeModuleCell *)cell
                  atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    NSString *expectedKey = cell.appliedCoverKey ?: @"";
    NSInteger token = cell.renderToken;

    [cell stopVideoIfNeeded];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    PHAsset *asset = fr.firstObject;
    if (asset.mediaType != PHAssetMediaTypeVideo) {
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
        return;
    }

    PHVideoRequestOptions *vopt = [PHVideoRequestOptions new];
    vopt.networkAccessAllowed = YES;
    vopt.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;

    __weak typeof(self) weakSelf = self;

    cell.videoReqId = [self.imgMgr requestAVAssetForVideo:asset
                                                 options:vopt
                                           resultHandler:^(AVAsset * _Nullable avAsset,
                                                           AVAudioMix * _Nullable audioMix,
                                                           NSDictionary * _Nullable info) {

        if (!avAsset) return;
        if ([info[PHImageCancelledKey] boolValue]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            HomeModuleCell *nowCell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            if (nowCell.renderToken != token) return;
            NSString *k1 = nowCell.appliedCoverKey ? nowCell.appliedCoverKey : @"";
            NSString *k2 = expectedKey ? expectedKey : @"";
            if (![k1 isEqualToString:k2]) return;
            if (![nowCell.representedLocalIds isEqualToArray:ids]) return;

            if (!nowCell.isVideoCover) return;

            PHImageRequestOptions *iopt = [PHImageRequestOptions new];
            iopt.networkAccessAllowed = YES;
            iopt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
            iopt.resizeMode = PHImageRequestOptionsResizeModeFast;
            iopt.synchronous = NO;

            CGSize posterSize = CGSizeMake(MAX(1, nowCell.img1.bounds.size.width) * UIScreen.mainScreen.scale,
                                           MAX(1, nowCell.img1.bounds.size.height) * UIScreen.mainScreen.scale);

            nowCell.reqId1 = [self.imgMgr requestImageForAsset:asset
                                                    targetSize:posterSize
                                                   contentMode:PHImageContentModeAspectFill
                                                       options:iopt
                                                 resultHandler:^(UIImage * _Nullable result,
                                                                 NSDictionary * _Nullable info2) {

                if (!result) return;
                BOOL cancelled = [info2[PHImageCancelledKey] boolValue];
                if (cancelled) return;

                BOOL degraded = [info2[PHImageResultIsDegradedKey] boolValue];

                dispatch_async(dispatch_get_main_queue(), ^{
                    HomeModuleCell *againCell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:indexPath];
                    if (!againCell) return;

                    if (againCell.renderToken != token) return;
                    NSString *k1 = againCell.appliedCoverKey ? againCell.appliedCoverKey : @"";
                    NSString *k2 = expectedKey ? expectedKey : @"";
                    if (![k1 isEqualToString:k2]) return;
                    if (![againCell.representedLocalIds isEqualToArray:ids]) return;
                    if (!againCell.isVideoCover) return;

                    if (!degraded || !againCell.hasFinalThumb1) {
                        againCell.img1.image = result;
                        if (!degraded) againCell.hasFinalThumb1 = YES;
                    }
                });
            }];

            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:avAsset];
            AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[item]];
            player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            player.muted = YES;

            AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
            layer.frame = nowCell.img1.bounds;
            layer.videoGravity = AVLayerVideoGravityResizeAspectFill;

            if (nowCell.playerLayer) {
                [nowCell.playerLayer removeFromSuperlayer];
            }
            [nowCell.img1.layer addSublayer:layer];

            if (@available(iOS 10.0, *)) {
                nowCell.looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
            }

            nowCell.player = player;
            nowCell.playerLayer = layer;

            [player play];
        });
    }];
}


- (void)pauseVisibleVideoCovers {
    if (!self.isViewLoaded) return;

    for (NSIndexPath *ip in self.cv.indexPathsForVisibleItems) {
        if (ip.item >= self.modules.count) continue;

        ASHomeModuleVM *vm = self.modules[ip.item];
        if (!vm.isVideoCover) continue;

        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (![cell isKindOfClass:HomeModuleCell.class]) continue;

        if (cell.player) [cell.player pause];
    }
}

- (void)resumeVisibleVideoCovers {
    if (!self.isViewLoaded || self.view.window == nil) return;
    if (![self hasPhotoAccess]) return;

    for (NSIndexPath *ip in self.cv.indexPathsForVisibleItems) {
        if (ip.item >= self.modules.count) continue;

        ASHomeModuleVM *vm = self.modules[ip.item];
        if (!vm.isVideoCover) continue;
        if (vm.thumbLocalIds.count == 0) continue;

        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (![cell isKindOfClass:HomeModuleCell.class]) continue;

        if (cell.player && cell.playerLayer) {
            [cell.player play];
            continue;
        }

        [self requestCoverIfNeededForCell:cell vm:vm indexPath:ip];
    }
}

@end

NS_ASSUME_NONNULL_END
