#import "ImageCompressionMainViewController.h"
#import "ImageCompressionQualityViewController.h"
#import "ASMediaPreviewViewController.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

#pragma mark - Helpers (static)
static NSString * const kASImgSizeCachePlist = @"as_img_size_cache_v2.plist";

static inline NSString *ASImgSizeCachePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:kASImgSizeCachePlist];
}

static inline UIColor *ASBlue(void)   { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline UIColor *ASBlue10(void) { return [ASBlue() colorWithAlphaComponent:0.10]; }

static NSString *ASHumanSizeShort(uint64_t bytes) {
    double b = (double)bytes;
    double mb = b / (1024.0 * 1024.0);
    double gb = mb / 1024.0;
    if (gb >= 1.0) return [NSString stringWithFormat:@"%.2fGB", gb];
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.0fMB", mb];
    if (b >= 1024.0) return [NSString stringWithFormat:@"%.1fKB", b/1024.0];
    return [NSString stringWithFormat:@"%.0fB", b];
}

static NSString *ASMBPill(uint64_t bytes) {
    if (bytes == 0) return @"--";
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.0fMB", mb];
    return [NSString stringWithFormat:@"%.1fMB", mb];
}

#pragma mark - Padding Label (for pill)

@interface ASPaddingLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets textInsets;
@end

@implementation ASPaddingLabel
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _textInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    }
    return self;
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}
- (CGSize)intrinsicContentSize {
    CGSize s = [super intrinsicContentSize];
    s.width  += self.textInsets.left + self.textInsets.right;
    s.height += self.textInsets.top  + self.textInsets.bottom;
    return s;
}
@end

#pragma mark - Section Model

@interface ASImgSizeSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@end
@implementation ASImgSizeSection @end

#pragma mark - Header (Section)

@interface ASImgSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation ASImgSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.blackColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
@end

#pragma mark - Cell (corner 12, check top-right, pill bottom-right)

@interface ASImgCell : UICollectionViewCell
@property (nonatomic, assign) PHImageRequestID requestId;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) ASPaddingLabel *pill;
@property (nonatomic, strong) UIButton *checkBtn;     // icon only
@property (nonatomic, strong) UIButton *checkTapBtn;  // bigger tap area
@property (nonatomic, copy) NSString *representedAssetIdentifier;
- (void)applySelectedUI:(BOOL)sel;
@end

@implementation ASImgCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = 12;
        self.contentView.layer.masksToBounds = YES;
        _requestId = PHInvalidImageRequestID;

        _thumbView = [UIImageView new];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_thumbView];

        _checkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _checkBtn.userInteractionEnabled = NO;
        _checkBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_checkBtn];

        _checkTapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _checkTapBtn.backgroundColor = UIColor.clearColor;
        _checkTapBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_checkTapBtn];

        _pill = [ASPaddingLabel new];
        _pill.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _pill.textColor = UIColor.whiteColor;
        _pill.backgroundColor = ASBlue();
        _pill.textAlignment = NSTextAlignmentCenter;
        _pill.layer.cornerRadius = 14;
        _pill.layer.masksToBounds = YES;
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_pill];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumbView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_checkBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_checkBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_checkBtn.widthAnchor constraintEqualToConstant:23],
            [_checkBtn.heightAnchor constraintEqualToConstant:23],

            // bigger tappable area
            [_checkTapBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_checkTapBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_checkTapBtn.widthAnchor constraintEqualToConstant:56],
            [_checkTapBtn.heightAnchor constraintEqualToConstant:56],

            // pill bottom-right
            [_pill.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            [_pill.heightAnchor constraintEqualToConstant:28],
        ]];

        self.thumbView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
        [self applySelectedUI:NO];
        self.pill.text = @"--";
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.requestId = PHInvalidImageRequestID; // 取消在 VC 里做
    self.representedAssetIdentifier = nil;
    self.thumbView.image = nil;
    self.pill.text = @"--";
    [self applySelectedUI:NO];
}

- (void)applySelectedUI:(BOOL)sel {
    static UIImage *onImg = nil;
    static UIImage *offImg = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        onImg  = [[UIImage imageNamed:@"ic_select_s"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        offImg = [[UIImage imageNamed:@"ic_select_n"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });

    [self.checkBtn setImage:(sel ? onImg : offImg) forState:UIControlStateNormal];
}

@end

#pragma mark - Preview VC (tap to preview)

@interface ASImagePreviewVC : UIViewController
@property (nonatomic, strong) PHAsset *asset;
@end

@implementation ASImagePreviewVC {
    UIImageView *_iv;
}
- (instancetype)initWithAsset:(PHAsset *)a {
    if (self = [super init]) { _asset = a; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _iv = [UIImageView new];
    _iv.contentMode = UIViewContentModeScaleAspectFit;
    _iv.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_iv];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0,*)) [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [_iv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_iv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_iv.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_iv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [close.widthAnchor constraintEqualToConstant:34],
        [close.heightAnchor constraintEqualToConstant:34],
    ]];

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    [[PHImageManager defaultManager] requestImageForAsset:self.asset
                                              targetSize:CGSizeMake(2500, 2500)
                                             contentMode:PHImageContentModeAspectFit
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) self->_iv.image = result;
    }];
}
- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface ASMiniCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UIButton *delBtn;
@property (nonatomic, copy) NSString *representedId;
@property (nonatomic, assign) PHImageRequestID requestId;
@end

