#import "HomeViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import "ASPhotoScanManager.h"
#import "ASAssetListViewController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UI Constants
typedef NS_ENUM(NSInteger, ASPhotoAuthLevel) {
    ASPhotoAuthLevelUnknown = -1,
    ASPhotoAuthLevelNone    = 0,   // Denied / Restricted / NotDetermined(未授权态)
    ASPhotoAuthLevelLimited = 1,
    ASPhotoAuthLevelFull    = 2
};

static NSString * const kASLastPhotoAuthLevelKey = @"as_last_photo_auth_level_v1";

static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static const CGFloat kHomeSideInset = 16.0;
static const CGFloat kHomeGridGap   = 12.0;

static const CGFloat kHeaderHeight  = 200.0;
static const CGFloat kLargeCellH    = 260.0;

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

#pragma mark - Home Module Model

@interface ASHomeModuleVM : NSObject
@property (nonatomic) BOOL didSetThumb; // ✅ 扫描中封面只设置一次，避免频繁换封面导致重复请求
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

    CGFloat radius = 6.0;
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

@implementation ASHomeHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;

        _spaceTitleLabel = [UILabel new];
        _spaceTitleLabel.text = @"Space To Clean";
        _spaceTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        _spaceTitleLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceTitleLabel];

        _spaceLabel = [UILabel new];
        _spaceLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightMedium];
        _spaceLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceLabel];

        _proBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _proBtn.layer.cornerRadius = 18;
        _proBtn.clipsToBounds = YES;
        _proBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        [_proBtn setTitle:@"Pro" forState:UIControlStateNormal];
        [_proBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

        UIImage *vip = [[UIImage imageNamed:@"ic_vip"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (vip) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
            [vip drawInRect:CGRectMake(0, 0, 24, 24)];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_proBtn setImage:scaled forState:UIControlStateNormal];
            _proBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            _proBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
            _proBtn.imageEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 8);
            _proBtn.titleEdgeInsets = UIEdgeInsetsZero;
        } else {
            _proBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
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
        _proGradient.cornerRadius = 18;
        [_proBtn.layer insertSublayer:_proGradient atIndex:0];

        _bar = [[ASSegmentedBarView alloc] initWithFrame:CGRectZero];
        [self addSubview:_bar];

        _legend1Dot = [UIView new];
        _legend1Dot.backgroundColor = kClutterRed();
        _legend1Dot.layer.cornerRadius = 3;
        [self addSubview:_legend1Dot];

        _legend1Name = [UILabel new];
        _legend1Name.text = @"Clutter";
        _legend1Name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend1Name.textColor = kTextGray();
        [self addSubview:_legend1Name];

        _legend1Value = [UILabel new];
        _legend1Value.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend1Value.textColor = UIColor.blackColor;
        [self addSubview:_legend1Value];

        _legend2Dot = [UIView new];
        _legend2Dot.backgroundColor = kAppDataYellow();
        _legend2Dot.layer.cornerRadius = 3;
        [self addSubview:_legend2Dot];

        _legend2Name = [UILabel new];
        _legend2Name.text = @"App&Data";
        _legend2Name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend2Name.textColor = kTextGray();
        [self addSubview:_legend2Name];

        _legend2Value = [UILabel new];
        _legend2Value.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend2Value.textColor = UIColor.blackColor;
        [self addSubview:_legend2Value];

        _legend3Dot = [UIView new];
        _legend3Dot.backgroundColor = kTotalGray();
        _legend3Dot.layer.cornerRadius = 3;
        [self addSubview:_legend3Dot];

        _legend3Name = [UILabel new];
        _legend3Name.text = @"Total";
        _legend3Name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend3Name.textColor = kTextGray();
        [self addSubview:_legend3Name];

        _legend3Value = [UILabel new];
        _legend3Value.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _legend3Value.textColor = UIColor.blackColor;
        [self addSubview:_legend3Value];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat left = 30.0;

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.window.safeAreaInsets.top;

    CGFloat top = safeTop;

    CGFloat proH = 36.0;
    [_proBtn sizeToFit];
    CGFloat proW = MAX(78.0, _proBtn.bounds.size.width + 10.0);
    _proBtn.frame = CGRectMake(w - left - proW, top, proW, proH);
    _proBtn.layer.cornerRadius = 18.0;
    _proGradient.frame = _proBtn.bounds;
    _proGradient.cornerRadius = 18.0;

    CGFloat titleH = 20.0;
    CGFloat bigH   = 40.0;

    CGFloat textMaxW = CGRectGetMinX(_proBtn.frame) - left - 10.0;
    _spaceTitleLabel.frame = CGRectMake(left, top, MAX(0, textMaxW), titleH);

    _spaceLabel.frame = CGRectMake(left,
                                   CGRectGetMaxY(_spaceTitleLabel.frame) + 5.0,
                                   MAX(0, textMaxW),
                                   bigH);

    _bar.frame = CGRectMake(left,
                            CGRectGetMaxY(_spaceLabel.frame) + 10.0,
                            w - left * 2.0,
                            12.0);

    CGFloat legendsTop = CGRectGetMaxY(_bar.frame) + 15.0;

    CGFloat dotD = 8.0;
    CGFloat dotToText = 6.0;

    CGFloat nameH = 14.0;
    CGFloat valueH = 14.0;
    CGFloat nameToValue = 2.0;

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
        _interItemSpacing = 12;
        _lineSpacing = 12;
        _sectionInset = UIEdgeInsetsMake(0, 16, 16, 16);
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
    return YES;
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
        _shadowContainer.layer.shadowOffset = CGSizeMake(0, 2);
        _shadowContainer.layer.shadowRadius = 8;
        [self.contentView addSubview:_shadowContainer];

        _cardView = [UIView new];
        _cardView.backgroundColor = UIColor.whiteColor;
        _cardView.layer.cornerRadius = 14;
        _cardView.clipsToBounds = YES;
        [_shadowContainer addSubview:_cardView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        _titleLabel.textColor = UIColor.blackColor;

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _countLabel.textColor = kTextGray();

        _img1 = [UIImageView new];
        _img2 = [UIImageView new];
        _img1.backgroundColor = ASRGB(240, 242, 247);
        _img2.backgroundColor = ASRGB(240, 242, 247);
        _img1.contentMode = UIViewContentModeScaleAspectFill;
        _img2.contentMode = UIViewContentModeScaleAspectFill;
        _img1.clipsToBounds = YES;
        _img2.clipsToBounds = YES;
        _img1.layer.cornerRadius = 12;
        _img2.layer.cornerRadius = 12;

        _badgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _badgeBtn.titleLabel.numberOfLines = 1;
        _badgeBtn.titleLabel.lineBreakMode = NSLineBreakByClipping;
        _badgeBtn.titleLabel.adjustsFontSizeToFitWidth = NO;

        _badgeBtn.backgroundColor = kBadgeBlue();
        _badgeBtn.layer.cornerRadius = 25;
        _badgeBtn.clipsToBounds = YES;

        _badgeBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        [_badgeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [_badgeBtn setTitle:@"--" forState:UIControlStateNormal];

        _badgeBtn.contentEdgeInsets = UIEdgeInsetsMake(11, 15, 11, 18);
        _badgeBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _badgeBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

        _badgeBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        _badgeBtn.userInteractionEnabled = NO;

        UIImage *todo = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (todo) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(9, 16), NO, 0);
            [todo drawInRect:CGRectMake(0, 0, 9, 16)];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_badgeBtn setImage:scaled forState:UIControlStateNormal];
            _badgeBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            CGFloat spacing = 9.0;
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

    CGFloat pad = 15.0;

    self.titleLabel.frame = CGRectMake(pad, pad, w - pad * 2.0, 20);

    self.countLabel.frame = CGRectMake(pad,
                                       CGRectGetMaxY(self.titleLabel.frame) + 4,
                                       w - pad * 2.0,
                                       16);

    CGFloat imgTop = CGRectGetMaxY(self.countLabel.frame) + 12;
    CGFloat imgBottomPad = pad;
    CGFloat imgH = MAX(0, h - imgTop - imgBottomPad);

    if (self.showsTwoThumbs) {
        CGFloat gap = 10.0;
        CGFloat imgW = (w - pad * 2.0 - gap) / 2.0;

        self.img1.hidden = NO;
        self.img2.hidden = NO;

        self.img1.layer.cornerRadius = 12;
        self.img2.layer.cornerRadius = 12;

        self.img1.frame = CGRectMake(pad, imgTop, imgW, imgH);
        self.img2.frame = CGRectMake(CGRectGetMaxX(self.img1.frame) + gap, imgTop, imgW, imgH);
    } else {
        self.img1.hidden = NO;
        self.img2.hidden = YES;

        if (!self.isLargeCard) {
            self.img1.layer.cornerRadius = 0;
            self.img1.frame = CGRectMake(0, imgTop, w, h - imgTop);
        } else {
            self.img1.layer.cornerRadius = 12;
            self.img1.frame = CGRectMake(pad, imgTop, w - pad * 2.0, imgH);
        }

        self.img2.frame = CGRectZero;
    }

    NSString *t = self.badgeBtn.currentTitle ?: @"";
    UIFont *f = self.badgeBtn.titleLabel.font ?: [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    CGSize textSize = [t sizeWithAttributes:@{NSFontAttributeName: f}];

    UIImage *img = [self.badgeBtn imageForState:UIControlStateNormal];
    CGSize imgSize = img ? img.size : CGSizeZero;

    CGFloat spacing = img ? 9.0 : 0.0;
    UIEdgeInsets in = self.badgeBtn.contentEdgeInsets;

    CGFloat badgeW = ceil(in.left + textSize.width + spacing + imgSize.width + in.right);
    CGFloat badgeH = ceil(in.top + MAX(textSize.height, imgSize.height) + in.bottom);

    if (self.isLargeCard) {
        CGFloat x = w - pad - badgeW;
        self.badgeBtn.frame = CGRectMake(x, pad - 3.0, badgeW, badgeH);
    } else {
        CGFloat rightInset = 10.0;
        CGFloat by = CGRectGetMaxY(self.img1.frame) - badgeH - rightInset;
        CGFloat bx = CGRectGetMaxX(self.img1.frame) - rightInset - badgeW;
        self.badgeBtn.frame = CGRectMake(bx, by, badgeW, badgeH);
    }

    [self.shadowContainer bringSubviewToFront:self.badgeBtn];
    [self.cardView bringSubviewToFront:self.playIconView];

    self.playIconView.hidden = !self.isVideoCover;
    self.playIconView.frame = CGRectMake(CGRectGetMinX(self.img1.frame) + 10,
                                         CGRectGetMinY(self.img1.frame) + 10,
                                         18, 18);

    if (self.playerLayer) {
        self.playerLayer.frame = self.img1.bounds;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.renderToken += 1;
    self.videoReqId = PHInvalidImageRequestID;
    [self stopVideoIfNeeded];

    self.representedLocalIds = @[];
    self.thumbKey = nil;

    self.appliedCoverKey = nil;      // ✅ 关键：复用时清掉 cover key

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

@property (nonatomic, strong) UIView *permissionGateView;   // 占位：无权限按钮
@property (nonatomic, strong) UILabel *permissionGateLabel;
@property (nonatomic, strong) UIButton *permissionGateButton;

@property (nonatomic, strong) UIImageView *topBgView;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<ASHomeModuleVM *> *modules;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

// Header space
@property (nonatomic) uint64_t diskTotalBytes;
@property (nonatomic) uint64_t diskFreeBytes;
@property (nonatomic) uint64_t clutterBytes;
@property (nonatomic) uint64_t appDataBytes;
@property (nonatomic) CFTimeInterval lastBootstrapAt;

// 合并扫描进度高频 UI 刷新
@property (nonatomic, strong) NSTimer *scanUITimer;
@property (nonatomic) BOOL pendingScanUIUpdate;
@property (nonatomic) CFTimeInterval lastScanUIFire;

// 去重集合（如果你别处要用）
@property (nonatomic, strong) NSSet<NSString *> *allCleanableIds;
@property (nonatomic) uint64_t allCleanableBytes;
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

- (void)showPermissionGate:(BOOL)show {
    self.permissionGateView.hidden = !show;
    [self.view bringSubviewToFront:self.permissionGateView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.scanUITimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didInitialBuild) return;
    self.didInitialBuild = YES;

    self.lastBootstrapAt = CFAbsoluteTimeGetCurrent();
    [self bootstrapScanFlow];
}

- (void)appDidBecomeActive {
    if (!self.didInitialBuild) return;
    if (!self.isViewLoaded || self.view.window == nil) return;

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastBootstrapAt < 0.8) return;  // ✅ 防抖：0.8s 内不重复跑
    self.lastBootstrapAt = now;

    [self bootstrapScanFlow];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];

    self.imgMgr = [[PHCachingImageManager alloc] init];   // ✅ 必须
    self.scanMgr = [ASPhotoScanManager shared];

    __weak typeof(self) weakSelf = self;
    [self.scanMgr subscribeProgress:^(ASScanSnapshot *snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf) return;
            if (snapshot.state == ASScanStateScanning) {
                [weakSelf scheduleScanUIUpdateCoalesced];
            } else {
                [weakSelf.scanUITimer invalidate];
                weakSelf.scanUITimer = nil;
                weakSelf.pendingScanUIUpdate = NO;
                [weakSelf rebuildModulesAndReload];
            }
        });
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    // ✅ 首屏先渲染一波（即使没权限也能显示缓存摘要 + 占位）
    [self rebuildModulesAndReload];

    // ✅ gate 按钮补上点击（见下面第3点）
    [self.permissionGateButton addTarget:self
                                  action:@selector(onTapPermissionGate)
                        forControlEvents:UIControlEventTouchUpInside];
}

