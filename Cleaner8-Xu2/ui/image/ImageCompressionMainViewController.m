#import "ImageCompressionMainViewController.h"
#import "ImageCompressionQualityViewController.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

#pragma mark - Helpers (static)

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

            [_checkBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_checkBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_checkBtn.widthAnchor constraintEqualToConstant:26],
            [_checkBtn.heightAnchor constraintEqualToConstant:26],

            // bigger tappable area
            [_checkTapBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_checkTapBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_checkTapBtn.widthAnchor constraintEqualToConstant:56],
            [_checkTapBtn.heightAnchor constraintEqualToConstant:56],

            // pill bottom-right
            [_pill.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
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
    self.representedAssetIdentifier = nil;
    self.thumbView.image = nil;
    self.pill.text = @"--";
    [self applySelectedUI:NO];
}

- (void)applySelectedUI:(BOOL)sel {
    if (@available(iOS 13.0, *)) {
        UIImage *img = sel ? [UIImage systemImageNamed:@"checkmark.circle.fill"]
                           : [UIImage systemImageNamed:@"circle"];
        [self.checkBtn setImage:img forState:UIControlStateNormal];
        self.checkBtn.tintColor = sel ? ASBlue() : [UIColor colorWithWhite:0 alpha:0.25];
    }
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
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 16;
        if (@available(iOS 11.0,*)) {
            self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
        self.layer.masksToBounds = YES;

        self.cachingMgr = [PHCachingImageManager new];

        self.titleLabel = [UILabel new];
        self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = UIColor.blackColor;

        UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
        lay.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        lay.minimumLineSpacing = 10;
        lay.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);

        self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
        self.cv.backgroundColor = UIColor.clearColor;
        self.cv.showsHorizontalScrollIndicator = NO;
        self.cv.dataSource = self;
        self.cv.delegate = self;
        [self.cv registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"mini"];
        self.cv.clipsToBounds = NO;
        self.cv.layer.masksToBounds = NO;
        
        self.goBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.goBtn.tintColor = ASBlue();
        self.goBtn.backgroundColor = ASBlue10();
        self.goBtn.layer.cornerRadius = 16;
        self.goBtn.layer.masksToBounds = YES;
        if (@available(iOS 13.0,*)) [self.goBtn setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
        [self.goBtn addTarget:self action:@selector(onGoTap) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:self.titleLabel];
        [self addSubview:self.cv];
        [self addSubview:self.goBtn];

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.cv.translatesAutoresizingMaskIntoConstraints = NO;
        self.goBtn.translatesAutoresizingMaskIntoConstraints = NO;

        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],

            [self.goBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.goBtn.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.goBtn.widthAnchor constraintEqualToConstant:52],
            [self.goBtn.heightAnchor constraintEqualToConstant:34],

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
    _selectedAssets = selectedAssets ?: @[];
    self.titleLabel.text = [NSString stringWithFormat:@"Selected %ld Image", (long)_selectedAssets.count];
    [self.cv reloadData];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.selectedAssets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"mini" forIndexPath:indexPath];

    cell.clipsToBounds = NO;
    cell.contentView.clipsToBounds = NO;
    cell.layer.masksToBounds = NO;
    cell.contentView.layer.masksToBounds = NO;

    UIImageView *iv = (UIImageView *)[cell.contentView viewWithTag:100];
    UIButton *x = (UIButton *)[cell.contentView viewWithTag:101];

    if (!iv) {
        iv = [UIImageView new];
        iv.tag = 100;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.layer.cornerRadius = 12;
        iv.layer.masksToBounds = YES;
        iv.translatesAutoresizingMaskIntoConstraints = NO;

        x = [UIButton buttonWithType:UIButtonTypeSystem];
        x.tag = 101;
        x.tintColor = UIColor.whiteColor;
        x.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        x.layer.cornerRadius = 12;
        x.layer.masksToBounds = YES;
        if (@available(iOS 13.0,*)) [x setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        x.translatesAutoresizingMaskIntoConstraints = NO;
        [x addTarget:self action:@selector(onX:) forControlEvents:UIControlEventTouchUpInside];

        [cell.contentView addSubview:iv];
        [cell.contentView addSubview:x];

        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [iv.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [iv.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [iv.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],

            [x.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:-6],
            [x.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:6],
            [x.widthAnchor constraintEqualToConstant:24],
            [x.heightAnchor constraintEqualToConstant:24],
        ]];
    }

    iv.image = nil;

    PHAsset *a = self.selectedAssets[indexPath.item];

    NSString *assetId = a.localIdentifier ?: @"";
    cell.accessibilityIdentifier = assetId;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    CGFloat px = 64.0 * UIScreen.mainScreen.scale * 2.0; // 2.0 倍冗余，缩放更清晰
    CGSize target = CGSizeMake(px, px);

    [self.cachingMgr requestImageForAsset:a
                               targetSize:target
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {

        if (!result) return;

        if (![cell.accessibilityIdentifier isEqualToString:assetId]) return;

        iv.image = result;
    }];

    return cell;
}