@implementation ASMiniCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.requestId = PHInvalidImageRequestID;

        self.clipsToBounds = NO;
        self.layer.masksToBounds = NO;
        self.contentView.clipsToBounds = NO;
        self.contentView.layer.masksToBounds = NO;

        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.clipsToBounds = YES;
        self.iv.layer.cornerRadius = 8;
        self.iv.layer.masksToBounds = YES;
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.iv];

        self.delBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.delBtn.translatesAutoresizingMaskIntoConstraints = NO;

        self.delBtn.layer.cornerRadius = 12;
        self.delBtn.layer.masksToBounds = YES;

        UIImage *del = [[UIImage imageNamed:@"ic_delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.delBtn setImage:del forState:UIControlStateNormal];

        self.delBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
        self.delBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

        self.delBtn.layer.zPosition = 1000;

        [self.contentView addSubview:self.delBtn];

        [NSLayoutConstraint activateConstraints:@[
            [self.iv.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.iv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.iv.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [self.delBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:-8],
            [self.delBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:8],
            [self.delBtn.widthAnchor constraintEqualToConstant:24],
            [self.delBtn.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedId = nil;
    self.requestId = PHInvalidImageRequestID;
    self.iv.image = nil;
}

/// ✅ 重要：按钮有一部分在 cell bounds 外时，默认点不到
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([super pointInside:point withEvent:event]) return YES;

    // 把点击点转换到 contentView，再判断是否落在 delBtn 上
    CGPoint p = [self convertPoint:point toView:self.contentView];
    return CGRectContainsPoint(self.delBtn.frame, p);
}

@end

#pragma mark - Selected Bar (background touches bottom, content in safeArea)

@interface ASSelectedBar : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIButton *goBtn;

@property (nonatomic, strong) NSArray<PHAsset *> *selectedAssets;
@property (nonatomic, copy) void(^onRemove)(PHAsset *a);
@property (nonatomic, copy) void(^onGo)(void);

@property (nonatomic, strong) PHCachingImageManager *cachingMgr;
@end

@implementation ASSelectedBar

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UIView *cardView = [UIView new];
        cardView.backgroundColor = UIColor.whiteColor;
        cardView.translatesAutoresizingMaskIntoConstraints = NO;
        cardView.layer.cornerRadius = 16;
        if (@available(iOS 11.0,*)) {
            cardView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
        cardView.layer.masksToBounds = YES;

        // ✅ 外层自己不裁剪，用来显示阴影
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.layer.masksToBounds = NO;

        // ✅ 阴影：Offset (0, -5), blur 10, color #00000033
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = (0x33 / 255.0);        // ≈0.2
        self.layer.shadowOffset = CGSizeMake(0, -5);
        self.layer.shadowRadius = 10;

        [self addSubview:cardView];
        [NSLayoutConstraint activateConstraints:@[
            [cardView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [cardView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [cardView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [cardView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        self.cachingMgr = [PHCachingImageManager new];

        self.titleLabel = [UILabel new];
        self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        self.titleLabel.textColor = UIColor.blackColor;

        UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
        lay.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        lay.minimumLineSpacing = 10;
        lay.sectionInset = UIEdgeInsetsMake(0, 20, 0, 20);

        self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
        self.cv.backgroundColor = UIColor.clearColor;
        self.cv.showsHorizontalScrollIndicator = NO;
        self.cv.dataSource = self;
        self.cv.delegate = self;
        [self.cv registerClass:ASMiniCell.class forCellWithReuseIdentifier:@"mini"];
        self.cv.clipsToBounds = NO;
        self.cv.layer.masksToBounds = NO;
        
        self.goBtn = [UIButton buttonWithType:UIButtonTypeCustom];

        UIImage *todoImg = [[UIImage imageNamed:@"ic_todo_big"]
                            imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.goBtn setImage:todoImg forState:UIControlStateNormal];

        self.goBtn.backgroundColor = UIColor.clearColor;
        self.goBtn.adjustsImageWhenHighlighted = NO;
        self.goBtn.showsTouchWhenHighlighted = NO;
        self.goBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.goBtn addTarget:self action:@selector(onGoTap) forControlEvents:UIControlEventTouchUpInside];

        [cardView addSubview:self.titleLabel];
        [cardView addSubview:self.cv];
        [cardView addSubview:self.goBtn];

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.cv.translatesAutoresizingMaskIntoConstraints = NO;
        self.goBtn.translatesAutoresizingMaskIntoConstraints = NO;

        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:20],

            [self.goBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.goBtn.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.goBtn.widthAnchor constraintEqualToConstant:60],
            [self.goBtn.heightAnchor constraintEqualToConstant:36],

            [self.cv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.cv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.cv.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
            [self.cv.heightAnchor constraintEqualToConstant:64],

            // content bottom sits on safeArea (background still reaches screen bottom)
            [self.cv.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)onGoTap { if (self.onGo) self.onGo(); }

- (void)setSelectedAssets:(NSArray<PHAsset *> *)selectedAssets {
    NSArray<PHAsset *> *old = _selectedAssets ?: @[];
    NSArray<PHAsset *> *newA = selectedAssets ?: @[];
    _selectedAssets = [newA copy];

    self.titleLabel.text = [NSString stringWithFormat:@"Selected %ld Image", (long)newA.count];

    if (old.count == 0 && newA.count == 0) return;

    if (newA.count == old.count + 1) {
        BOOL prefixSame = YES;
        for (NSInteger i=0;i<old.count;i++) {
            if (![old[i].localIdentifier isEqualToString:newA[i].localIdentifier]) { prefixSame = NO; break; }
        }
        if (prefixSame) {
            NSIndexPath *ip = [NSIndexPath indexPathForItem:newA.count-1 inSection:0];
            [self.cv performBatchUpdates:^{
                [self.cv insertItemsAtIndexPaths:@[ip]];
            } completion:nil];
            return;
        }
    }

    // ✅ 只删除一个（找首个不一致的位置）
    if (old.count == newA.count + 1) {
        NSInteger rm = NSNotFound;
        NSInteger i=0,j=0;
        while (i<old.count && j<newA.count) {
            if ([old[i].localIdentifier isEqualToString:newA[j].localIdentifier]) { i++; j++; }
            else { rm = i; i++; } // skip old one
            if (rm != NSNotFound) break;
        }
        if (rm == NSNotFound) rm = old.count-1;
        // 校验尾部一致
        BOOL ok = YES;
        for (NSInteger k=rm;k<newA.count;k++) {
            if (![old[k+1].localIdentifier isEqualToString:newA[k].localIdentifier]) { ok = NO; break; }
        }
        if (ok) {
            NSIndexPath *ip = [NSIndexPath indexPathForItem:rm inSection:0];
            [self.cv performBatchUpdates:^{
                [self.cv deleteItemsAtIndexPaths:@[ip]];
            } completion:nil];
            return;
        }
    }

    // fallback：复杂变化就无动画 reload（减少闪）
    [UIView performWithoutAnimation:^{
        [self.cv reloadData];
        [self.cv layoutIfNeeded];
    }];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.selectedAssets.count;
}

- (void)collectionView:(UICollectionView *)collectionView
  didEndDisplayingCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:ASMiniCell.class]) return;
    ASMiniCell *c = (ASMiniCell *)cell;
    if (c.requestId != PHInvalidImageRequestID) {
        [self.cachingMgr cancelImageRequest:c.requestId];
        c.requestId = PHInvalidImageRequestID;
    }
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASMiniCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"mini" forIndexPath:indexPath];

    PHAsset *a = self.selectedAssets[indexPath.item];
    NSString *newId = a.localIdentifier ?: @"";

    if (cell.representedId.length && ![cell.representedId isEqualToString:newId]) {
        if (cell.requestId != PHInvalidImageRequestID) {
            [self.cachingMgr cancelImageRequest:cell.requestId];
            cell.requestId = PHInvalidImageRequestID;
        }
        cell.iv.image = nil;
    }
    cell.representedId = newId;

    [cell.delBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.delBtn addTarget:self action:@selector(onDelTap:) forControlEvents:UIControlEventTouchUpInside];

    if (!cell.iv.image && cell.requestId == PHInvalidImageRequestID) {
        PHImageRequestOptions *opt = [PHImageRequestOptions new];
        opt.networkAccessAllowed = YES;
        opt.resizeMode = PHImageRequestOptionsResizeModeFast;
        opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

        CGFloat px = 64.0 * UIScreen.mainScreen.scale * 2.0;
        CGSize target = CGSizeMake(px, px);

        __weak typeof(cell) weakCell = cell;
        cell.requestId =
        [self.cachingMgr requestImageForAsset:a
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFill
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (!result) return;
            if (![weakCell.representedId isEqualToString:newId]) return;

            BOOL cancelled = [info[PHImageCancelledKey] boolValue];
            if (cancelled) return;

            BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
            if (degraded && weakCell.iv.image) return;

            weakCell.iv.image = result;
            if (!degraded) weakCell.requestId = PHInvalidImageRequestID;
        }];
    }

    return cell;
}

- (void)onDelTap:(UIButton *)btn {
    CGPoint p = [btn convertPoint:CGPointMake(12, 12) toView:self.cv];
    NSIndexPath *ip = [self.cv indexPathForItemAtPoint:p];
    if (!ip) return;
    PHAsset *a = self.selectedAssets[ip.item];
    if (self.onRemove) self.onRemove(a);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(64, 64);
}

@end

#pragma mark - Pill Button (filter)

@interface ASImagePillButton : UIButton
@end

@implementation ASImagePillButton
- (instancetype)init {
    if (self = [super initWithFrame:CGRectZero]) {
        self.adjustsImageWhenHighlighted = NO;
        self.showsTouchWhenHighlighted = NO;
        self.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height * 0.5;
}
@end

#pragma mark - VC

@interface ImageCompressionMainViewController () <
UICollectionViewDelegate,
UICollectionViewDataSource,
UICollectionViewDataSourcePrefetching
>

@property (nonatomic, strong) NSObject *statsLock;
@property (nonatomic, assign) uint64_t statsKnownBytes;
@property (nonatomic, assign) NSInteger statsPending;
@property (nonatomic, assign) NSInteger statsFailed;

// UI
@property (nonatomic, strong) UIView *blueHeader;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) UILabel *headerTotal;
@property (nonatomic, strong) UILabel *headerSubtitle;

@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIScrollView *filterScroll;
@property (nonatomic, strong) UIStackView *filterStack;
@property (nonatomic, strong) NSArray<UIButton *> *filterButtons;
@property (nonatomic, assign) NSInteger filterIndex;

@property (nonatomic, strong) UICollectionView *collectionView;

// bottom bar
@property (nonatomic, strong) ASSelectedBar *selectedBar;
@property (nonatomic, strong) NSLayoutConstraint *selectedBarHiddenC;
@property (nonatomic, strong) NSLayoutConstraint *selectedBarShownC;
@property (nonatomic, strong) NSLayoutConstraint *selectedBarHeightC;
@property (nonatomic, assign) BOOL selectedBarVisible;

@property (nonatomic, strong) NSArray<PHAsset *> *allImages;
@property (nonatomic, strong) NSArray<PHAsset *> *displayImages;
@property (nonatomic, strong) NSArray<ASImgSizeSection *> *sections;
@property (nonatomic, strong) NSMutableArray<PHAsset *> *selectedAssets;

// caches
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sizeCache;
@property (nonatomic, strong) NSOperationQueue *sizeQueue;
@property (nonatomic, assign) BOOL didStartComputeAll;

@property (nonatomic, strong) PHCachingImageManager *cachingMgr;
@property (nonatomic, assign) CGSize thumbPixelSize;

@property (nonatomic, assign) NSInteger filterToken;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sizeMetaCache;
@property (nonatomic, assign) BOOL sizeCacheSaveScheduled;

@end

@implementation ImageCompressionMainViewController

#pragma mark - Preview selection bridge (Main <-> Preview)

- (NSIndexSet *)selectedIndexesForPreviewAssets:(NSArray<PHAsset *> *)previewAssets {
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    if (previewAssets.count == 0 || self.selectedAssets.count == 0) return set;

    NSMutableSet<NSString *> *selectedIds = [NSMutableSet setWithCapacity:self.selectedAssets.count];
    for (PHAsset *a in self.selectedAssets) {
        if (a.localIdentifier) [selectedIds addObject:a.localIdentifier];
    }

    [previewAssets enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier && [selectedIds containsObject:obj.localIdentifier]) {
            [set addIndex:idx];
        }
    }];
    return set;
}

- (void)applyPreviewSelectionFromAssets:(NSArray<PHAsset *> *)previewAssets selectedIndexes:(NSIndexSet *)selectedIndexes {
    NSMutableSet<NSString *> *scopeIds = [NSMutableSet setWithCapacity:previewAssets.count];
    for (PHAsset *a in previewAssets) if (a.localIdentifier) [scopeIds addObject:a.localIdentifier];

    NSMutableSet<NSString *> *newSelIds = [NSMutableSet set];
    [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx < previewAssets.count) {
            PHAsset *a = previewAssets[idx];
            if (a.localIdentifier) [newSelIds addObject:a.localIdentifier];
        }
    }];

    for (NSInteger i = (NSInteger)self.selectedAssets.count - 1; i >= 0; i--) {
        PHAsset *a = self.selectedAssets[i];
        NSString *aid = a.localIdentifier ?: @"";
        if ([scopeIds containsObject:aid] && ![newSelIds containsObject:aid]) {
            [self.selectedAssets removeObjectAtIndex:i];
        }
    }

    for (PHAsset *a in previewAssets) {
        if (self.selectedAssets.count >= 9) break;
        NSString *aid = a.localIdentifier ?: @"";
        if (![newSelIds containsObject:aid]) continue;

        BOOL already = NO;
        for (PHAsset *x in self.selectedAssets) {
            if ([x.localIdentifier ?: @"" isEqualToString:aid]) { already = YES; break; }
        }
        if (!already) [self.selectedAssets addObject:a];
    }

    self.selectedBar.selectedAssets = self.selectedAssets;
    [self showSelectedBar:(self.selectedAssets.count > 0) animated:NO];
    [self updateVisibleSelectionOnly];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
}

- (void)dealloc {
    [self.sizeQueue cancelAllOperations];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.statsLock = [NSObject new];
    self.sizeCache = [NSMutableDictionary dictionary];
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:ASImgSizeCachePath()];
    self.sizeMetaCache = [(disk ?: @{}) mutableCopy];
    self.selectedAssets = [NSMutableArray array];
    self.sections = @[];
    self.filterIndex = 0;

    self.sizeQueue = [NSOperationQueue new];
    self.sizeQueue.maxConcurrentOperationCount = 1;
    self.cachingMgr = [PHCachingImageManager new];

    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self setupHeaderAndCardUI];
    [self ensureAuthThenLoadFast];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeB = 0;
    if (@available(iOS 11.0,*)) safeB = self.view.safeAreaInsets.bottom;
    self.selectedBarHeightC.constant = 130.0 + safeB;

    [self updateThumbTargetSizeIfNeeded];
    [self updateBottomInsetsForSelectedBarAnimated:NO];
}