- (void)onTapPermissionGate {
    PHAuthorizationStatus st = [self currentPHAuthStatus];

    // 1) 未决定：直接弹系统授权
    if (st == PHAuthorizationStatusNotDetermined) {
        [self bootstrapScanFlow];  // 你 bootstrapScanFlow 里已经写了 requestAuthorization
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

    PHAuthorizationStatus st = [self currentPHAuthStatus];
    ASPhotoAuthLevel curLevel = [self mapToAuthLevel:st];
    ASPhotoAuthLevel lastLevel = [self storedAuthLevel];
    BOOL hasCache1 = [self.scanMgr isCacheValid];
    
    BOOL authChanged = (lastLevel != ASPhotoAuthLevelUnknown && lastLevel != curLevel);
    if (authChanged) {
        [self resetCoverStateForAuthChange];
    }

    NSLog(@"[BOOT] st=%ld cur=%ld last=%ld hasCache=%d snapshotState=%ld",
             (long)st, (long)curLevel, (long)lastLevel, hasCache1, (long)self.scanMgr.snapshot.state);
    
    // --- 没权限（Denied / Restricted） 或 未决定（NotDetermined） ---
    if (st == PHAuthorizationStatusNotDetermined) {
        // 规则：首次/未决定 -> 弹系统授权；授权为 full/limit -> 全量扫描并缓存
        [self showPermissionGate:NO]; // 系统弹窗出来就不需要 gate（你也可以 YES）
        __weak typeof(self) weakSelf = self;

        if (@available(iOS 14.0, *)) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ASPhotoAuthLevel newLevel = [weakSelf mapToAuthLevel:status];
                    [weakSelf storeAuthLevel:newLevel];

                    if (newLevel == ASPhotoAuthLevelLimited || newLevel == ASPhotoAuthLevelFull) {
                        // 规则：0->limit / 0->full 全量扫描（不管有没有缓存）
                        [weakSelf showPermissionGate:NO];
                        [weakSelf startFullScanForce:YES];
                    } else {
                        // 用户拒绝：展示占位按钮
                        [weakSelf showPermissionGate:YES];
                        [weakSelf rebuildModulesAndReload]; // 继续展示缓存摘要
                    }
                });
            }];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ASPhotoAuthLevel newLevel = [weakSelf mapToAuthLevel:status];
                    [weakSelf storeAuthLevel:newLevel];

                    if (newLevel == ASPhotoAuthLevelLimited || newLevel == ASPhotoAuthLevelFull) {
                        [weakSelf showPermissionGate:NO];
                        [weakSelf startFullScanForce:YES];
                    } else {
                        [weakSelf showPermissionGate:YES];
                        [weakSelf rebuildModulesAndReload];
                    }
                });
            }];
