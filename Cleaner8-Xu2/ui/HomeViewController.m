#import "HomeViewController.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "ASPhotoScanManager.h"
#import "ASAssetListViewController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UI Constants

static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static const CGFloat kHomeSideInset = 16.0;
static const CGFloat kHomeGridGap   = 12.0;

static const CGFloat kHeaderHeight  = 200.0;   // 按截图大致高度，可再微调
static const CGFloat kLargeCellH    = 260.0;   // Similar Photos 大卡
static const CGFloat kSmallCellH    = 200.0;   // 其余小卡

static UIColor *kHomeBgColor(void) { return ASRGB(246, 248, 251); }
static UIColor *kCardShadowColor(void) { return [UIColor colorWithWhite:0 alpha:0.10]; }

// #666666FF
static UIColor *kTextGray(void) { return ASRGB(102, 102, 102); }

// 进度条颜色
static UIColor *kClutterRed(void) { return ASRGB(245, 19, 19); }      // #F51313FF
static UIColor *kAppDataYellow(void) { return ASRGB(255, 181, 46); }  // #FFB52EFF
static UIColor *kTotalGray(void) { return ASRGB(218, 218, 218); }     // #DADADAFF

static CGFloat ASHomeBgHeightForWidth(CGFloat width) {
    static UIImage *bgImg = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bgImg = [UIImage imageNamed:@"ic_home_bg"];
    });
    if (!bgImg || bgImg.size.width <= 0) return kHeaderHeight;
    return bgImg.size.height * (width / bgImg.size.width);
}

static uint64_t ASBytesFromGiB(double gib) {
    return (uint64_t)(gib * 1024.0 * 1024.0 * 1024.0);
}

// 把系统读到的 totalBytes 映射到 128/256/512/1TB/2TB 档位
static NSString *ASMarketingTotalString(uint64_t totalBytes) {
    double gib = (double)totalBytes / (1024.0 * 1024.0 * 1024.0);

    // 用“中点阈值”做分类，避免 121GiB 这种被误判
    if (gib < 192)  return @"128GB";  // <(128+256)/2
    if (gib < 384)  return @"256GB";  // <(256+512)/2
    if (gib < 768)  return @"512GB";  // <(512+1024)/2
    if (gib < 1536) return @"1TB";    // <(1024+2048)/2
    return @"2TB";
}

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
@property (nonatomic) ASHomeCardType type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *countText;     // 例如 “253 Photos” / “24 Videos”
@property (nonatomic) NSUInteger totalCount;
@property (nonatomic) uint64_t totalBytes;

// 封面（最多2张：Similar/Duplicate 用2张；其余1张；视频用1个视频id）
@property (nonatomic, strong) NSArray<NSString *> *thumbLocalIds; // 0/1/2
@property (nonatomic, copy) NSString *thumbKey;

// UI flags
@property (nonatomic) BOOL showsTwoThumbs;
@property (nonatomic) BOOL isVideoCover; // 视频卡片：动态预览
@end

@implementation ASHomeModuleVM @end