#pragma mark - UI

- (void)setupHeaderAndCardUI {
    CGFloat sideInset = 20;

    self.blueHeader = [UIView new];
    self.blueHeader.backgroundColor = ASBlue();
    self.blueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blueHeader];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];

    UIImage *backImg = [[UIImage imageNamed:@"ic_return_white"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];

    self.backBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;

    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;

    [self.blueHeader addSubview:self.backBtn];

    self.headerTitle = [UILabel new];
    self.headerTitle.text = @"Image Compressor";
    self.headerTitle.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    self.headerTitle.textColor = UIColor.whiteColor;
    self.headerTitle.textAlignment = NSTextAlignmentCenter;
    self.headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerTitle];

    self.headerTotal = [UILabel new];
    self.headerTotal.text = @"--";
    self.headerTotal.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
    self.headerTotal.textColor = UIColor.whiteColor;
    self.headerTotal.textAlignment = NSTextAlignmentCenter;
    self.headerTotal.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerTotal];

    self.headerSubtitle = [UILabel new];
    self.headerSubtitle.text = @"Total storage space saved by compressed photos --";
    self.headerSubtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.headerSubtitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.95];
    self.headerSubtitle.textAlignment = NSTextAlignmentCenter;
    self.headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerSubtitle];

    self.card = [UIView new];
    self.card.backgroundColor = UIColor.whiteColor;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = 16;
    self.card.layer.masksToBounds = YES;
    if (@available(iOS 11.0,*)) {
        self.card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    [self.view addSubview:self.card];

    self.filterScroll = [UIScrollView new];
    self.filterScroll.showsHorizontalScrollIndicator = NO;
    self.filterScroll.alwaysBounceHorizontal = YES;
    self.filterScroll.decelerationRate = UIScrollViewDecelerationRateFast;
    self.filterScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.filterScroll];

    UIButton *b0 = [self makeFilterButton:@"All" tag:0];
    UIButton *b1 = [self makeFilterButton:@"Today" tag:1];
    UIButton *b2 = [self makeFilterButton:@"This week" tag:2];
    UIButton *b3 = [self makeFilterButton:@"This month" tag:3];
    UIButton *b4 = [self makeFilterButton:@"Last month" tag:4];
    UIButton *b5 = [self makeFilterButton:@"Past 6 months" tag:5];
    self.filterButtons = @[b0,b1,b2,b3,b4,b5];

    self.filterStack = [[UIStackView alloc] initWithArrangedSubviews:self.filterButtons];
    self.filterStack.axis = UILayoutConstraintAxisHorizontal;
    self.filterStack.spacing = 12;
    self.filterStack.alignment = UIStackViewAlignmentCenter;
    self.filterStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterScroll addSubview:self.filterStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.filterScroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:20],
        [self.filterScroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.filterScroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],

        [self.filterStack.leadingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.leadingAnchor constant:20],
        [self.filterStack.trailingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.trailingAnchor constant:-20],
        [self.filterStack.topAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.topAnchor],
        [self.filterStack.bottomAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.bottomAnchor],

        [self.filterScroll.heightAnchor constraintEqualToAnchor:self.filterStack.heightAnchor],
    ]];

    UICollectionViewLayout *layout = [self buildLayout];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.prefetchDataSource = self;
    self.collectionView.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0,*)) self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    [self.collectionView registerClass:ASImgCell.class forCellWithReuseIdentifier:@"ASImgCell"];
    [self.collectionView registerClass:ASImgSectionHeader.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"ASImgSectionHeader"];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.collectionView];

    // bottom selected bar
    self.selectedBar = [ASSelectedBar new];
    self.selectedBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.selectedBar.onRemove = ^(PHAsset *a) { [weakSelf toggleSelectAsset:a forceDeselect:YES]; };
    self.selectedBar.onGo = ^{ [weakSelf goQuality]; };
    [self.view addSubview:self.selectedBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.blueHeader.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.blueHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.blueHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:6],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.blueHeader.safeAreaLayoutGuide.topAnchor constant:10],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.headerTitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTitle.centerYAnchor constraintEqualToAnchor:self.backBtn.centerYAnchor],

        [self.headerTotal.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTotal.topAnchor constraintEqualToAnchor:self.headerTitle.bottomAnchor constant:14],

        [self.headerSubtitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerSubtitle.topAnchor constraintEqualToAnchor:self.headerTotal.bottomAnchor constant:10],
        [self.headerSubtitle.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:sideInset],
        [self.headerSubtitle.trailingAnchor constraintEqualToAnchor:self.blueHeader.trailingAnchor constant:-sideInset],

        [self.card.topAnchor constraintEqualToAnchor:self.headerSubtitle.bottomAnchor constant:28],
        [self.blueHeader.bottomAnchor constraintEqualToAnchor:self.card.topAnchor constant:22],

        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.filterScroll.bottomAnchor constant:20],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],

        [self.selectedBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0],
        [self.selectedBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:0],
    ]];

    self.selectedBarHeightC = [self.selectedBar.heightAnchor constraintEqualToConstant:150];
    self.selectedBarHeightC.active = YES;

    self.selectedBarHiddenC = [self.selectedBar.topAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.selectedBarHiddenC.active = YES;

    self.selectedBarShownC = [self.selectedBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.selectedBarShownC.active = NO;

    [self updateFilterButtonStyles];
}

- (UIButton *)makeFilterButton:(NSString *)title tag:(NSInteger)tag {
    ASImagePillButton *b = [ASImagePillButton new];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    b.contentEdgeInsets = UIEdgeInsetsMake(7, 15, 7, 15);
    b.tag = tag;
    [b addTarget:self action:@selector(onFilterTap:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)updateFilterButtonStyles {
    for (UIButton *b in self.filterButtons) {
        BOOL selected = (b.tag == self.filterIndex);
        if (selected) {
            b.backgroundColor = ASBlue();
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        } else {
            b.backgroundColor = ASBlue10();
            [b setTitleColor:[UIColor colorWithWhite:0 alpha:0.9] forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Layout

- (UICollectionViewLayout *)buildLayout {
    if (@available(iOS 13.0, *)) {
        __weak typeof(self) weakSelf = self;

        UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment>  _Nonnull environment) {

            CGFloat containerW = environment.container.effectiveContentSize.width;

            CGFloat inter = 5.0;
            CGFloat leading = 20.0;

            CGFloat contentW = containerW - leading * 2.0;
            CGFloat itemSide = floor(contentW / 3.2);
            if (itemSide < 90) itemSide = 90;

            NSCollectionLayoutSize *itemSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemSide]
                                          heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemSide]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

            NSCollectionLayoutSize *groupSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemSide]
                                          heightDimension:[NSCollectionLayoutDimension absoluteDimension:(itemSide * 2 + inter)]];

            NSCollectionLayoutGroup *group =
            [NSCollectionLayoutGroup verticalGroupWithLayoutSize:groupSize subitem:item count:2];
            group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:inter];

            NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:group];
            sec.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
            sec.interGroupSpacing = inter;

            sec.contentInsets = NSDirectionalEdgeInsetsMake(0, leading, 0, leading);

            sec.supplementariesFollowContentInsets = NO;


            NSCollectionLayoutSize *headerSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                          heightDimension:[NSCollectionLayoutDimension absoluteDimension:40]];
            NSCollectionLayoutBoundarySupplementaryItem *header =
            [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                     elementKind:UICollectionElementKindSectionHeader
                                                                                      alignment:NSRectAlignmentTop];
            sec.boundarySupplementaryItems = @[header];

            CGFloat scale = UIScreen.mainScreen.scale;
            weakSelf.thumbPixelSize = CGSizeMake(itemSide * scale * 1.6, itemSide * scale * 1.6);

            return sec;
        }];

        UICollectionViewCompositionalLayoutConfiguration *config = [UICollectionViewCompositionalLayoutConfiguration new];
        config.interSectionSpacing = 18;
        layout.configuration = config;
        return layout;
    }

    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.scrollDirection = UICollectionViewScrollDirectionVertical;
    fl.minimumLineSpacing = 10;
    fl.minimumInteritemSpacing = 10;
    fl.itemSize = CGSizeMake(120, 120);
    return fl;
}