#pragma clang diagnostic pop
        }
        return;
    }

    // Denied / Restricted
    if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
        [self storeAuthLevel:ASPhotoAuthLevelNone];
        // 规则：后续启动没权限 -> 请求权限或展示按钮（你说按钮不用实现，这里展示占位）
        [self showPermissionGate:YES];

        // 仍然展示缓存摘要，但不要触发增量/校验/封面
        [self rebuildModulesAndReload];
        return;
    }

    // --- 有权限（Limited / Full） ---
    [self showPermissionGate:NO];

    BOOL hasCache = [self.scanMgr isCacheValid];

    // 规则：权限变动 limit<->full 全量扫描；0->limit/full 全量扫描（不管缓存）
    BOOL forceFullByAuthChange = NO;
    if (lastLevel != ASPhotoAuthLevelUnknown && lastLevel != curLevel) {
        forceFullByAuthChange = YES;
    }

    // 更新记录（很关键：避免下次启动一直判定“权限变动”）
    [self storeAuthLevel:curLevel];

    if (forceFullByAuthChange) {
        [self startFullScanForce:YES];
        return;
    }

    if (!hasCache) {
        // 规则：有权限无缓存 -> 全量扫描并缓存
        [self startFullScanForce:NO];
        return;
    }

    // 规则：有权限有缓存 -> 先展示缓存（我们已经展示了）-> 再增量更新
    [self.scanMgr loadCacheAndCheckIncremental];
}

- (void)startFullScanForce:(BOOL)force {

    // 防重复：如果正在扫且你不想强制重来，就直接返回
    if (!force && self.scanMgr.snapshot.state == ASScanStateScanning) return;

    // 强制重扫：先 cancel
    if (force && self.scanMgr.snapshot.state == ASScanStateScanning) {
        [self.scanMgr cancel];
    }

    __weak typeof(self) weakSelf = self;
    [self.scanMgr startFullScanWithProgress:nil
                                 completion:^(__unused ASScanSnapshot *snapshot, __unused NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf rebuildModulesAndReload];
        });
    }];
}

#pragma mark - UI