#pragma mark - Segmented Progress View (red/yellow/gray)

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

        // 关键：叠放顺序（灰在底，黄中间，红在最上）
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

    // 你要求：高度12，圆角6
    CGFloat radius = 6.0;
    CGFloat overlap = radius; // 用圆角宽度做覆盖，符合“左边被覆盖”的感觉

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

        // 1) 灰：全长底色（让“不分开”永远成立）
        self.grayView.frame = CGRectMake(0, 0, w, h);

        // 2) 黄：从红末尾开始，但左边被红覆盖（x = rw - overlap）
        if (yw > 0) {
            CGFloat yx = MAX(0, rw - overlap);
            CGFloat yRight = MIN(w, rw + yw);  // 逻辑右端
            CGFloat yWidth = MAX(0, yRight - yx);
            self.yellowView.frame = CGRectMake(yx, 0, yWidth, h);
        } else {
            self.yellowView.frame = CGRectZero;
        }

        // 3) 红：最上层，长度到 rw，并向右多盖 overlap（让红右边也是圆角但不露缝）
        if (rw > 0) {
            CGFloat rWidth = MIN(w, rw + ((yw > 0 || gw > 0) ? overlap : 0));
            self.redView.frame = CGRectMake(0, 0, rWidth, h);
        } else {
            self.redView.frame = CGRectZero;
        }
    }

    // 每段都圆角（你要求：红左右圆角，黄右圆角但左被盖，灰右圆角但左被盖）
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

        // Space To Clean
        _spaceTitleLabel = [UILabel new];
        _spaceTitleLabel.text = @"Space To Clean";
        _spaceTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        _spaceTitleLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceTitleLabel];

        // 大数字
        _spaceLabel = [UILabel new];
        _spaceLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightMedium];
        _spaceLabel.textColor = UIColor.blackColor;
        [self addSubview:_spaceLabel];

        // Pro 按钮
        _proBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _proBtn.layer.cornerRadius = 18;
        _proBtn.clipsToBounds = YES;
        _proBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        [_proBtn setTitle:@"Pro" forState:UIControlStateNormal];
        [_proBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

        // ✅ 让图标按原图显示，不被 tint 影响
        UIImage *vip = [[UIImage imageNamed:@"ic_vip"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (vip) {
            // ✅ 给个明确大小，防止图片太大/太小导致看不到
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
            [vip drawInRect:CGRectMake(0, 0, 24, 24)];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_proBtn setImage:scaled forState:UIControlStateNormal];
            _proBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            // ✅ 用 contentEdgeInsets + image/title 的间距方式居中
            _proBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
            _proBtn.imageEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 8);
            _proBtn.titleEdgeInsets = UIEdgeInsetsZero;
        } else {
            _proBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
        }

        _proBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _proBtn.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;

        [self addSubview:_proBtn];

        // 渐变层（#6F47E1FF -> #2E3BF0FF）
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

        // Legends（类型 #666666 12；数值 #000000 12）
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

    // Pro：右上
    CGFloat proH = 36.0;
    [_proBtn sizeToFit];
    CGFloat proW = MAX(78.0, _proBtn.bounds.size.width + 10.0);
    _proBtn.frame = CGRectMake(w - left - proW, top, proW, proH);
    _proBtn.layer.cornerRadius = 18.0;
    _proGradient.frame = _proBtn.bounds;
    _proGradient.cornerRadius = 18.0;

    // Space To Clean 与 Pro 顶对齐
    CGFloat titleH = 20.0;
    CGFloat bigH   = 40.0;

    CGFloat textMaxW = CGRectGetMinX(_proBtn.frame) - left - 10.0;
    _spaceTitleLabel.frame = CGRectMake(left, top, MAX(0, textMaxW), titleH);

    // Space to clean 距离大文字 5
    _spaceLabel.frame = CGRectMake(left,
                                   CGRectGetMaxY(_spaceTitleLabel.frame) + 5.0,
                                   MAX(0, textMaxW),
                                   bigH);

    // 大文字距离进度条 10；进度条高12
    _bar.frame = CGRectMake(left,
                            CGRectGetMaxY(_spaceLabel.frame) + 10.0,
                            w - left * 2.0,
                            12.0);

    // 进度条距离下面文字 15
    CGFloat legendsTop = CGRectGetMaxY(_bar.frame) + 15.0;

    // 圆点 8 直径；文字距离大小 2
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

#pragma mark - Waterfall Layout (2 columns + optional full-span)

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

    // Header
    if (self.headerHeight > 0) {
        NSIndexPath *hp = [NSIndexPath indexPathForItem:0 inSection:0];
        UICollectionViewLayoutAttributes *ha =
        [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                       withIndexPath:hp];
        ha.frame = CGRectMake(0, 0, width, self.headerHeight);
        [_cache addObject:ha];
        _contentHeight = CGRectGetMaxY(ha.frame);
    }

    // Columns y
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
            // Full width item (e.g. Similar big card)
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

        // choose the shortest column
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

- (nullable NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray<UICollectionViewLayoutAttributes *> *out = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *a in _cache) {
        if (CGRectIntersectsRect(a.frame, rect)) [out addObject:a];
    }
    return out;
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind
                                                                              atIndexPath:(NSIndexPath *)indexPath {
    for (UICollectionViewLayoutAttributes *a in _cache) {
        if (a.representedElementCategory == UICollectionElementCategorySupplementaryView &&
            [a.representedElementKind isEqualToString:elementKind] &&
            [a.indexPath isEqual:indexPath]) {
            return a;
        }
    }
    return nil;
}

- (CGSize)collectionViewContentSize {
    CGFloat w = self.collectionView ? self.collectionView.bounds.size.width : 0;
    return CGSizeMake(w, _contentHeight);
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES;
}

@end


static UIColor *kBadgeBlue(void) { return ASRGB(2, 77, 255); } // #024DFFFF

#pragma mark - Home Module Cell

@interface HomeModuleCell : UICollectionViewCell
@property (nonatomic) BOOL isLargeCard; // Similar 大卡

@property (nonatomic, copy) NSArray<NSString *> *representedLocalIds;
@property (nonatomic, copy) NSString *thumbKey;

@property (nonatomic, strong) UIView *shadowContainer;
@property (nonatomic, strong) UIView *cardView;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;

@property (nonatomic, strong) UIImageView *img1;
@property (nonatomic, strong) UIImageView *img2;

@property (nonatomic, strong) UIButton *badgeBtn;         // 蓝色胶囊（大小 + >）
@property (nonatomic, strong) UIImageView *playIconView;  // 视频左上角 ic_play

// video preview
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

        // ✅ 胶囊按钮（按你新规格）
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

        // ✅ 内边距：左15 右18 上下11
        _badgeBtn.contentEdgeInsets = UIEdgeInsetsMake(11, 15, 11, 18);
        _badgeBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _badgeBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

        // ✅ 关键：文字左、图标右
        _badgeBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

        _badgeBtn.userInteractionEnabled = NO;

        // ✅ 右图标 ic_todo，强制 9x16，并且不受 tint 影响
        UIImage *todo = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (todo) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(9, 16), NO, 0);
            [todo drawInRect:CGRectMake(0, 0, 9, 16)];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            [_badgeBtn setImage:scaled forState:UIControlStateNormal];
            _badgeBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

            // ✅ 图文间距 9（RTL 下用这组最直观）
            CGFloat spacing = 9.0;
            _badgeBtn.imageEdgeInsets = UIEdgeInsetsMake(0, spacing, 0, 0);
            _badgeBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, spacing);
        }

        _playIconView = [UIImageView new];
        _playIconView.image = [UIImage imageNamed:@"ic_play"];
        _playIconView.contentMode = UIViewContentModeScaleAspectFit;
        _playIconView.hidden = YES;

        // ✅ 别漏了标题/数量
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

    // ✅ 卡片整体内边距 15
    CGFloat pad = 15.0;

    // 标题
    self.titleLabel.frame = CGRectMake(pad, pad, w - pad * 2.0, 20);

    // ✅ 大标题离下面数量文字 4
    self.countLabel.frame = CGRectMake(pad,
                                       CGRectGetMaxY(self.titleLabel.frame) + 4,
                                       w - pad * 2.0,
                                       16);

    // ✅ 标题(准确说：数量)离下面图片 12
    CGFloat imgTop = CGRectGetMaxY(self.countLabel.frame) + 12;

    CGFloat imgBottomPad = pad;
    CGFloat imgH = MAX(0, h - imgTop - imgBottomPad);

    if (self.showsTwoThumbs) {
        // ✅ 图片间隔 10
        CGFloat gap = 10.0;
        CGFloat imgW = (w - pad * 2.0 - gap) / 2.0;

        self.img1.hidden = NO;
        self.img2.hidden = NO;

        self.img1.frame = CGRectMake(pad, imgTop, imgW, imgH);
        self.img2.frame = CGRectMake(CGRectGetMaxX(self.img1.frame) + gap, imgTop, imgW, imgH);
    } else {
        self.img1.hidden = NO;
        self.img2.hidden = YES;

        if (!self.isLargeCard) {
            // ✅ 小卡：图片贴左右、贴底，上边两角直角
            self.img1.layer.cornerRadius = 0;
            self.img1.frame = CGRectMake(0, imgTop, w, h - imgTop); // 贴左右贴底
        } else {
            // ✅ 大卡保持原来内边距与圆角
            self.img1.layer.cornerRadius = 12;
            self.img1.frame = CGRectMake(pad, imgTop, w - pad * 2.0, imgH);
        }

        self.img2.frame = CGRectZero;
    }

    // ✅ 手算：文字宽 + 图标宽 + 间距 + contentEdgeInsets
    NSString *t = self.badgeBtn.currentTitle ?: @"";
    UIFont *f = self.badgeBtn.titleLabel.font ?: [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    CGSize textSize = [t sizeWithAttributes:@{NSFontAttributeName: f}];

    UIImage *img = [self.badgeBtn imageForState:UIControlStateNormal];
    CGSize imgSize = img ? img.size : CGSizeZero;

    CGFloat spacing = img ? 9.0 : 0.0; // 你要的图文间距
    UIEdgeInsets in = self.badgeBtn.contentEdgeInsets;

    CGFloat badgeW = ceil(in.left + textSize.width + spacing + imgSize.width + in.right);
    CGFloat badgeH = ceil(in.top + MAX(textSize.height, imgSize.height) + in.bottom);

    CGFloat inset = 10.0;

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


    [self.cardView bringSubviewToFront:self.badgeBtn];
    [self.cardView bringSubviewToFront:self.playIconView];

    // play icon（视频左上角）
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

    self.representedLocalIds = @[];
    self.thumbKey = nil;

    self.reqId1 = PHInvalidImageRequestID;
    self.reqId2 = PHInvalidImageRequestID;

    self.img1.image = nil;
    self.img2.image = nil;

    [self stopVideoIfNeeded];
    self.playIconView.hidden = YES;
}