- (void)updateThumbTargetSizeIfNeeded {
    if (!CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero)) return;
    CGFloat scale = UIScreen.mainScreen.scale;
    self.thumbPixelSize = CGSizeMake(120 * scale, 120 * scale);
}

#pragma mark - Auth + Load (不卡 UI)

- (void)ensureAuthThenLoadFast {
    PHAuthorizationStatus st;
    if (@available(iOS 14.0,*)) st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    else st = [PHPhotoLibrary authorizationStatus];

    if (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited) {
        [self loadAssetsFast];
        return;
    }

    if (@available(iOS 14.0,*)) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self ensureAuthThenLoadFast]; });
        }];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self ensureAuthThenLoadFast]; });
        }];
    }
}

- (void)loadAssetsFast {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        PHFetchOptions *opt = [PHFetchOptions new];
        opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];

        opt.predicate = [NSPredicate predicateWithFormat:
                         @"(mediaType == %d) AND ((mediaSubtypes & %d) == 0)",
                         PHAssetMediaTypeImage,
                         PHAssetMediaSubtypePhotoLive];

        if (@available(iOS 9.0, *)) {
            opt.includeHiddenAssets = YES;
            opt.includeAssetSourceTypes =
                PHAssetSourceTypeUserLibrary |
                PHAssetSourceTypeCloudShared |
                PHAssetSourceTypeiTunesSynced;
        }

        PHFetchResult<PHAsset *> *result =
        [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:opt];

        NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:result.count];
        [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [arr addObject:obj];
        }];
        
        NSDictionary *metaSnap = nil;
        @synchronized (self.sizeMetaCache) { metaSnap = [self.sizeMetaCache copy]; }

        uint64_t known = 0;
        NSInteger pending = 0;
        NSMutableDictionary<NSString *, NSNumber *> *warm = [NSMutableDictionary dictionary];

        for (PHAsset *a in arr) {
            NSString *aid = a.localIdentifier ?: @"";
            NSDictionary *rec = metaSnap[aid];
            if (rec) {
                uint64_t s = [rec[@"s"] unsignedLongLongValue];
                NSTimeInterval cachedM = [rec[@"m"] doubleValue];
                NSTimeInterval curM = a.modificationDate ? a.modificationDate.timeIntervalSince1970 : 0;

                if (s > 0 && fabs(curM - cachedM) < 1.0) {
                    warm[aid] = @(s);
                    known += s;
                    continue;
                }
            }
            pending += 1;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allImages = [arr copy];

            @synchronized (self.sizeCache) {
                [self.sizeCache addEntriesFromDictionary:warm];
            }

            @synchronized (self.statsLock) {
                self.statsKnownBytes = known;
                self.statsPending = pending;
                self.statsFailed = 0;
            }

            [self refreshHeaderFromStats:YES];
            [self applyFilterIndex:self.filterIndex];
            [self startComputeAllSizesIfNeeded];
        });
    });
}