- (void)setupUI {
    self.topBgView = [UIImageView new];
    self.topBgView.image = [UIImage imageNamed:@"ic_home_bg"];
    self.topBgView.contentMode = UIViewContentModeScaleAspectFill;
    self.topBgView.clipsToBounds = YES;
    self.topBgView.userInteractionEnabled = NO;
    [self.view addSubview:self.topBgView];

    ASWaterfallLayout *layout = [ASWaterfallLayout new];
    layout.delegate = (id)self;
    layout.numberOfColumns = 2;
    layout.interItemSpacing = kHomeGridGap;
    layout.lineSpacing = kHomeGridGap;
    layout.sectionInset = UIEdgeInsetsMake(0, kHomeSideInset, kHomeSideInset, kHomeSideInset);

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];

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
    // --- Permission Gate Placeholder (后期换成真正按钮) ---
    self.permissionGateView = [UIView new];
    self.permissionGateView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.04];
    self.permissionGateView.layer.cornerRadius = 12;
    self.permissionGateView.hidden = YES;
    [self.view addSubview:self.permissionGateView];

    self.permissionGateLabel = [UILabel new];
    self.permissionGateLabel.numberOfLines = 2;
    self.permissionGateLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.permissionGateLabel.textColor = [UIColor blackColor];
    self.permissionGateLabel.text = @"Need Photos Permission\nTap to grant access";
    [self.permissionGateView addSubview:self.permissionGateLabel];

    self.permissionGateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.permissionGateButton setTitle:@"Grant Permission" forState:UIControlStateNormal];
    // 这里先不实现点击逻辑，后期补
    [self.permissionGateView addSubview:self.permissionGateButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.cv.frame = self.view.bounds;

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat bgH = ASHomeBgHeightForWidth(w);
    self.topBgView.frame = CGRectMake(0, 0, w, bgH + safeTop);

    UIEdgeInsets safe = self.view.safeAreaInsets;
    self.cv.contentInset = UIEdgeInsetsMake(0, 0, safe.bottom + 70, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;

    ASWaterfallLayout *wf = (ASWaterfallLayout *)self.cv.collectionViewLayout;
    if ([wf isKindOfClass:ASWaterfallLayout.class]) {
        wf.headerHeight = [self collectionView:self.cv layout:wf referenceSizeForHeaderInSection:0].height;
        [wf invalidateLayout];
    }
    
    // Permission gate layout (占位)
    CGFloat gateW = self.view.bounds.size.width - 32;
    CGFloat gateH = 86;
    CGFloat gateX = 16;
    CGFloat gateY = self.view.safeAreaInsets.top + 12;
    self.permissionGateView.frame = CGRectMake(gateX, gateY, gateW, gateH);

    self.permissionGateLabel.frame = CGRectMake(12, 10, gateW - 24 - 140, gateH - 20);
    self.permissionGateButton.frame = CGRectMake(gateW - 12 - 130, (gateH - 36)/2.0, 130, 36);
}

#pragma mark - Data Build

- (void)rebuildModulesAndReload {
    [self computeDiskSpace];

    if (self.scanMgr.snapshot.state == ASScanStateScanning) {
        [self scheduleScanUIUpdateCoalesced];
        return;
    }

    NSArray<ASHomeModuleVM *> *old = self.modules ?: @[];
    NSArray<ASHomeModuleVM *> *newMods = [self buildModulesFromManagerAndComputeClutterIsFinal:YES];
    self.modules = newMods;

    // 第一次或数量变化：只能 reloadData
    if (old.count == 0 || old.count != newMods.count) {
        [self.cv reloadData];
        return;
    }

    // 找封面变化的 item，只 reload 那些
    NSMutableArray<NSIndexPath *> *reloadIPs = [NSMutableArray array];
    for (NSInteger i = 0; i < newMods.count; i++) {
        NSString *ok = [self coverKeyForVM:old[i]];
        NSString *nk = [self coverKeyForVM:newMods[i]];
        if (![ok isEqualToString:nk]) {
            [reloadIPs addObject:[NSIndexPath indexPathForItem:i inSection:0]];
        }
    }

    if (reloadIPs.count > 0) {
        [self.cv reloadItemsAtIndexPaths:reloadIPs];
    }

    // ✅ 无论封面变不变，都只更新 header + 可见 cell 文案，不 reloadData
    [self updateHeaderDuringScanning]; // 这函数其实也能用于非扫描期
    for (NSIndexPath *ip in [self.cv indexPathsForVisibleItems]) {
        if (ip.item >= self.modules.count) continue;
        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (!cell) continue;
        ASHomeModuleVM *vm = self.modules[ip.item];
        [cell applyVM:vm humanSizeFn:^NSString *(uint64_t bytes) {
            return [HomeModuleCell humanSize:bytes];
        }];
    }
}

- (NSString *)coverKeyForVM:(ASHomeModuleVM *)vm {
    // 只由“卡片类型 + 封面 ids”决定，顺序也要稳定（你 ids 本身就是你选出来的顺序）
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

        // 旧封面存在且有效：强制继承，保证“封面只在首次设置”
        if (o.thumbLocalIds.count > 0 && [self as_allLocalIdsValid:o.thumbLocalIds]) {
            n.thumbLocalIds = o.thumbLocalIds;
            n.thumbKey = o.thumbKey;
            n.didSetThumb = o.didSetThumb;
        } else {
            // 旧封面没了/失效：允许新模块的封面（当作首次可用时设置）
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

    // 让界面马上变成占位，避免继续显示旧封面
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

#pragma mark - ✅ Scan UI Throttle (关键)

- (void)scheduleScanUIUpdateCoalesced {
    self.pendingScanUIUpdate = YES;

    if (!self.scanUITimer) {
        // 每 0.25s 合并刷新一次
        self.scanUITimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                           target:self
                                                         selector:@selector(handleScanUITimerFire)
                                                         userInfo:nil
                                                          repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.scanUITimer forMode:NSRunLoopCommonModes];
    }
}

- (void)handleScanUITimerFire {
    if (!self.pendingScanUIUpdate) return;

    // 扫描结束就停
    if (self.scanMgr.snapshot.state != ASScanStateScanning) {
        self.pendingScanUIUpdate = NO;
        [self.scanUITimer invalidate];
        self.scanUITimer = nil;
        return;
    }

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastScanUIFire < 0.6) {
        return; // 还没到时间，保留 pending
    }
    self.lastScanUIFire = now;

    self.pendingScanUIUpdate = NO;
    [self updateModulesDuringScanning];
}

- (void)updateModulesDuringScanning {

    if (self.modules.count == 0) {
        self.modules = [self buildModulesFromManagerAndComputeClutterIsFinal:NO];
        [self.cv reloadData];
        return;
    }

    // ✅ 扫描中：只刷新数量/大小，并且“thumb 只设置一次”
    [self refreshCountsAndBytesOnlyKeepThumbs];

    // ✅ header 更新（已节流）
    [self updateHeaderDuringScanning];

    // ✅ 关键：对可见 cell，更新文字 + 如果封面已经拿到了就“只触发一次封面加载”
    NSArray<NSIndexPath *> *visible = [self.cv indexPathsForVisibleItems];
    for (NSIndexPath *ip in visible) {
        if (ip.item >= self.modules.count) continue;

        HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
        if (!cell) continue;

        ASHomeModuleVM *vm = self.modules[ip.item];

        [cell applyVM:vm humanSizeFn:^NSString *(uint64_t bytes) {
            return [HomeModuleCell humanSize:bytes];
        }];

        // ✅ 扫描中：一旦 vm.thumbLocalIds 有了，就显示封面；同 key 只触发一次，不会闪
        [self ensureCoverLoadedOnceDuringScanningForIndexPath:ip];
    }
}

- (void)requestCoverIfNeededForCell:(HomeModuleCell *)cell
                                 vm:(ASHomeModuleVM *)vm
                          indexPath:(NSIndexPath *)indexPath {

    if (![self hasPhotoAccess]) return;

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    NSString *coverKey = [self coverKeyForVM:vm];
    BOOL sameKey = (cell.appliedCoverKey && [cell.appliedCoverKey isEqualToString:coverKey]);

    if (sameKey) {
        // ✅ 同 key：如果请求还在飞，直接返回（最关键：不 cancel、不 placeholder）
        BOOL inFlight = (cell.reqId1 != PHInvalidImageRequestID) ||
                        (cell.reqId2 != PHInvalidImageRequestID) ||
                        (cell.videoReqId != PHInvalidImageRequestID);
        if (inFlight) return;

        // ✅ 同 key：如果已最终图，也返回
        BOOL hasAllFinal = cell.hasFinalThumb1 && (!vm.showsTwoThumbs || cell.hasFinalThumb2);
        if (hasAllFinal) return;

        // 同 key 但没最终图且也没请求在飞：允许补一次（不置 placeholder）
    } else {
        // ✅ key 变了：才 cancel + placeholder（只会发生一次，不会“疯狂闪”）
        [self cancelCellRequests:cell];
        [cell stopVideoIfNeeded];

        cell.hasFinalThumb1 = NO;
        cell.hasFinalThumb2 = NO;

        cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
        cell.img2.image = (vm.showsTwoThumbs ? [UIImage imageNamed:@"ic_placeholder"] : nil);
    }

    cell.appliedCoverKey = coverKey;
    cell.thumbKey = coverKey;                 // ✅ 回调校验统一用 coverKey
    cell.representedLocalIds = ids;

    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    if (vm.isVideoCover) {
        [self loadVideoPreviewForVM:vm intoCell:cell atIndexPath:indexPath];
    } else {
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
    }
}

- (void)updateHeaderDuringScanning {
    // 更新磁盘信息（free 会变）
    [self computeDiskSpace];

    // 触发 header 更新：不 reloadData，直接拿当前 header
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

#pragma mark - ✅ 只刷新数量/大小（保持封面不变，解决缩略图频繁刷新）

- (BOOL)refreshCountsAndBytesOnlyKeepThumbs {

    // 扫描中不做“存在性校验”，否则会 fetchAssetsWithLocalIdentifiers 巨重
    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    NSArray<ASAssetModel *> *shots = self.scanMgr.screenshots ?: @[];
    NSArray<ASAssetModel *> *recs  = self.scanMgr.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigs  = self.scanMgr.bigVideos ?: @[];
    NSArray<ASAssetModel *> *blurs = self.scanMgr.blurryPhotos ?: @[];
    NSArray<ASAssetModel *> *others = self.scanMgr.otherPhotos ?: @[];

    // flatten group
    NSArray<ASAssetModel *> *(^flattenGroups)(NSArray<ASAssetGroup *> *, ASGroupType) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetGroup *> *groups, ASGroupType type) {
        NSMutableArray<ASAssetModel *> *arr = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;
            if (g.assets.count < 2) continue;
            [arr addObjectsFromArray:g.assets];
        }
        return arr;
    };

    NSArray<ASAssetModel *> *simImg = flattenGroups(sim, ASGroupTypeSimilarImage);
    NSArray<ASAssetModel *> *dupImg = flattenGroups(dup, ASGroupTypeDuplicateImage);
    NSArray<ASAssetModel *> *simVid = flattenGroups(sim, ASGroupTypeSimilarVideo);
    NSArray<ASAssetModel *> *dupVid = flattenGroups(dup, ASGroupTypeDuplicateVideo);

    // 计算 clutter（扫描范围可清理总大小）
    NSMutableDictionary<NSString*, NSNumber*> *bytesById = [NSMutableDictionary dictionary];
    void (^collectUniq)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
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

    // 更新 modules
    BOOL changed = NO;
    for (ASHomeModuleVM *vm in self.modules) {
        switch (vm.type) {
            case ASHomeCardTypeSimilarPhotos: {
                uint64_t bytes = 0; for (ASAssetModel *m in simImg) bytes += m.fileSizeBytes;
                NSUInteger cnt = simImg.count;
                NSString *ct = [NSString stringWithFormat:@"%lu Photos", (unsigned long)cnt];

                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                // ✅ 封面只在没设置过且现在有可用封面时设置一次
                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0) {
                    NSArray<NSString *> *ids = [self thumbsFromFirstGroup:sim type:ASGroupTypeSimilarImage maxCount:2];
                    if (ids.count > 0) {
                        vm.thumbLocalIds = ids;
                        vm.thumbKey = [ids componentsJoinedByString:@"|"];
                        vm.didSetThumb = YES;
                        changed = YES;
                    }
                }
            } break;

            case ASHomeCardTypeDuplicatePhotos: {
                uint64_t bytes = 0; for (ASAssetModel *m in dupImg) bytes += m.fileSizeBytes;
                NSUInteger cnt = dupImg.count;
                NSString *ct = [NSString stringWithFormat:@"%lu Photos", (unsigned long)cnt];

                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0) {
                    NSArray<NSString *> *ids = [self thumbsFromFirstGroup:dup type:ASGroupTypeDuplicateImage maxCount:2];
                    if (ids.count > 0) {
                        // 小卡你想只显示 1 张：thumbLocalIds 保留 2 也行，但 showsTwoThumbs=NO 不会加载第二张
                        vm.thumbLocalIds = ids;
                        vm.thumbKey = [ids componentsJoinedByString:@"|"];
                        vm.didSetThumb = YES;
                        changed = YES;
                    }
                }
            } break;

            case ASHomeCardTypeScreenshots: {
                uint64_t bytes = 0; for (ASAssetModel *m in shots) bytes += m.fileSizeBytes;
                NSUInteger cnt = shots.count;
                NSString *ct = [NSString stringWithFormat:@"%lu Photos", (unsigned long)cnt];

                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0 && shots.firstObject.localId.length) {
                    vm.thumbLocalIds = @[shots.firstObject.localId];
                    vm.thumbKey = shots.firstObject.localId;
                    vm.didSetThumb = YES;
                    changed = YES;
                }
            } break;

            case ASHomeCardTypeBlurryPhotos: {
                uint64_t bytes = 0; for (ASAssetModel *m in blurs) bytes += m.fileSizeBytes;
                NSUInteger cnt = blurs.count;
                NSString *ct = [NSString stringWithFormat:@"%lu Photos", (unsigned long)cnt];

                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0 && blurs.firstObject.localId.length) {
                    vm.thumbLocalIds = @[blurs.firstObject.localId];
                    vm.thumbKey = blurs.firstObject.localId;
                    vm.didSetThumb = YES;
                    changed = YES;
                }
            } break;

            case ASHomeCardTypeOtherPhotos: {
                uint64_t bytes = 0; for (ASAssetModel *m in others) bytes += m.fileSizeBytes;
                NSUInteger cnt = others.count;
                NSString *ct = [NSString stringWithFormat:@"%lu Photos", (unsigned long)cnt];

                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0 && others.firstObject.localId.length) {
                    vm.thumbLocalIds = @[others.firstObject.localId];
                    vm.thumbKey = others.firstObject.localId;
                    vm.didSetThumb = YES;
                    changed = YES;
                }
            } break;

            case ASHomeCardTypeVideos: {
                NSUInteger cnt = simVid.count + dupVid.count + bigs.count + recs.count;
                uint64_t bytes = 0;
                for (ASAssetModel *m in simVid) bytes += m.fileSizeBytes;
                for (ASAssetModel *m in dupVid) bytes += m.fileSizeBytes;
                for (ASAssetModel *m in bigs) bytes += m.fileSizeBytes;
                for (ASAssetModel *m in recs) bytes += m.fileSizeBytes;

                NSString *ct = [NSString stringWithFormat:@"%lu Videos", (unsigned long)cnt];
                if (vm.totalBytes != bytes || vm.totalCount != cnt || ![vm.countText isEqualToString:ct]) {
                    vm.totalBytes = bytes;
                    vm.totalCount = cnt;
                    vm.countText = ct;
                    changed = YES;
                }

                if (!vm.didSetThumb && vm.thumbLocalIds.count == 0) {
                    NSString *cover = nil;
                    if (bigs.firstObject.localId.length) cover = bigs.firstObject.localId;
                    else if (recs.firstObject.localId.length) cover = recs.firstObject.localId;
                    else if (simVid.firstObject.localId.length) cover = simVid.firstObject.localId;
                    else if (dupVid.firstObject.localId.length) cover = dupVid.firstObject.localId;

                    if (cover.length) {
                        vm.thumbLocalIds = @[cover];
                        vm.thumbKey = cover;
                        vm.didSetThumb = YES;
                        changed = YES;
                    }
                }
            } break;
        }
    }

    return changed;
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