- (void)stopVideoIfNeeded {
    if (self.player) {
        [self.player pause];
    }
    if (self.playerLayer) {
        [self.playerLayer removeFromSuperlayer];
    }
    self.playerLayer = nil;
    self.looper = nil;
    self.player = nil;
}

- (void)applyVM:(ASHomeModuleVM *)vm humanSizeFn:(NSString * _Nonnull (^)(uint64_t bytes))humanSize {
    self.showsTwoThumbs = vm.showsTwoThumbs;
    self.isVideoCover = vm.isVideoCover;

    self.isLargeCard = (vm.type == ASHomeCardTypeSimilarPhotos);

    self.titleLabel.text = vm.title ?: @"";
    self.countLabel.text = vm.countText ?: @"";

    NSString *sizeText = humanSize(vm.totalBytes);
    NSString *badge = [NSString stringWithFormat:@"%@", sizeText];
    [self.badgeBtn setTitle:badge forState:UIControlStateNormal];
    [self.badgeBtn invalidateIntrinsicContentSize];
    [self setNeedsLayout];
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
@property (nonatomic, strong) UIImageView *topBgView;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<ASHomeModuleVM *> *modules;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

// 空间数据（Header）
@property (nonatomic) uint64_t diskTotalBytes;
@property (nonatomic) uint64_t diskFreeBytes;
@property (nonatomic) uint64_t clutterBytes;
@property (nonatomic) uint64_t appDataBytes;

// 去重集合（用于一键删除/也可用于 clutter）
@property (nonatomic, strong) NSSet<NSString *> *allCleanableIds;
@property (nonatomic) uint64_t allCleanableBytes;
@end

@implementation HomeViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = kHomeBgColor();

    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    [self setupUI];

    __weak typeof(self) weakSelf = self;
    [self.scanMgr subscribeProgress:^(ASScanSnapshot *snapshot) {
        if (!weakSelf.cv) return;

        // 扫描中不频繁 reload，避免闪烁
        if (snapshot.state == ASScanStateScanning) return;

        if (snapshot.state == ASScanStateFinished) {
            [weakSelf rebuildModulesAndReload];
        }
    }];

    [self.scanMgr loadCacheAndCheckIncremental];
    [self rebuildModulesAndReload];

    [self requestPhotoPermissionThenStartScan];
}