- (void)prewarmStatsFromDiskCache {
    uint64_t known = 0;
    NSInteger pending = 0;

    for (PHAsset *a in self.allImages) {
        NSString *aid = a.localIdentifier ?: @"";
        NSDictionary *rec = nil;
        @synchronized (self.sizeMetaCache) { rec = self.sizeMetaCache[aid]; }

        if (rec) {
            uint64_t s = [rec[@"s"] unsignedLongLongValue];
            NSTimeInterval cachedM = [rec[@"m"] doubleValue];
            NSTimeInterval curM = a.modificationDate ? a.modificationDate.timeIntervalSince1970 : 0;

            // modificationDate 基本能作为“是否变化”的版本号
            if (s > 0 && fabs(curM - cachedM) < 1.0) {
                @synchronized (self.sizeCache) { self.sizeCache[aid] = @(s); }
                known += s;
                continue;
            }
        }
        pending += 1;
    }

    @synchronized(self.statsLock) {
        self.statsKnownBytes = known;
        self.statsPending = pending;
        self.statsFailed = 0;
    }
}

- (void)scheduleSaveSizeCache {
    @synchronized (self) {
        if (self.sizeCacheSaveScheduled) return;
        self.sizeCacheSaveScheduled = YES;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *snap = nil;
        @synchronized (self.sizeMetaCache) { snap = [self.sizeMetaCache copy]; }
        [snap writeToFile:ASImgSizeCachePath() atomically:YES];

        @synchronized (self) { self.sizeCacheSaveScheduled = NO; }
    });
}