- (void)onX:(UIButton *)btn {
    UIView *v = btn.superview;
    while (v && ![v isKindOfClass:UICollectionViewCell.class]) v = v.superview;
    UICollectionViewCell *cell = (UICollectionViewCell *)v;
    NSIndexPath *ip = [self.cv indexPathForCell:cell];
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

// stats (no flicker, no full scan)
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

// Data
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

// async token
@property (nonatomic, assign) NSInteger filterToken;

@end

@implementation ImageCompressionMainViewController

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
    self.selectedAssets = [NSMutableArray array];
    self.sections = @[];
    self.filterIndex = 0;

    self.sizeQueue = [NSOperationQueue new];
    self.sizeQueue.maxConcurrentOperationCount = 1; // ✅更稳，不抢 UI
    self.cachingMgr = [PHCachingImageManager new];

    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self setupHeaderAndCardUI];
    [self ensureAuthThenLoadFast];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // ✅ bottom bar height = base(118) + safeBottom, background贴底不留缝
    CGFloat safeB = 0;
    if (@available(iOS 11.0,*)) safeB = self.view.safeAreaInsets.bottom;
    self.selectedBarHeightC.constant = 118.0 + safeB;

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

    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0,*)) [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    self.backBtn.tintColor = UIColor.whiteColor;
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
    self.headerTotal.font = [UIFont systemFontOfSize:44 weight:UIFontWeightSemibold];
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

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:16],
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

    // height updated in viewDidLayoutSubviews
    self.selectedBarHeightC = [self.selectedBar.heightAnchor constraintEqualToConstant:150];
    self.selectedBarHeightC.active = YES;

    // hidden / shown
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

#pragma mark - Layout (width = screen/3.5, square, 2 rows, gap 10, horizontal per section)

- (UICollectionViewLayout *)buildLayout {
    if (@available(iOS 13.0, *)) {
        __weak typeof(self) weakSelf = self;

        UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment>  _Nonnull environment) {

            CGFloat containerW = environment.container.effectiveContentSize.width;

            CGFloat inter = 10.0;
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

            // ✅ item 左右和 header title 对齐（20）
            sec.contentInsets = NSDirectionalEdgeInsetsMake(0, leading, 0, leading);

            // ✅ 关键：header 不跟随 contentInsets（否则会 20 + 20 = 40）
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
        PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:opt];

        NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:result.count];
        [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [arr addObject:obj];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allImages = [arr copy];

            @synchronized(self.statsLock) {
                self.statsKnownBytes = 0;
                self.statsPending = self.allImages.count;
                self.statsFailed = 0;
            }
            [self refreshHeaderFromStats:YES];

            [self applyFilterIndex:self.filterIndex];

            // ✅ 后台开始统计所有 size（不会卡 UI）
            [self startComputeAllSizesIfNeeded];
        });
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
    [CATransaction setDisableActions:YES]; // ✅ 不闪
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

    [self.sizeQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSInteger tick = 0;
            for (PHAsset *a in assets) {
                if (weakSelf.sizeQueue.isSuspended || weakSelf.sizeQueue.operationCount == 0) {
                    // ignore
                }

                uint64_t size = [weakSelf fileSizeForAsset:a];

                @synchronized (weakSelf.sizeCache) {
                    if (!weakSelf.sizeCache[a.localIdentifier]) {
                        weakSelf.sizeCache[a.localIdentifier] = @(size);
                    }
                }

                @synchronized(weakSelf.statsLock) {
                    if (weakSelf.statsPending > 0) weakSelf.statsPending -= 1;
                    if (size > 0) weakSelf.statsKnownBytes += size;
                    else weakSelf.statsFailed += 1;
                }

                tick += 1;
                if (tick % 120 == 0) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [weakSelf refreshHeaderFromStats:YES];

                        // ✅ 只刷新可见 item（避免闪、避免大 reload）
                        NSArray<NSIndexPath *> *visible = weakSelf.collectionView.indexPathsForVisibleItems;
                        if (visible.count) [weakSelf.collectionView reloadItemsAtIndexPaths:visible];
                    }];
                }
            }

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [weakSelf refreshHeaderFromStats:NO];
                // ✅ 统计结束后，重新按 size 分组（后台做，不卡）
                [weakSelf applyFilterIndex:weakSelf.filterIndex];
            }];
        }
    }];
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

    // ✅ 只刷新可见，避免闪
    NSArray<NSIndexPath *> *visible = self.collectionView.indexPathsForVisibleItems;
    if (visible.count) [self.collectionView reloadItemsAtIndexPaths:visible];
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
    cell.representedAssetIdentifier = asset.localIdentifier;

    BOOL sel = [self.selectedAssets containsObject:asset];
    [cell applySelectedUI:sel];

    uint64_t bytes = [self cachedFileSizeForAsset:asset];
    cell.pill.text = ASMBPill(bytes);

    // thumb
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    CGSize target = CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero) ? CGSizeMake(600, 600) : self.thumbPixelSize;

    [self.cachingMgr requestImageForAsset:asset
                               targetSize:target
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if (![cell.representedAssetIdentifier isEqualToString:asset.localIdentifier]) return;
        cell.thumbView.image = result;
    }];

    // check tap
    cell.checkTapBtn.tag = (indexPath.section<<16) | indexPath.item;
    [cell.checkTapBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.checkTapBtn addTarget:self action:@selector(onCheckTap:) forControlEvents:UIControlEventTouchUpInside];

    return cell;
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
    PHAsset *a = self.sections[indexPath.section].assets[indexPath.item];
    ASImagePreviewVC *p = [[ASImagePreviewVC alloc] initWithAsset:a];
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:p animated:YES completion:nil];
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