#pragma mark - Permission / Scan

- (void)requestPhotoPermissionThenStartScan {
    PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited) {
        [self startScanIfNeeded];
        return;
    }

    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                [self startScanIfNeeded];
            }
        });
    }];
}

- (void)startScanIfNeeded {
    if (self.scanMgr.snapshot.state == ASScanStateFinished) return;

    __weak typeof(self) weakSelf = self;
    [self.scanMgr startFullScanWithProgress:nil completion:^(ASScanSnapshot *snapshot, NSError * _Nullable error) {
        [weakSelf rebuildModulesAndReload];
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
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.cv.frame = self.view.bounds;

    CGFloat w = self.view.bounds.size.width;

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat bgH = ASHomeBgHeightForWidth(w);

    // ✅ 背景固定在顶部，不随列表滚动，并覆盖到状态栏
    self.topBgView.frame = CGRectMake(0, 0, w, bgH + safeTop);

    UIEdgeInsets safe = self.view.safeAreaInsets;
    self.cv.contentInset = UIEdgeInsetsMake(0, 0, safe.bottom + 70, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;
    
    ASWaterfallLayout *wf = (ASWaterfallLayout *)self.cv.collectionViewLayout;
    if ([wf isKindOfClass:ASWaterfallLayout.class]) {
        wf.headerHeight = [self collectionView:self.cv layout:wf referenceSizeForHeaderInSection:0].height;
        [wf invalidateLayout];
    }
}

#pragma mark - Data Build

- (void)rebuildModulesAndReload {
    [self computeDiskSpace];
    self.modules = [self buildModulesFromManagerAndComputeClutter];

    [UIView performWithoutAnimation:^{
        [self.cv reloadData];
    }];
}

- (void)computeDiskSpace {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    uint64_t total = [attrs[NSFileSystemSize] unsignedLongLongValue];
    uint64_t free  = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];

    self.diskTotalBytes = total;
    self.diskFreeBytes = free;
}

- (NSArray<ASHomeModuleVM *> *)buildModulesFromManagerAndComputeClutter {

    // 取扫描结果
    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    NSArray<ASAssetModel *> *shots = self.scanMgr.screenshots ?: @[];
    NSArray<ASAssetModel *> *recs  = self.scanMgr.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigs  = self.scanMgr.bigVideos ?: @[];
    NSArray<ASAssetModel *> *blurs = self.scanMgr.blurryPhotos ?: @[];
    NSArray<ASAssetModel *> *others = self.scanMgr.otherPhotos ?: @[];

    // finished 后做存在性校验，避免缓存的 localId 已被删导致封面/计数错
    BOOL needExistCheck = (self.scanMgr.snapshot.state == ASScanStateFinished);
    NSMutableSet<NSString *> *existIdSet = nil;
    if (needExistCheck) {
        NSMutableArray<NSString *> *candidateIds = [NSMutableArray array];

        void (^collectIdsFromModels)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
            for (ASAssetModel *m in arr) if (m.localId.length) [candidateIds addObject:m.localId];
        };
        void (^collectIdsFromGroups)(NSArray<ASAssetGroup *> *) = ^(NSArray<ASAssetGroup *> *groups) {
            for (ASAssetGroup *g in groups) {
                for (ASAssetModel *m in g.assets) if (m.localId.length) [candidateIds addObject:m.localId];
            }
        };

        collectIdsFromGroups(sim);
        collectIdsFromGroups(dup);
        collectIdsFromModels(shots);
        collectIdsFromModels(recs);
        collectIdsFromModels(bigs);
        collectIdsFromModels(blurs);
        collectIdsFromModels(others);

        PHFetchResult<PHAsset *> *existFR = [PHAsset fetchAssetsWithLocalIdentifiers:candidateIds options:nil];
        existIdSet = [NSMutableSet setWithCapacity:existFR.count];
        [existFR enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.localIdentifier.length) [existIdSet addObject:obj.localIdentifier];
        }];
    }

    BOOL (^isValidId)(NSString *) = ^BOOL(NSString *lid) {
        if (!lid.length) return NO;
        if (!existIdSet) return YES;
        return [existIdSet containsObject:lid];
    };

    // flatten group (similar/duplicate)
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

    NSArray<NSString *> *(^thumbsFromFirstValidGroup)(NSArray<ASAssetGroup *> *, ASGroupType, NSUInteger) =
    ^NSArray<NSString *>* (NSArray<ASAssetGroup *> *groups, ASGroupType type, NSUInteger maxCount) {
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;

            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (!isValidId(m.localId)) continue;
                [ids addObject:m.localId];
                if (ids.count == maxCount) break;
            }
            if (ids.count >= 1) return ids;
        }
        return @[];
    };

    // Similar/Duplicate photo flat arrays（用于统计）
    NSArray<ASAssetModel *> *simImg = flattenGroups(sim, ASGroupTypeSimilarImage);
    NSArray<ASAssetModel *> *dupImg = flattenGroups(dup, ASGroupTypeDuplicateImage);

    // Videos 统计：相似视频 + 重复视频 + 大视频 + 录屏
    NSArray<ASAssetModel *> *simVid = flattenGroups(sim, ASGroupTypeSimilarVideo);
    NSArray<ASAssetModel *> *dupVid = flattenGroups(dup, ASGroupTypeDuplicateVideo);

    // 过滤 models 数组（shots/recs/bigs/blurs/others）
    NSArray<ASAssetModel *> *(^filterValidModels)(NSArray<ASAssetModel *> *) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetModel *> *arr) {
        NSMutableArray<ASAssetModel *> *out = [NSMutableArray array];
        for (ASAssetModel *m in arr) {
            if (isValidId(m.localId)) [out addObject:m];
        }
        return out;
    };

    shots = filterValidModels(shots);
    recs  = filterValidModels(recs);
    bigs  = filterValidModels(bigs);
    blurs = filterValidModels(blurs);
    others = filterValidModels(others);

    // 去重总集合（用于 clutter）
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

    // Clutter = photos + video（这里取“可清理扫描范围内”的聚合，跟首页一致）
    self.clutterBytes = self.allCleanableBytes;

    // App&Data = used - clutter
    uint64_t used = (self.diskTotalBytes > self.diskFreeBytes) ? (self.diskTotalBytes - self.diskFreeBytes) : 0;
    self.appDataBytes = (used > self.clutterBytes) ? (used - self.clutterBytes) : 0;

    // 构造 VM
    ASHomeModuleVM *(^makeVM)(ASHomeCardType, NSString *, NSString *, uint64_t, NSArray<NSString *> *, BOOL, BOOL) =
    ^ASHomeModuleVM *(ASHomeCardType type,
                      NSString *title,
                      NSString *countText,
                      uint64_t totalBytes,
                      NSArray<NSString *> *thumbIds,
                      BOOL showsTwo,
                      BOOL isVideoCover) {

        ASHomeModuleVM *vm = [ASHomeModuleVM new];
        vm.type = type;
        vm.title = title;
        vm.countText = countText ?: @"";
        vm.totalBytes = totalBytes;
        vm.thumbLocalIds = thumbIds ?: @[];
        vm.thumbKey = [vm.thumbLocalIds componentsJoinedByString:@"|"];
        vm.showsTwoThumbs = showsTwo;
        vm.isVideoCover = isVideoCover;
        return vm;
    };

    // Similar Photos（2张封面取第一组相似图两张）
    NSArray<NSString *> *simThumbs = thumbsFromFirstValidGroup(sim, ASGroupTypeSimilarImage, 2);
    uint64_t simBytes = 0;
    for (ASAssetModel *m in simImg) simBytes += m.fileSizeBytes;
    NSString *simCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)simImg.count];
    ASHomeModuleVM *vmSimilar = makeVM(ASHomeCardTypeSimilarPhotos, @"Similar Photos", simCountText, simBytes, simThumbs, YES, NO);

    // Duplicate Photos（2张封面取第一组重复图两张）
    NSArray<NSString *> *dupThumbs = thumbsFromFirstValidGroup(dup, ASGroupTypeDuplicateImage, 2);
    uint64_t dupBytes = 0;
    for (ASAssetModel *m in dupImg) dupBytes += m.fileSizeBytes;
    NSString *dupCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)dupImg.count];
    ASHomeModuleVM *vmDup = makeVM(ASHomeCardTypeDuplicatePhotos, @"Duplicate Photos", dupCountText, dupBytes, dupThumbs, NO /*小卡只显示1图*/, NO);

    // Screenshots（1张封面取第一张）
    uint64_t shotsBytes = 0;
    for (ASAssetModel *m in shots) shotsBytes += m.fileSizeBytes;
    NSString *shotsCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)shots.count];
    NSArray<NSString *> *shotThumb = shots.count ? @[shots.firstObject.localId ?: @""] : @[];
    ASHomeModuleVM *vmShots = makeVM(ASHomeCardTypeScreenshots, @"Screenshots", shotsCountText, shotsBytes, shotThumb, NO, NO);

    // Blurry Photos
    uint64_t blurBytes = 0;
    for (ASAssetModel *m in blurs) blurBytes += m.fileSizeBytes;
    NSString *blurCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)blurs.count];
    NSArray<NSString *> *blurThumb = blurs.count ? @[blurs.firstObject.localId ?: @""] : @[];
    ASHomeModuleVM *vmBlur = makeVM(ASHomeCardTypeBlurryPhotos, @"Blurry Photos", blurCountText, blurBytes, blurThumb, NO, NO);

    // Other Photos
    uint64_t otherBytes = 0;
    for (ASAssetModel *m in others) otherBytes += m.fileSizeBytes;
    NSString *otherCountText = [NSString stringWithFormat:@"%lu Photos", (unsigned long)others.count];
    NSArray<NSString *> *otherThumb = others.count ? @[others.firstObject.localId ?: @""] : @[];
    ASHomeModuleVM *vmOther = makeVM(ASHomeCardTypeOtherPhotos, @"Other photos", otherCountText, otherBytes, otherThumb, NO, NO);

    // Videos（相似视频+重复视频+大视频+录屏 总数/总大小；封面取第一个视频，动态播放）
    NSUInteger vCount = simVid.count + dupVid.count + bigs.count + recs.count;
    uint64_t vBytes = 0;
    for (ASAssetModel *m in simVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in dupVid) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in bigs) vBytes += m.fileSizeBytes;
    for (ASAssetModel *m in recs) vBytes += m.fileSizeBytes;

    NSString *vCountText = [NSString stringWithFormat:@"%lu Videos", (unsigned long)vCount];
    NSString *videoCoverId = nil;
    // cover 优先：大视频 > 录屏 > 相似视频 > 重复视频（你也可以按业务调整）
    if (bigs.firstObject.localId.length) videoCoverId = bigs.firstObject.localId;
    else if (recs.firstObject.localId.length) videoCoverId = recs.firstObject.localId;
    else if (simVid.firstObject.localId.length) videoCoverId = simVid.firstObject.localId;
    else if (dupVid.firstObject.localId.length) videoCoverId = dupVid.firstObject.localId;

    NSArray<NSString *> *videoThumb = videoCoverId.length ? @[videoCoverId] : @[];
    ASHomeModuleVM *vmVideos = makeVM(ASHomeCardTypeVideos, @"Videos", vCountText, vBytes, videoThumb, NO, YES);

    // 排序：按截图：Similar(大卡) -> Videos -> Duplicate -> Screenshots -> Blurry -> Other
    return @[ vmSimilar, vmVideos, vmDup, vmShots, vmBlur, vmOther ];
}