#pragma mark - Header (no flicker)

- (void)refreshHeaderFromStats:(BOOL)possiblyUnknown {
    uint64_t known = 0;
    NSInteger pending = 0;
    NSInteger failed = 0;
    @synchronized(self.statsLock) {
        known = self.statsKnownBytes;
        pending = self.statsPending;
        failed = self.statsFailed;
    }

    uint64_t saved = known / 2; // 固定 50%

    NSString *totalText = known > 0 ? ASHumanSizeShort(known) : @"--";
    if (possiblyUnknown && known > 0 && (pending > 0 || failed > 0)) totalText = [totalText stringByAppendingString:@"+"];

    NSString *savedText = saved > 0 ? ASHumanSizeShort(saved) : @"--";
    NSString *prefix = @"Total storage space saved by compressed photos ";
    NSString *full = [prefix stringByAppendingString:savedText];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full];
    [att addAttribute:NSForegroundColorAttributeName value:[[UIColor whiteColor] colorWithAlphaComponent:0.85] range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold] range:NSMakeRange(prefix.length, savedText.length)];
    [att addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:NSMakeRange(prefix.length, savedText.length)];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.headerTotal.text = totalText;
    self.headerSubtitle.attributedText = att;
    [CATransaction commit];
}

#pragma mark - File Size

- (uint64_t)cachedFileSizeForAsset:(PHAsset *)asset {
    NSNumber *n = nil;
    @synchronized (self.sizeCache) { n = self.sizeCache[asset.localIdentifier]; }
    return n ? n.unsignedLongLongValue : 0;
}

- (uint64_t)fileSizeForAsset:(PHAsset *)asset {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    PHAssetResource *target = nil;
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypePhoto || r.type == PHAssetResourceTypeFullSizePhoto) { target = r; break; }
    }
    if (!target) target = resources.firstObject;
    if (!target) return 0;

    NSNumber *n = nil;
    @try { n = [target valueForKey:@"fileSize"]; }
    @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

- (void)startComputeAllSizesIfNeeded {
    if (self.didStartComputeAll) return;
    self.didStartComputeAll = YES;

    __weak typeof(self) weakSelf = self;
    NSArray<PHAsset *> *assets = self.allImages ?: @[];

    NSMutableArray<PHAsset *> *missing = [NSMutableArray array];
    for (PHAsset *a in assets) {
        NSString *aid = a.localIdentifier ?: @"";
        NSNumber *n = nil;
        @synchronized (self.sizeCache) { n = self.sizeCache[aid]; }
        if (!n || n.unsignedLongLongValue == 0) [missing addObject:a];
    }

    if (missing.count == 0) {
        [self refreshHeaderFromStats:NO];
        // 可选：这里做一次分组刷新（只有一次，不会闪到肉眼）
        [self applyFilterIndex:self.filterIndex];
        return;
    }

    [self.sizeQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSInteger tick = 0;
            for (PHAsset *a in missing) {
                uint64_t size = [weakSelf fileSizeForAsset:a];

                NSString *aid = a.localIdentifier ?: @"";
                NSTimeInterval mod = a.modificationDate ? a.modificationDate.timeIntervalSince1970 : 0;

                @synchronized (weakSelf.sizeCache) {
                    weakSelf.sizeCache[aid] = @(size);
                }
                @synchronized (weakSelf.sizeMetaCache) {
                    weakSelf.sizeMetaCache[aid] = @{@"s": @(size), @"m": @(mod)};
                }

                @synchronized(weakSelf.statsLock) {
                    if (weakSelf.statsPending > 0) weakSelf.statsPending -= 1;
                    if (size > 0) weakSelf.statsKnownBytes += size;
                    else weakSelf.statsFailed += 1;
                }

                tick++;
                if (tick % 30 == 0) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [weakSelf refreshHeaderFromStats:YES];
                        [weakSelf updateVisiblePillsOnly];
                    }];
                    [weakSelf scheduleSaveSizeCache];
                }
            }

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [weakSelf refreshHeaderFromStats:NO];
                [weakSelf scheduleSaveSizeCache];
                [weakSelf applyFilterIndex:weakSelf.filterIndex];
            }];
        }
    }];
}

- (void)updateVisiblePillsOnly {
    NSArray<NSIndexPath *> *visible = self.collectionView.indexPathsForVisibleItems;
    for (NSIndexPath *ip in visible) {
        if (ip.section >= self.sections.count) continue;
        NSArray<PHAsset *> *arr = self.sections[ip.section].assets;
        if (ip.item >= arr.count) continue;

        PHAsset *a = arr[ip.item];
        ASImgCell *cell = (ASImgCell *)[self.collectionView cellForItemAtIndexPath:ip];
        if (![cell.representedAssetIdentifier isEqualToString:a.localIdentifier]) continue;

        uint64_t bytes = [self cachedFileSizeForAsset:a];
        NSString *txt = ASMBPill(bytes);
        if (![cell.pill.text isEqualToString:txt]) cell.pill.text = txt;
    }
}