// 从一堆 localIds 里取 “最新日期”的前 limit 个（limit=1/2）
- (NSArray<NSString *> *)as_pickNewestLocalIds:(NSArray<NSString *> *)localIds limit:(NSUInteger)limit {
    if (limit == 0 || localIds.count == 0) return @[];

    // 防止极端数据量，封面没必要全量参与排序
    NSUInteger cap = MIN(localIds.count, 300);
    NSArray<NSString *> *cands = [localIds subarrayWithRange:NSMakeRange(0, cap)];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:cands options:nil];
    if (fr.count == 0) return @[];

    NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:fr.count];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [arr addObject:obj];
    }];

    [arr sortUsingComparator:^NSComparisonResult(PHAsset *a, PHAsset *b) {
        // 目标：日期降序
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

    // 取每个 group 的 “代表 id”：优先取 assets 里第一个有效的
    NSMutableArray<NSString *> *repIds = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *groupIds = [NSMutableArray array]; // 对应 repIds 的全量 ids（有效）

    for (ASAssetGroup *g in groups) {
        if (g.type != type) continue;

        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (ASAssetModel *m in g.assets) {
            if (!m.localId.length) continue;
            if (isValidId && !isValidId(m.localId)) continue;
            [ids addObject:m.localId];
        }
        if (ids.count < 2) continue; // 组内至少2个才算有效组

        [repIds addObject:ids.firstObject]; // 假设组内通常已按日期排列；即使不是，下面也会再按日期取 maxCount
        [groupIds addObject:ids];
    }

    if (repIds.count == 0) return @[];

    // 批量 fetch 代表 asset，找日期最新的那个 group
    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:repIds options:nil];
    if (fr.count == 0) {
        // 兜底：直接用第一个组
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

    // finished 后做存在性校验（避免缓存 localId 已被删）
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

    // flatten group（保持你原有逻辑：组内>=2才算）
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

    // 计算 clutter（扫描范围可清理总大小，去重 localId）
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

    // ---------- ✅ 封面：不依赖数组顺序，统一按 creationDate 取最新 ----------
    // Similar / Duplicate：从“最新日期的组”里取最新 N 张
    NSArray<NSString *> *simThumbs =
    [self as_thumbsFromNewestGroup:sim type:ASGroupTypeSimilarImage maxCount:2 isValid:isValidId];

    NSArray<NSString *> *dupThumbs =
    [self as_thumbsFromNewestGroup:dup type:ASGroupTypeDuplicateImage maxCount:2 isValid:isValidId];

    // Screenshots / Blurry / Other：从列表里取最新 1 张
    NSMutableArray<NSString *> *shotIds = [NSMutableArray arrayWithCapacity:shots.count];
    for (ASAssetModel *m in shots)  if (isValidId(m.localId)) [shotIds addObject:m.localId];
    NSArray<NSString *> *shotThumb = [self as_pickNewestLocalIds:shotIds limit:1];

    NSMutableArray<NSString *> *blurIds = [NSMutableArray arrayWithCapacity:blurs.count];
    for (ASAssetModel *m in blurs)  if (isValidId(m.localId)) [blurIds addObject:m.localId];
    NSArray<NSString *> *blurThumb = [self as_pickNewestLocalIds:blurIds limit:1];

    NSMutableArray<NSString *> *otherIds = [NSMutableArray arrayWithCapacity:others.count];
    for (ASAssetModel *m in others) if (isValidId(m.localId)) [otherIds addObject:m.localId];
    NSArray<NSString *> *otherThumb = [self as_pickNewestLocalIds:otherIds limit:1];

    // Videos：把 big/recs/simVid/dupVid 的 localId 合并后取最新 1 个
    NSMutableArray<NSString *> *videoIds = [NSMutableArray array];
    for (ASAssetModel *m in bigs)   if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in recs)   if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in simVid) if (isValidId(m.localId)) [videoIds addObject:m.localId];
    for (ASAssetModel *m in dupVid) if (isValidId(m.localId)) [videoIds addObject:m.localId];

    NSString *videoCoverId = [self as_pickNewestLocalIds:videoIds limit:1].firstObject;
    NSArray<NSString *> *videoThumb = videoCoverId.length ? @[videoCoverId] : @[];

    // ---------- VM 工厂 ----------
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

        // ✅ 初始 build 认为封面已定
        vm.didSetThumb = (vm.thumbLocalIds.count > 0);

        return vm;
    };

    // Similar Photos
    uint64_t simBytes = 0; for (ASAssetModel *m in simImg) simBytes += m.fileSizeBytes;
    NSString *simCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)simImg.count];
    ASHomeModuleVM *vmSimilar =
    makeVM(ASHomeCardTypeSimilarPhotos, @"Similar Photos", simCountText, simBytes, simImg.count, simThumbs, YES, NO);

    // Duplicate Photos
    uint64_t dupBytes = 0; for (ASAssetModel *m in dupImg) dupBytes += m.fileSizeBytes;
    NSString *dupCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)dupImg.count];
    ASHomeModuleVM *vmDup =
    makeVM(ASHomeCardTypeDuplicatePhotos, @"Duplicate Photos", dupCountText, dupBytes, dupImg.count, dupThumbs, NO, NO);

    // Screenshots
    uint64_t shotsBytes = 0; for (ASAssetModel *m in shots) shotsBytes += m.fileSizeBytes;
    NSString *shotsCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)shots.count];
    ASHomeModuleVM *vmShots =
    makeVM(ASHomeCardTypeScreenshots, @"Screenshots", shotsCountText, shotsBytes, shots.count, shotThumb, NO, NO);

    // Blurry
    uint64_t blurBytes = 0; for (ASAssetModel *m in blurs) blurBytes += m.fileSizeBytes;
    NSString *blurCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)blurs.count];
    ASHomeModuleVM *vmBlur =
    makeVM(ASHomeCardTypeBlurryPhotos, @"Blurry Photos", blurCountText, blurBytes, blurs.count, blurThumb, NO, NO);

    // Other
    uint64_t otherBytes = 0; for (ASAssetModel *m in others) otherBytes += m.fileSizeBytes;
    NSString *otherCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)others.count];
    ASHomeModuleVM *vmOther =
    makeVM(ASHomeCardTypeOtherPhotos, @"Other photos", otherCountText, otherBytes, others.count, otherThumb, NO, NO);

    // Videos
    NSUInteger vCount = simVid.count + dupVid.count + bigs.count + recs.count;
    uint64_t vBytes = 0;
    for (ASAssetModel *m in simVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in dupVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in bigs)   vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in recs)   vBytes += m.fileSizeBytes;

    NSString *vCountText = [NSString stringWithFormat:@"%lu Videos", (unsigned long)vCount];
    ASHomeModuleVM *vmVideos =
    makeVM(ASHomeCardTypeVideos, @"Videos", vCountText, vBytes, vCount, videoThumb, NO, YES);

    return @[ vmSimilar, vmVideos, vmDup, vmShots, vmBlur, vmOther ];
}