#pragma mark - Collection DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                          cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    HomeModuleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeModuleCell" forIndexPath:indexPath];
    ASHomeModuleVM *vm = self.modules[indexPath.item];

    [cell applyVM:vm humanSizeFn:^NSString * _Nonnull(uint64_t bytes) {
        return [HomeModuleCell humanSize:bytes];
    }];

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    NSString *newKey = vm.thumbKey ?: @"";
    BOOL thumbChanged = (cell.thumbKey == nil) || ![cell.thumbKey isEqualToString:newKey];

    cell.representedLocalIds = ids;
    cell.thumbKey = newKey;

    if (ids.count == 0) {
        if (thumbChanged) {
            cell.img1.image = nil;
            cell.img2.image = nil;
            [cell stopVideoIfNeeded];
        }
        return cell;
    }

    // 只有 thumbKey 变化才请求（防闪）
    if (thumbChanged) {
        [cell setNeedsLayout];
        [cell layoutIfNeeded];

        if (vm.isVideoCover) {
            [self loadVideoPreviewForVM:vm intoCell:cell atIndexPath:indexPath];
        } else {
            [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
        }
    }

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
    // Similar 大卡全宽
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    return (vm.type == ASHomeCardTypeSimilarPhotos);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath {

    ASHomeModuleVM *vm = self.modules[indexPath.item];
    if (vm.type == ASHomeCardTypeSimilarPhotos) {
        return kLargeCellH; // 260
    }

    // 小卡：两列交错 306 / 246（从第一个小卡开始算）
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
            // 合并视频模块点击：给用户一个入口选择具体列表（不改你现有 listMode）
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

#pragma mark - Thumbnails (Images)

- (void)loadThumbsForVM:(ASHomeModuleVM *)vm intoCell:(HomeModuleCell *)cell atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    // cancel old requests
    if (cell.reqId1 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId1];
        cell.reqId1 = PHInvalidImageRequestID;
    }
    if (cell.reqId2 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId2];
        cell.reqId2 = PHInvalidImageRequestID;
    }

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
        if (degraded) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            HomeModuleCell *nowCell = (HomeModuleCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;
            if (![nowCell.representedLocalIds isEqualToArray:vm.thumbLocalIds ?: @[]]) return;

            if (idx == 0) nowCell.img1.image = img;
            else nowCell.img2.image = img;
        });
    };

    PHAsset *a0 = fr.count > 0 ? [fr objectAtIndex:0] : nil;
    PHAsset *a1 = fr.count > 1 ? [fr objectAtIndex:1] : nil;

    if (a0) {
        PHImageRequestID rid =
        [self.imgMgr requestImageForAsset:a0
                               targetSize:t1
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(0, result, info ?: @{});
        }];
        cell.reqId1 = rid;
    }

    if (a1 && vm.showsTwoThumbs) {
        PHImageRequestID rid =
        [self.imgMgr requestImageForAsset:a1
                               targetSize:t2
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(1, result, info ?: @{});
        }];
        cell.reqId2 = rid;
    } else {
        cell.img2.image = nil;
    }
}