#pragma mark - Filter (async,不卡 UI)

- (void)onFilterTap:(UIButton *)sender {
    self.filterIndex = sender.tag;
    [self updateFilterButtonStyles];
    [self applyFilterIndex:self.filterIndex];
}

- (void)applyFilterIndex:(NSInteger)idx {
    NSArray<PHAsset *> *base = self.allImages ?: @[];
    NSDate *now = [NSDate date];

    NSInteger token = ++self.filterToken;
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<PHAsset *> *filtered = [weakSelf filteredImagesByIndex:idx fromImages:base now:now];
        NSArray<ASImgSizeSection *> *secs = [weakSelf buildSectionsFromImages:filtered];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != weakSelf.filterToken) return;
            weakSelf.displayImages = filtered;
            weakSelf.sections = secs;
            [weakSelf.collectionView reloadData];
        });
    });
}

- (NSArray<PHAsset *> *)filteredImagesByIndex:(NSInteger)idx fromImages:(NSArray<PHAsset *> *)images now:(NSDate *)now {
    if (idx == 0) return images;

    NSDate *start = nil;
    NSCalendar *cal = [NSCalendar currentCalendar];
    cal.firstWeekday = 2;

    if (idx == 1) {
        start = [cal startOfDayForDate:now];
    } else if (idx == 2) {
        NSDate *weekStart = nil; NSTimeInterval interval = 0;
        [cal rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&weekStart interval:&interval forDate:now];
        start = weekStart ?: [cal startOfDayForDate:now];
    } else if (idx == 3) {
        NSDateComponents *c = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:now];
        c.day = 1;
        start = [cal dateFromComponents:c];
    } else if (idx == 4) {
        NSDateComponents *c = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:now];
        c.day = 1;
        NSDate *thisMonth = [cal dateFromComponents:c];
        start = [cal dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:thisMonth options:0];
    } else if (idx == 5) {
        start = [cal dateByAddingUnit:NSCalendarUnitMonth value:-6 toDate:now options:0];
    } else {
        return images;
    }

    NSMutableArray<PHAsset *> *out = [NSMutableArray array];
    for (PHAsset *a in images) {
        if (!a.creationDate) continue;
        if ([a.creationDate compare:start] != NSOrderedAscending) [out addObject:a];
    }
    return [out copy];
}

#pragma mark - Sections (>10MB / 5-10 / 1-5 / <1 & unknown)

- (NSArray<ASImgSizeSection *> *)buildSectionsFromImages:(NSArray<PHAsset *> *)imgs {
    NSMutableArray<PHAsset *> *g10 = [NSMutableArray array];
    NSMutableArray<PHAsset *> *g5  = [NSMutableArray array];
    NSMutableArray<PHAsset *> *g1  = [NSMutableArray array];
    NSMutableArray<PHAsset *> *g0  = [NSMutableArray array];

    for (PHAsset *a in imgs) {
        uint64_t s = [self cachedFileSizeForAsset:a];
        if (s == 0) { [g0 addObject:a]; continue; }

        double mb = (double)s / (1024.0 * 1024.0);
        if (mb > 10.0) [g10 addObject:a];
        else if (mb >= 5.0) [g5 addObject:a];
        else if (mb >= 1.0) [g1 addObject:a];
        else [g0 addObject:a];
    }

    NSMutableArray<ASImgSizeSection *> *secs = [NSMutableArray array];
    if (g10.count) { ASImgSizeSection *s=[ASImgSizeSection new]; s.title=@">10MB";     s.assets=g10; [secs addObject:s]; }
    if (g5.count)  { ASImgSizeSection *s=[ASImgSizeSection new]; s.title=@"5MB–10MB"; s.assets=g5;  [secs addObject:s]; }
    if (g1.count)  { ASImgSizeSection *s=[ASImgSizeSection new]; s.title=@"1MB–5MB";  s.assets=g1;  [secs addObject:s]; }
    if (g0.count)  { ASImgSizeSection *s=[ASImgSizeSection new]; s.title=@"<1MB";     s.assets=g0;  [secs addObject:s]; }
    return [secs copy];
}

#pragma mark - Bottom Selected Bar + Insets

- (void)toggleSelectAsset:(PHAsset *)asset forceDeselect:(BOOL)forceDeselect {
    if (!asset) return;

    NSInteger idx = [self.selectedAssets indexOfObject:asset];
    BOOL isSel = (idx != NSNotFound);

    if (isSel || forceDeselect) {
        if (isSel) [self.selectedAssets removeObjectAtIndex:idx];
    } else {
        if (self.selectedAssets.count >= 9) return;
        [self.selectedAssets addObject:asset];
    }

    self.selectedBar.selectedAssets = self.selectedAssets;
    [self showSelectedBar:(self.selectedAssets.count > 0) animated:YES];

    NSArray<NSIndexPath *> *visible = self.collectionView.indexPathsForVisibleItems;
    [self updateVisibleSelectionOnly];
}

- (void)updateVisibleSelectionOnly {
    NSArray<NSIndexPath *> *visible = self.collectionView.indexPathsForVisibleItems;
    for (NSIndexPath *ip in visible) {
        if (ip.section >= self.sections.count) continue;
        NSArray<PHAsset *> *arr = self.sections[ip.section].assets;
        if (ip.item >= arr.count) continue;

        PHAsset *a = arr[ip.item];
        ASImgCell *cell = (ASImgCell *)[self.collectionView cellForItemAtIndexPath:ip];
        if (!cell) continue;
        if (![cell.representedAssetIdentifier isEqualToString:a.localIdentifier]) continue;

        BOOL sel = [self.selectedAssets containsObject:a];
        [cell applySelectedUI:sel];
    }
}


- (void)showSelectedBar:(BOOL)show animated:(BOOL)animated {
    if (show == self.selectedBarVisible) return;
    self.selectedBarVisible = show;

    self.selectedBarHiddenC.active = !show;
    self.selectedBarShownC.active  = show;

    [self updateBottomInsetsForSelectedBarAnimated:animated];

    void(^blk)(void) = ^{ [self.view layoutIfNeeded]; };
    if (!animated) { blk(); return; }
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:blk completion:nil];
}