- (NSString *)renderKeyForVM:(ASHomeModuleVM *)vm indexPath:(NSIndexPath *)ip {
    // ✅ 不再拼 indexPath，不再搞两套 key
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
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                          cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    HomeModuleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeModuleCell"
                                                                     forIndexPath:indexPath];
    ASHomeModuleVM *vm = self.modules[indexPath.item];

    [cell applyVM:vm humanSizeFn:^NSString * _Nonnull(uint64_t bytes) {
        return [HomeModuleCell humanSize:bytes];
    }];

    // ✅ 没权限：永远占位 + 清请求 + 停视频（避免复用残影）
    if (![self hasPhotoAccess]) {
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

    // ✅ 有权限但没有 ids：占位（不请求）
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

    // ✅ 非视频卡：如果之前复用过视频，确保停掉
    if (!vm.isVideoCover) {
        if (cell.videoReqId != PHInvalidImageRequestID) {
            [self.imgMgr cancelImageRequest:cell.videoReqId];
            cell.videoReqId = PHInvalidImageRequestID;
        }
        [cell stopVideoIfNeeded];
    }

    // ✅ 核心：封面只在“需要时”请求；同 key 且 in-flight / 已最终图 → 不重来
    [self requestCoverIfNeededForCell:cell vm:vm indexPath:indexPath];

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

    return v;
}