#pragma mark - Video Preview

- (void)loadVideoPreviewForVM:(ASHomeModuleVM *)vm intoCell:(HomeModuleCell *)cell atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    // cancel image requests
    if (cell.reqId1 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId1];
        cell.reqId1 = PHInvalidImageRequestID;
    }
    if (cell.reqId2 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId2];
        cell.reqId2 = PHInvalidImageRequestID;
    }

    [cell stopVideoIfNeeded];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    PHAsset *asset = fr.firstObject;
    if (asset.mediaType != PHAssetMediaTypeVideo) {
        // fallback：用封面帧
        [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
        return;
    }

    PHVideoRequestOptions *vopt = [PHVideoRequestOptions new];
    vopt.networkAccessAllowed = YES;
    vopt.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;

    __weak typeof(self) weakSelf = self;

    [self.imgMgr requestAVAssetForVideo:asset options:vopt resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {

        if (!avAsset) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            HomeModuleCell *nowCell = (HomeModuleCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;
            if (![nowCell.representedLocalIds isEqualToArray:vm.thumbLocalIds ?: @[]]) return;

            // 先给一个 poster（避免 player 准备时空白）
            PHImageRequestOptions *iopt = [PHImageRequestOptions new];
            iopt.networkAccessAllowed = YES;
            iopt.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
            iopt.resizeMode = PHImageRequestOptionsResizeModeFast;

            CGSize posterSize = CGSizeMake(nowCell.img1.bounds.size.width * UIScreen.mainScreen.scale,
                                           nowCell.img1.bounds.size.height * UIScreen.mainScreen.scale);

            [weakSelf.imgMgr requestImageForAsset:asset
                                      targetSize:posterSize
                                     contentMode:PHImageContentModeAspectFill
                                         options:iopt
                                   resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info2) {
                BOOL degraded = [info2[PHImageResultIsDegradedKey] boolValue];
                if (degraded) return;
                if (result) nowCell.img1.image = result;
            }];

            // 循环播放（静音）
            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:avAsset];
            AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[item]];
            player.muted = YES;

            AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
            layer.frame = nowCell.img1.bounds;
            layer.videoGravity = AVLayerVideoGravityResizeAspectFill;

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