- (void)updateBottomInsetsForSelectedBarAnimated:(BOOL)animated {
    CGFloat safe = 0;
    if (@available(iOS 11.0,*)) safe = self.view.safeAreaInsets.bottom;

    CGFloat barH = self.selectedBarVisible ? self.selectedBarHeightC.constant : 0;
    CGFloat bottom = self.selectedBarVisible ? barH : safe;

    UIEdgeInsets insets = self.collectionView.contentInset;
    insets.bottom = bottom;

    UIEdgeInsets inds = self.collectionView.scrollIndicatorInsets;
    inds.bottom = bottom;

    void (^apply)(void) = ^{
        self.collectionView.contentInset = insets;
        self.collectionView.scrollIndicatorInsets = inds;
    };

    if (!animated) { apply(); return; }
    [UIView animateWithDuration:0.25 animations:apply];
}

#pragma mark - Actions

- (void)onBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)goQuality {
    if (self.selectedAssets.count == 0) return;
    ImageCompressionQualityViewController *vc =
    [[ImageCompressionQualityViewController alloc] initWithAssets:self.selectedAssets];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.sections[section].assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASImgCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASImgCell" forIndexPath:indexPath];

    PHAsset *asset = self.sections[indexPath.section].assets[indexPath.item];

    NSString *oldId = cell.representedAssetIdentifier;
    NSString *newId = asset.localIdentifier ?: @"";
    NSString *capturedId = [newId copy];

    // 如果 cell 复用到了新 asset：先 cancel 旧请求 + 清图
    if (oldId.length && ![oldId isEqualToString:newId]) {
        if (cell.requestId != PHInvalidImageRequestID) {
            [self.cachingMgr cancelImageRequest:cell.requestId];
            cell.requestId = PHInvalidImageRequestID;
        }
        cell.thumbView.image = nil;
    }
    cell.representedAssetIdentifier = newId;

    // selection + pill（不 reload）
    BOOL sel = [self.selectedAssets containsObject:asset];
    [cell applySelectedUI:sel];
    cell.pill.text = ASMBPill([self cachedFileSizeForAsset:asset]);

    // thumb：只有当当前没有图时才请求
    if (!cell.thumbView.image && cell.requestId == PHInvalidImageRequestID) {
        PHImageRequestOptions *opt = [PHImageRequestOptions new];
        opt.networkAccessAllowed = YES;
        opt.resizeMode = PHImageRequestOptionsResizeModeExact;
        opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

        CGSize target = CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero) ? CGSizeMake(512, 512) : self.thumbPixelSize;

        cell.requestId =
        [self.cachingMgr requestImageForAsset:asset
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFill
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (!result) return;
            if (![cell.representedAssetIdentifier isEqualToString:capturedId]) return;

            BOOL cancelled = [info[PHImageCancelledKey] boolValue];
            if (cancelled) return;

            BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
            if (degraded) {
                if (cell.thumbView.image) return;
            }

            cell.thumbView.image = result;

            if (!degraded) cell.requestId = PHInvalidImageRequestID;
        }];
    }

    // check tap
    cell.checkTapBtn.tag = (indexPath.section<<16) | indexPath.item;
    [cell.checkTapBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.checkTapBtn addTarget:self action:@selector(onCheckTap:) forControlEvents:UIControlEventTouchUpInside];

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
  didEndDisplayingCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![cell isKindOfClass:ASImgCell.class]) return;
    ASImgCell *c = (ASImgCell *)cell;

    if (c.requestId != PHInvalidImageRequestID) {
        [self.cachingMgr cancelImageRequest:c.requestId];
        c.requestId = PHInvalidImageRequestID;
    }
}

- (void)onCheckTap:(UIButton *)btn {
    NSInteger s = (btn.tag >> 16) & 0xFFFF;
    NSInteger i = btn.tag & 0xFFFF;
    if (s < 0 || s >= self.sections.count) return;
    NSArray *arr = self.sections[s].assets;
    if (i < 0 || i >= arr.count) return;
    [self toggleSelectAsset:arr[i] forceDeselect:NO];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= self.sections.count) return;
    NSArray<PHAsset *> *arr = self.sections[indexPath.section].assets ?: @[];
    if (indexPath.item >= arr.count) return;

    PHAsset *a = arr[indexPath.item];

    NSArray<PHAsset *> *previewAssets = @[a];
    NSIndexSet *preSel = [self selectedIndexesForPreviewAssets:previewAssets];

    ASMediaPreviewViewController *p =
    [[ASMediaPreviewViewController alloc] initWithAssets:previewAssets
                                           initialIndex:0
                                        selectedIndexes:preSel];

    p.bestIndex = 0;
    p.showsBestBadge = YES;

    __weak typeof(self) weakSelf = self;
    p.onBack = ^(NSArray<PHAsset *> *selectedAssets, NSIndexSet *selectedIndexes) {
        [weakSelf applyPreviewSelectionFromAssets:previewAssets selectedIndexes:selectedIndexes];
    };

    [self.navigationController pushViewController:p animated:YES];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        ASImgSectionHeader *h =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:@"ASImgSectionHeader"
                                                  forIndexPath:indexPath];
        h.titleLabel.text = self.sections[indexPath.section].title ?: @"";
        return h;
    }
    return [UICollectionReusableView new];
}

#pragma mark - Prefetch (reduce flicker)

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    if (CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero)) return;

    NSMutableArray<PHAsset *> *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *ip in indexPaths) {
        if (ip.section < self.sections.count) {
            NSArray *arr = self.sections[ip.section].assets;
            if (ip.item < arr.count) [assets addObject:arr[ip.item]];
        }
    }
    if (assets.count == 0) return;

    [self.cachingMgr startCachingImagesForAssets:assets
                                      targetSize:self.thumbPixelSize
                                     contentMode:PHImageContentModeAspectFill
                                         options:nil];
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    if (CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero)) return;

    NSMutableArray<PHAsset *> *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *ip in indexPaths) {
        if (ip.section < self.sections.count) {
            NSArray *arr = self.sections[ip.section].assets;
            if (ip.item < arr.count) [assets addObject:arr[ip.item]];
        }
    }
    if (assets.count == 0) return;

    [self.cachingMgr stopCachingImagesForAssets:assets
                                     targetSize:self.thumbPixelSize
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil];
}

@end