#pragma mark - Layout

- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
shouldFullSpanAtIndexPath:(NSIndexPath *)indexPath {
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    return (vm.type == ASHomeCardTypeSimilarPhotos);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath {

    ASHomeModuleVM *vm = self.modules[indexPath.item];
    if (vm.type == ASHomeCardTypeSimilarPhotos) return kLargeCellH;

    NSInteger smallIdx = (NSInteger)indexPath.item - 1;
    if (smallIdx < 0) smallIdx = 0;
    return (smallIdx % 3 == 0) ? 306.0 : 246.0;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {

    CGFloat w = collectionView.bounds.size.width;

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = collectionView.safeAreaInsets.top;

    CGFloat top = safeTop + 12;
    CGFloat proH = 28;

    CGFloat spaceTitleH = 16;
    CGFloat spaceValueH = 40;
    CGFloat spaceTitleGap = 2;

    CGFloat barTopGap = 10;
    CGFloat barH = 12;
    CGFloat legendH = 24;
    CGFloat legendTopGap = 12;
    CGFloat bottomPad = 30;

    CGFloat contentH =
    top + 8
    + MAX(proH, (spaceTitleH + spaceTitleGap + spaceValueH))
    + barTopGap + barH
    + legendTopGap + legendH
    + bottomPad;

    return CGSizeMake(w, contentH);
}

#pragma mark - Tap

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {

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
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Videos"
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];

            void (^pushMode)(ASAssetListMode) = ^(ASAssetListMode mode) {
                ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:mode];
                [nav pushViewController:vc animated:YES];
            };

            [ac addAction:[UIAlertAction actionWithTitle:@"Similar Videos" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
                pushMode(ASAssetListModeSimilarVideo);
            }]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Duplicate Videos" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
                pushMode(ASAssetListModeDuplicateVideo);
            }]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Big Videos" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
                pushMode(ASAssetListModeBigVideos);
            }]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Screen Recordings" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
                pushMode(ASAssetListModeScreenRecordings);
            }]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

            [nav presentViewController:ac animated:YES completion:nil];
        } break;
    }
}

- (void)collectionView:(UICollectionView *)collectionView
didEndDisplayingCell:(UICollectionViewCell *)cell
   forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![cell isKindOfClass:HomeModuleCell.class]) return;
    HomeModuleCell *c = (HomeModuleCell *)cell;

    if (c.reqId1 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:c.reqId1];
        c.reqId1 = PHInvalidImageRequestID;
    }
    if (c.reqId2 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:c.reqId2];
        c.reqId2 = PHInvalidImageRequestID;
    }

    [self cancelCellRequests:c];
    [c stopVideoIfNeeded];
}

#pragma mark - Scan Cover One-Time Load

- (void)ensureCoverLoadedOnceDuringScanningForIndexPath:(NSIndexPath *)ip {
    if (![self hasPhotoAccess]) return;
    if (ip.item >= self.modules.count) return;

    ASHomeModuleVM *vm = self.modules[ip.item];
    if (vm.thumbLocalIds.count == 0) return;

    HomeModuleCell *cell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:ip];
    if (!cell) return;

    NSString *key = [self coverKeyForVM:vm];

    // ✅ 已经是这套封面 & 已经有最终图：不做任何事（避免闪）
    BOOL hasAllFinal = cell.hasFinalThumb1 && (!vm.showsTwoThumbs || cell.hasFinalThumb2);
    if ([cell.appliedCoverKey isEqualToString:key] && hasAllFinal) return;

    // ✅ 同一个 key 扫描期只触发一次请求
    if (cell.coverRequestKey && [cell.coverRequestKey isEqualToString:key]) return;

    cell.coverRequestKey = key;
    cell.representedLocalIds = vm.thumbLocalIds ?: @[];
    cell.thumbKey = key;
    cell.appliedCoverKey = key;

    // ✅ 新 key 第一次加载：先把 final 标记清掉
    cell.hasFinalThumb1 = NO;
    cell.hasFinalThumb2 = NO;

    [self cancelCellRequests:cell];
    [cell stopVideoIfNeeded];

    // ✅ 不要无脑置 placeholder！只有当当前没图时才放占位
    if (!cell.img1.image) cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
    if (vm.showsTwoThumbs && !cell.img2.image) cell.img2.image = [UIImage imageNamed:@"ic_placeholder"];

    if (vm.isVideoCover) {
        [self loadVideoPreviewForVM:vm intoCell:cell atIndexPath:ip];
    } else {
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:ip];
    }
}

#pragma mark - Thumbnails (Images)

- (void)loadThumbsForVM:(ASHomeModuleVM *)vm intoCell:(HomeModuleCell *)cell atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    NSString *expectedKey = cell.appliedCoverKey ?: @"";

    [self cancelCellRequests:cell];
    [cell stopVideoIfNeeded];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;

    CGSize s1 = cell.img1.bounds.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = cell.img1.frame.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = CGSizeMake(120, 120);
    CGSize t1 = CGSizeMake(s1.width * scale, s1.height * scale);

    CGSize s2 = cell.img2.bounds.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = cell.img2.frame.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = CGSizeMake(120, 120);
    CGSize t2 = CGSizeMake(s2.width * scale, s2.height * scale);

    __weak typeof(self) weakSelf = self;

    void (^setImg)(NSInteger, UIImage *, NSDictionary *) = ^(NSInteger idx, UIImage *img, NSDictionary *info) {
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            HomeModuleCell *nowCell = (HomeModuleCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            NSString *k1 = nowCell.appliedCoverKey ? nowCell.appliedCoverKey : @"";
            NSString *k2 = expectedKey ? expectedKey : @"";
            if (![k1 isEqualToString:k2]) return;
            if (![nowCell.representedLocalIds isEqualToArray:ids]) return;

            if (idx == 0) {
                // degraded 先上屏，但不置 final
                if (!degraded || !nowCell.hasFinalThumb1) {
                    nowCell.img1.image = img;
                    if (!degraded) nowCell.hasFinalThumb1 = YES;
                }
            } else {
                if (!degraded || !nowCell.hasFinalThumb2) {
                    nowCell.img2.image = img;
                    if (!degraded) nowCell.hasFinalThumb2 = YES;
                }
            }
        });
    };

    PHAsset *a0 = fr.count > 0 ? [fr objectAtIndex:0] : nil;
    PHAsset *a1 = fr.count > 1 ? [fr objectAtIndex:1] : nil;

    if (a0) {
        cell.reqId1 = [self.imgMgr requestImageForAsset:a0
                                             targetSize:t1
                                            contentMode:PHImageContentModeAspectFill
                                                options:opt
                                          resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(0, result, info ?: @{});
        }];
    }

    if (a1 && vm.showsTwoThumbs) {
        cell.reqId2 = [self.imgMgr requestImageForAsset:a1
                                             targetSize:t2
                                            contentMode:PHImageContentModeAspectFill
                                                options:opt
                                          resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(1, result, info ?: @{});
        }];
    } else {
        cell.img2.image = nil;
    }
}

#pragma mark - Video Preview

- (void)loadVideoPreviewForVM:(ASHomeModuleVM *)vm
                     intoCell:(HomeModuleCell *)cell
                  atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    // ✅ 统一用 appliedCoverKey 做回调校验（不要再用 thumbKey 拼 indexPath）
    NSString *expectedKey = cell.appliedCoverKey ?: @"";
    NSInteger token = cell.renderToken;

    // 这里不要再反复 placeholder/cancel（外层 requestCoverIfNeeded 已经处理 key 变化）
    // 但为了安全，确保旧视频播放资源停掉
    [cell stopVideoIfNeeded];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    PHAsset *asset = fr.firstObject;
    if (asset.mediaType != PHAssetMediaTypeVideo) {
        // 兜底：不是视频就按图片封面走
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
        return;
    }

    PHVideoRequestOptions *vopt = [PHVideoRequestOptions new];
    vopt.networkAccessAllowed = YES;
    vopt.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;

    __weak typeof(self) weakSelf = self;

    // ✅ 保存 request id，外层可 cancel
    cell.videoReqId = [self.imgMgr requestAVAssetForVideo:asset
                                                 options:vopt
                                           resultHandler:^(AVAsset * _Nullable avAsset,
                                                           AVAudioMix * _Nullable audioMix,
                                                           NSDictionary * _Nullable info) {

        // 被取消/失败直接返回
        if (!avAsset) return;
        if ([info[PHImageCancelledKey] boolValue]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            HomeModuleCell *nowCell = (HomeModuleCell *)[self.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            // ✅ 三重校验：token + key + ids
            if (nowCell.renderToken != token) return;
            NSString *k1 = nowCell.appliedCoverKey ? nowCell.appliedCoverKey : @"";
            NSString *k2 = expectedKey ? expectedKey : @"";
            if (![k1 isEqualToString:k2]) return;
            if (![nowCell.representedLocalIds isEqualToArray:ids]) return;

            // 如果此时 cell 已不再是视频卡（复用/切换），直接不做
            if (!nowCell.isVideoCover) return;

            // ---------- 1) 先拿 poster（允许 degraded 先上屏，避免“空白闪一下”） ----------
            PHImageRequestOptions *iopt = [PHImageRequestOptions new];
            iopt.networkAccessAllowed = YES;
            iopt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic; // ✅ 先给低清再给高清
            iopt.resizeMode = PHImageRequestOptionsResizeModeFast;
            iopt.synchronous = NO;

            CGSize posterSize = CGSizeMake(MAX(1, nowCell.img1.bounds.size.width) * UIScreen.mainScreen.scale,
                                           MAX(1, nowCell.img1.bounds.size.height) * UIScreen.mainScreen.scale);

            // ✅ 用 reqId1 记录 poster 请求（视频卡只用这一张，不会和图片卡冲突）
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

                    // degraded 先上屏，但不置 final
                    if (!degraded || !againCell.hasFinalThumb1) {
                        againCell.img1.image = result;
                        if (!degraded) againCell.hasFinalThumb1 = YES;
                    }
                });
            }];

            // ---------- 2) 再叠加 loop 播放 ----------
            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:avAsset];
            AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[item]];
            player.muted = YES;

            AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
            layer.frame = nowCell.img1.bounds;
            layer.videoGravity = AVLayerVideoGravityResizeAspectFill;

            // 清理旧 layer（保险）
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

@end

NS_ASSUME_NONNULL_END
