#import "VideoCompressionMainViewController.h"
#import "VideoCompressionQualityViewController.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

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
    return MIN(1.0, MIN(SWScaleX(), SWScaleY()));
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

#pragma mark - Helpers
static NSString * const kASVidSizeCachePlist = @"as_vid_size_cache_v2.plist";

static inline NSString *ASVidSizeCachePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:kASVidSizeCachePlist];
}

static inline UIColor *ASBlue(void) {
    // #024DFFFF
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0];
}
static inline UIColor *ASBlue10(void) {
    return [ASBlue() colorWithAlphaComponent:0.10];
}

static const uint64_t MB = 1024ULL * 1024ULL;

static NSString *ASHumanSizeShort(uint64_t bytes) {
    double b = (double)bytes;
    double mb = b / (1024.0 * 1024.0);
    double gb = mb / 1024.0;
    if (gb >= 1.0) return [NSString stringWithFormat:@"%.2fGB", gb];
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.0fMB", mb];
    if (b >= 1024.0) return [NSString stringWithFormat:@"%.1fKB", b/1024.0];
    return [NSString stringWithFormat:@"%.0fB", b];
}

static NSString *ASDurationText(NSTimeInterval duration) {
    NSInteger d = (NSInteger)llround(duration);
    NSInteger m = d / 60, s = d % 60;
    if (m >= 60) { NSInteger h = m/60; m%=60; return [NSString stringWithFormat:@"%ld:%02ld:%02ld",(long)h,(long)m,(long)s]; }
    return [NSString stringWithFormat:@"%ld:%02ld",(long)m,(long)s];
}

#pragma mark - Section Model

@interface ASVideoSizeSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@end
@implementation ASVideoSizeSection @end

#pragma mark - Header (Section)

@interface ASVideoSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation ASVideoSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [UILabel new];
        _titleLabel.font = ASFontS(22, UIFontWeightSemibold);
        _titleLabel.textColor = UIColor.blackColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-AS(10)],
        ]];
    }
    return self;
}
@end

#pragma mark - Cell (Screenshot style)

@interface ASVideoCell : UICollectionViewCell
@property (nonatomic, assign) PHImageRequestID requestId;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UIButton *savePill;
@property (nonatomic, copy) NSString *representedAssetIdentifier;
@end

@implementation ASVideoCell

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat r = self.savePill.bounds.size.height * 0.5;
    self.savePill.layer.cornerRadius = r;
    self.savePill.clipsToBounds = YES;

    if (@available(iOS 13.0, *)) {
        self.savePill.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = AS(22);
        self.contentView.layer.masksToBounds = YES;

        _thumbView = [UIImageView new];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_thumbView];

        _playIcon = [UIImageView new];
        _playIcon.contentMode = UIViewContentModeScaleAspectFit;
        _playIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _playIcon.image = [[UIImage imageNamed:@"ic_play"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.contentView addSubview:_playIcon];

        // save pill (bottom center)
        _savePill = [UIButton buttonWithType:UIButtonTypeCustom];
        _savePill.adjustsImageWhenHighlighted = NO;
        _savePill.showsTouchWhenHighlighted = NO;
        _savePill.backgroundColor = ASBlue();

        _savePill.layer.cornerRadius = AS(26);
        _savePill.layer.masksToBounds = YES;

        _savePill.titleLabel.font = ASFontS(12, UIFontWeightMedium);
        [_savePill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

        _savePill.userInteractionEnabled = NO;

        _savePill.contentEdgeInsets = ASEdgeInsets(8, 10, 8, 12);

        [_savePill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_savePill setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_savePill.titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _savePill.translatesAutoresizingMaskIntoConstraints = NO;

        UIImage *todo = [[UIImage imageNamed:@"ic_more"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [_savePill setImage:todo forState:UIControlStateNormal];
        _savePill.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        _savePill.imageEdgeInsets = UIEdgeInsetsMake(0, AS(6), 0, -AS(6));

        [self.contentView addSubview:_savePill];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumbView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_playIcon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(10)],
            [_playIcon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AS(10)],
            [_playIcon.widthAnchor constraintEqualToConstant:AS(24)],
            [_playIcon.heightAnchor constraintEqualToConstant:AS(24)],

            [_savePill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_savePill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-AS(14)],
            [_savePill.heightAnchor constraintEqualToConstant:AS(36)],
        ]];

        self.requestId = PHInvalidImageRequestID;
        self.thumbView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedAssetIdentifier = nil;
    self.requestId = PHInvalidImageRequestID;
    self.thumbView.image = nil;
}

@end

#pragma mark - VC

@interface VideoCompressionMainViewController () <
UICollectionViewDelegate,
UICollectionViewDataSource,
UICollectionViewDataSourcePrefetching
>
@property (nonatomic, strong) NSObject *statsLock;
@property (nonatomic, assign) uint64_t statsKnownBytes;
@property (nonatomic, assign) NSInteger statsPending;
@property (nonatomic, assign) NSInteger statsFailed;

// caches
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sizeMetaCache; // {id: {s:bytes, m:ts}}
@property (nonatomic, assign) BOOL sizeCacheSaveScheduled;

@property (nonatomic, assign) BOOL didStartComputeAll;
@property (nonatomic, strong) PHCachingImageManager *cachingMgr;

@property (nonatomic, assign) NSInteger filterToken;

// Header (blue)
@property (nonatomic, strong) UIView *blueHeader;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) UILabel *headerTotal;
@property (nonatomic, strong) UILabel *headerSubtitle;

// White Card Container
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *filterStack;
@property (nonatomic, strong) NSArray<UIButton *> *filterButtons;

@property (nonatomic, strong) UICollectionView *collectionView;

// Data
@property (nonatomic, strong) NSArray<PHAsset *> *allVideos;
@property (nonatomic, strong) NSArray<PHAsset *> *displayVideos;
@property (nonatomic, strong) NSArray<ASVideoSizeSection *> *sections;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sizeCache;
@property (nonatomic, strong) NSOperationQueue *sizeQueue;
@property (nonatomic) CGSize thumbPixelSize;
@property (nonatomic) BOOL isComputingAllSizes;

@property (nonatomic, strong) UIScrollView *filterScroll;
@property (nonatomic) NSInteger filterIndex; // 0..5

@end

@interface ASPillButton : UIButton
@end

@implementation ASPillButton
- (instancetype)init {
    if (self = [super initWithFrame:CGRectZero]) {
        self.adjustsImageWhenHighlighted = NO;
        self.showsTouchWhenHighlighted = NO;
        self.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
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

@implementation VideoCompressionMainViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
}

- (void)dealloc {
    [self.sizeQueue cancelAllOperations];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    self.statsLock = [NSObject new];

    self.sizeCache = [NSMutableDictionary dictionary];

    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:ASVidSizeCachePath()];
    self.sizeMetaCache = [(disk ?: @{}) mutableCopy];

    self.sizeQueue = [NSOperationQueue new];
    self.sizeQueue.maxConcurrentOperationCount = 1;

    self.cachingMgr = [PHCachingImageManager new];

    self.filterIndex = 0;

    [self setupHeaderAndCardUI];

    self.collectionView.prefetchDataSource = self;

    [self loadAssetsFastThenComputeSizesInBackground];
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
        [snap writeToFile:ASVidSizeCachePath() atomically:YES];

        @synchronized (self) { self.sizeCacheSaveScheduled = NO; }
    });
}

- (void)as_cancelCellRequestIfNeeded:(ASVideoCell *)cell {
    if (!cell) return;
    if (cell.requestId != PHInvalidImageRequestID) {
        [self.cachingMgr cancelImageRequest:cell.requestId];
        cell.requestId = PHInvalidImageRequestID;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateThumbTargetSizeIfNeeded];

    if (@available(iOS 11.0, *)) {
        CGFloat bottom = self.view.safeAreaInsets.bottom;
        UIEdgeInsets insets = self.collectionView.contentInset;
        insets.bottom = bottom;
        self.collectionView.contentInset = insets;
        self.collectionView.scrollIndicatorInsets = insets;
    }
}

#pragma mark - UI (Header + Card)

- (void)setupHeaderAndCardUI {

    CGFloat sideInset = AS(20);

    // Blue header
    self.blueHeader = [UIView new];
    self.blueHeader.backgroundColor = ASBlue();
    self.blueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blueHeader];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];

    UIImage *backImg = [[UIImage imageNamed:@"ic_return_white"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];

    self.backBtn.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;

    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;

    [self.blueHeader addSubview:self.backBtn];

    self.headerTitle = [UILabel new];
    self.headerTitle.text = NSLocalizedString(@"Video Compression",nil);
    self.headerTitle.font = ASFontS(24, UIFontWeightSemibold);
    self.headerTitle.textColor = UIColor.whiteColor;
    self.headerTitle.textAlignment = NSTextAlignmentCenter;
    self.headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerTitle];

    self.headerTotal = [UILabel new];
    self.headerTotal.text = @"--";
    self.headerTotal.font = ASFontS(34, UIFontWeightSemibold);
    self.headerTotal.textColor = UIColor.whiteColor;
    self.headerTotal.textAlignment = NSTextAlignmentCenter;
    self.headerTotal.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerTotal];

    self.headerSubtitle = [UILabel new];
    self.headerSubtitle.text = NSLocalizedString(@"Total storage space saved by compressed videos --",nil);
    self.headerSubtitle.font = ASFontS(12, UIFontWeightRegular);
    self.headerSubtitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:1];
    self.headerSubtitle.textAlignment = NSTextAlignmentCenter;
    self.headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerSubtitle];

    // White card (rounded top corners)
    self.card = [UIView new];
    self.card.backgroundColor = UIColor.whiteColor;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = AS(16);
    self.card.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        self.card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    [self.view addSubview:self.card];

    // Filter pills (scroll)
    self.filterScroll = [UIScrollView new];
    self.filterScroll.showsHorizontalScrollIndicator = NO;
    self.filterScroll.alwaysBounceHorizontal = YES;
    self.filterScroll.bounces = YES;
    self.filterScroll.decelerationRate = UIScrollViewDecelerationRateFast;

    self.filterScroll.delaysContentTouches = YES;
    self.filterScroll.canCancelContentTouches = YES;

    self.filterScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.filterScroll];

    UIButton *b0 = [self makeFilterButton:NSLocalizedString(@"All",nil) tag:0];
    UIButton *b1 = [self makeFilterButton:NSLocalizedString(@"Today",nil) tag:1];
    UIButton *b2 = [self makeFilterButton:NSLocalizedString(@"This week",nil) tag:2];
    UIButton *b3 = [self makeFilterButton:NSLocalizedString(@"This month",nil) tag:3];
    UIButton *b4 = [self makeFilterButton:NSLocalizedString(@"Last month",nil) tag:4];
    UIButton *b5 = [self makeFilterButton:NSLocalizedString(@"Past 6 months",nil) tag:5];
    self.filterButtons = @[b0,b1,b2,b3,b4,b5];

    self.filterStack = [[UIStackView alloc] initWithArrangedSubviews:self.filterButtons];
    self.filterStack.axis = UILayoutConstraintAxisHorizontal;
    self.filterStack.spacing = AS(12);
    self.filterStack.alignment = UIStackViewAlignmentCenter;
    self.filterStack.distribution = UIStackViewDistributionFill;
    self.filterStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterScroll addSubview:self.filterStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.filterScroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:AS(20)],
        [self.filterScroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.filterScroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],

        // content
        [self.filterStack.leadingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.leadingAnchor constant:AS(20)],
        [self.filterStack.trailingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.trailingAnchor constant:-AS(20)],
        [self.filterStack.topAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.topAnchor],
        [self.filterStack.bottomAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.bottomAnchor],

        [self.filterScroll.heightAnchor constraintEqualToAnchor:self.filterStack.heightAnchor],
    ]];

    // Collection
    UICollectionViewLayout *layout = [self buildLayout];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.showsVerticalScrollIndicator = NO;

    if (@available(iOS 11.0, *)) {
        self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [self.collectionView registerClass:[ASVideoCell class] forCellWithReuseIdentifier:@"ASVideoCell"];
    [self.collectionView registerClass:[ASVideoSectionHeader class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"ASVideoSectionHeader"];

    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.blueHeader.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.blueHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.blueHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        // back
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:AS(6)],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.blueHeader.safeAreaLayoutGuide.topAnchor constant:AS(10)],
        [self.backBtn.widthAnchor constraintEqualToConstant:AS(44)],
        [self.backBtn.heightAnchor constraintEqualToConstant:AS(44)],

        [self.headerTitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTitle.centerYAnchor constraintEqualToAnchor:self.backBtn.centerYAnchor],

        [self.headerTotal.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTotal.topAnchor constraintEqualToAnchor:self.headerTitle.bottomAnchor constant:AS(18)],

        [self.headerSubtitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerSubtitle.topAnchor constraintEqualToAnchor:self.headerTotal.bottomAnchor constant:AS(10)],
        [self.headerSubtitle.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:sideInset],
        [self.headerSubtitle.trailingAnchor constraintEqualToAnchor:self.blueHeader.trailingAnchor constant:-sideInset],

        [self.card.topAnchor constraintEqualToAnchor:self.headerSubtitle.bottomAnchor constant:AS(30)],

        [self.blueHeader.bottomAnchor constraintEqualToAnchor:self.card.topAnchor constant:AS(22)],

        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.filterScroll.bottomAnchor constant:AS(20)],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],
    ]];

    [self updateFilterButtonStyles];
}

- (UIButton *)makeFilterButton:(NSString *)title tag:(NSInteger)tag {
    ASPillButton *b = [ASPillButton new];
    [b setTitle:title forState:UIControlStateNormal];

    b.titleLabel.font = ASFontS(17, UIFontWeightRegular);
    b.contentEdgeInsets = ASEdgeInsets(7, 15, 7, 15);

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

        CGFloat cardW = AS(150.0);
        CGFloat cardH = AS(200.0);

        NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                      heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

        NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:cardW]
                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:cardH]];
        NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];

        section.interGroupSpacing = AS(10);

        section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;

        section.contentInsets = NSDirectionalEdgeInsetsMake(0, AS(20), 0, 0);
        section.supplementariesFollowContentInsets = YES;

        // header
        NSCollectionLayoutSize *headerSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:AS(40)]];
        NSCollectionLayoutBoundarySupplementaryItem *header =
        [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                 elementKind:UICollectionElementKindSectionHeader
                                                                                  alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];

        UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSection:section];

        UICollectionViewCompositionalLayoutConfiguration *config =
            [UICollectionViewCompositionalLayoutConfiguration new];
        config.interSectionSpacing = AS(20);
        layout.configuration = config;

        return layout;
    }

    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.scrollDirection = UICollectionViewScrollDirectionVertical;
    fl.minimumLineSpacing = AS(20);
    fl.itemSize = CGSizeMake(AS(150), AS(200));
    return fl;
}

- (void)updateThumbTargetSizeIfNeeded {
    CGFloat cardW = AS(150.0);
    CGFloat cardH = AS(200.0);

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize px = CGSizeMake(cardW * scale * 1.8, cardH * scale * 1.8);

    if (!CGSizeEqualToSize(self.thumbPixelSize, px)) {
        self.thumbPixelSize = px;
    }
}

#pragma mark - Data Loading

- (void)loadAssetsFastThenComputeSizesInBackground {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        PHFetchOptions *opt = [PHFetchOptions new];
        opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:opt];

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
            self.allVideos = [arr copy];

            @synchronized (self.sizeCache) {
                [self.sizeCache addEntriesFromDictionary:warm];
            }

            @synchronized (self.statsLock) {
                self.statsKnownBytes = known;
                self.statsPending = pending;
                self.statsFailed = 0;
            }

            [self refreshHeaderStatsPossiblyUnknown:YES];
            [self applyFilterIndex:self.filterIndex];      // 先用缓存分组/展示
            [self startComputeAllSizesIfNeeded];           // 后台补算缺失的
        });
    });
}

#pragma mark - Filter

- (void)onFilterTap:(UIButton *)sender {
    self.filterIndex = sender.tag;
    [self updateFilterButtonStyles];

    // 筛选数据 & 刷新列表
    [self applyFilterIndex:self.filterIndex];
}

- (void)applyFilterIndex:(NSInteger)idx {
    NSArray<PHAsset *> *base = self.allVideos ?: @[];
    NSDate *now = [NSDate date];

    NSInteger token = ++self.filterToken;
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<PHAsset *> *filtered = [weakSelf filteredVideosByIndex:idx fromVideos:base now:now];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != weakSelf.filterToken) return;

            weakSelf.displayVideos = filtered;
            [weakSelf rebuildSectionsFromDisplayVideos];
            [weakSelf.collectionView reloadData];
        });
    });
}

- (NSArray<PHAsset *> *)filteredVideosByIndex:(NSInteger)idx
                                   fromVideos:(NSArray<PHAsset *> *)videos
                                          now:(NSDate *)now {
    if (idx == 0) return videos;

    NSDate *start = nil;
    switch (idx) {
        case 1: start = [self startOfDayForDate:now]; break;
        case 2: start = [self startOfWeekForDate:now]; break;
        case 3: start = [self startOfMonthForDate:now]; break;
        case 4: start = [self startOfLastMonthForDate:now]; break;
        case 5: start = [self startOfPastSixMonthsForDate:now]; break;
        default: return videos;
    }

    NSMutableArray<PHAsset *> *out = [NSMutableArray array];
    for (PHAsset *a in videos) {
        if (!a.creationDate) continue;
        if ([a.creationDate compare:start] != NSOrderedAscending) {
            [out addObject:a];
        }
    }
    return [out copy];
}

- (NSDate *)startOfLastMonthForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *delta = [NSDateComponents new];
    delta.month = -1;
    NSDate *d = [cal dateByAddingComponents:delta toDate:date options:0];
    return [self startOfMonthForDate:d];
}

- (NSDate *)startOfPastSixMonthsForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *delta = [NSDateComponents new];
    delta.month = -6;
    NSDate *d = [cal dateByAddingComponents:delta toDate:date options:0];
    return [self startOfMonthForDate:d];
}

#pragma mark - Build Sections

- (void)rebuildSectionsFromDisplayVideos {
    NSArray<PHAsset *> *videos = self.displayVideos ?: @[];

    NSMutableArray<PHAsset *> *g1 = [NSMutableArray array]; // > 500MB
    NSMutableArray<PHAsset *> *g2 = [NSMutableArray array]; // 200-500
    NSMutableArray<PHAsset *> *g3 = [NSMutableArray array]; // 50-200
    NSMutableArray<PHAsset *> *g4 = [NSMutableArray array]; // < 50 (含未知)

    for (PHAsset *a in videos) {
        uint64_t s = [self cachedFileSizeForAsset:a];
        if (s == 0) { [g4 addObject:a]; continue; }

        if (s > 500ULL * MB)      [g1 addObject:a];
        else if (s > 200ULL * MB) [g2 addObject:a];
        else if (s > 50ULL * MB)  [g3 addObject:a];
        else                      [g4 addObject:a];
    }

    NSMutableArray<ASVideoSizeSection *> *secs = [NSMutableArray array];

    if (g1.count > 0) { ASVideoSizeSection *s = [ASVideoSizeSection new]; s.title = @">500MB";         s.assets = g1; [secs addObject:s]; }
    if (g2.count > 0) { ASVideoSizeSection *s = [ASVideoSizeSection new]; s.title = @"200MB–500MB";     s.assets = g2; [secs addObject:s]; }
    if (g3.count > 0) { ASVideoSizeSection *s = [ASVideoSizeSection new]; s.title = @"50MB–200MB";      s.assets = g3; [secs addObject:s]; }
    if (g4.count > 0) { ASVideoSizeSection *s = [ASVideoSizeSection new]; s.title = @"<50MB";           s.assets = g4; [secs addObject:s]; }

    self.sections = [secs copy];
}

#pragma mark - Header Stats (Top Blue)

- (void)refreshHeaderStatsPossiblyUnknown:(BOOL)possiblyUnknown {
    uint64_t known = 0;
    NSInteger pending = 0;
    NSInteger failed = 0;
    @synchronized (self.statsLock) {
        known = self.statsKnownBytes;
        pending = self.statsPending;
        failed = self.statsFailed;
    }

    uint64_t saved = known / 2;

    NSString *totalText = known > 0 ? ASHumanSizeShort(known) : @"--";
    if (possiblyUnknown && known > 0 && (pending > 0 || failed > 0)) {
        totalText = [totalText stringByAppendingString:@"+"];
    }

    NSString *savedText = saved > 0 ? ASHumanSizeShort(saved) : @"--";
    NSString *prefix = NSLocalizedString(@"Total storage space saved by compressed videos ",nil);
    NSString *full = [prefix stringByAppendingString:savedText];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full];
    [att addAttribute:NSForegroundColorAttributeName value:[[UIColor whiteColor] colorWithAlphaComponent:0.85] range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:ASFontS(12, UIFontWeightRegular) range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:ASFontS(12, UIFontWeightSemibold)
              range:NSMakeRange(prefix.length, savedText.length)];
    [att addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor
              range:NSMakeRange(prefix.length, savedText.length)];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.headerTotal.text = totalText;
    self.headerSubtitle.attributedText = att;
    [CATransaction commit];
}

- (void)startComputeAllSizesIfNeeded {
    if (self.didStartComputeAll) return;
    self.didStartComputeAll = YES;

    __weak typeof(self) weakSelf = self;
    NSArray<PHAsset *> *assets = self.allVideos ?: @[];

    NSMutableArray<PHAsset *> *missing = [NSMutableArray array];
    for (PHAsset *a in assets) {
        NSNumber *n = nil;
        @synchronized (weakSelf.sizeCache) { n = weakSelf.sizeCache[a.localIdentifier]; }
        if (!n || n.unsignedLongLongValue == 0) [missing addObject:a];
    }

    if (missing.count == 0) {
        [self refreshHeaderStatsPossiblyUnknown:NO];
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

                @synchronized (weakSelf.statsLock) {
                    if (weakSelf.statsPending > 0) weakSelf.statsPending -= 1;
                    if (size > 0) weakSelf.statsKnownBytes += size;
                    else weakSelf.statsFailed += 1;
                }

                tick++;
                if (tick % 60 == 0) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [weakSelf refreshHeaderStatsPossiblyUnknown:YES];
                        [weakSelf updateVisibleSavePillsOnly];
                    }];
                    [weakSelf scheduleSaveSizeCache];
                }
            }

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [weakSelf refreshHeaderStatsPossiblyUnknown:NO];
                [weakSelf scheduleSaveSizeCache];
                [weakSelf applyFilterIndex:weakSelf.filterIndex];
            }];
        }
    }];
}

- (void)updateVisibleSavePillsOnly {

    NSArray<NSIndexPath *> *visible = self.collectionView.indexPathsForVisibleItems;
    for (NSIndexPath *ip in visible) {
        if (ip.section >= self.sections.count) continue;
        NSArray<PHAsset *> *arr = self.sections[ip.section].assets;
        if (ip.item >= arr.count) continue;

        PHAsset *a = arr[ip.item];
        ASVideoCell *cell = (ASVideoCell *)[self.collectionView cellForItemAtIndexPath:ip];
        if (!cell) continue;
        if (![cell.representedAssetIdentifier isEqualToString:a.localIdentifier]) continue;

        uint64_t bytes = [self cachedFileSizeForAsset:a];
        NSString *t = [self savePillTextForBytes:bytes];
        NSString *old = [cell.savePill titleForState:UIControlStateNormal] ?: @"";
        if ([old isEqualToString:t]) continue;

        [UIView performWithoutAnimation:^{
            [cell.savePill setTitle:t forState:UIControlStateNormal];
            [cell.savePill layoutIfNeeded];
        }];
    }
}

#pragma mark - Size Compute

- (void)computeSizesForAssetsIfNeeded:(NSArray<PHAsset *> *)assets rebuildSectionsWhenFinished:(BOOL)rebuild {
    if (assets.count == 0) return;

    // 只计算缺失的
    NSMutableArray<PHAsset *> *missing = [NSMutableArray array];
    for (PHAsset *a in assets) {
        BOOL hasCached = NO;
        @synchronized (self.sizeCache) {
            hasCached = (self.sizeCache[a.localIdentifier] != nil);
        }
        if (!hasCached) [missing addObject:a];
    }

    if (missing.count == 0) {
        [self refreshHeaderStatsPossiblyUnknown:NO];
        if (rebuild) {
            [self rebuildSectionsFromDisplayVideos];
            [self.collectionView reloadData];
        } else {
            [self updateVisibleSavePillsOnly];
        }
        return;
    }

    __weak typeof(self) weakSelf = self;

    [self.sizeQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSInteger tick = 0;

            for (PHAsset *a in missing) {
                uint64_t size = [weakSelf fileSizeForAsset:a];

                @synchronized (weakSelf.sizeCache) {
                    weakSelf.sizeCache[a.localIdentifier] = @(size);
                }

                tick++;
                //  中途别 reload：只更新 header + 可见 pill（减少抖动/闪）
                if (tick % 60 == 0) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [weakSelf refreshHeaderStatsPossiblyUnknown:YES];
                        [weakSelf updateVisibleSavePillsOnly];
                    }];
                }
            }

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [weakSelf refreshHeaderStatsPossiblyUnknown:NO];

                if (rebuild) {
                    //  最终只重建一次 section + reload 一次
                    [weakSelf rebuildSectionsFromDisplayVideos];
                    [weakSelf.collectionView reloadData];
                } else {
                    [weakSelf updateVisibleSavePillsOnly];
                }
            }];
        }
    }];
}

#pragma mark - Size Helpers

- (uint64_t)cachedFileSizeForAsset:(PHAsset *)asset {
    NSNumber *n = nil;
    @synchronized (self.sizeCache) { n = self.sizeCache[asset.localIdentifier]; }
    return n ? n.unsignedLongLongValue : 0;
}

- (uint64_t)fileSizeForAsset:(PHAsset *)asset {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    PHAssetResource *target = nil;
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypeVideo || r.type == PHAssetResourceTypePairedVideo) {
            target = r; break;
        }
    }
    if (!target) target = resources.firstObject;
    if (!target) return 0;

    NSNumber *n = nil;
    @try { n = [target valueForKey:@"fileSize"]; }
    @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

- (NSString *)savePillTextForBytes:(uint64_t)bytes {
    if (bytes == 0) return NSLocalizedString(@"Save --MB",nil);
    uint64_t saveBytes = bytes / 2;
    double mb = (double)saveBytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:NSLocalizedString(@"Save %.0fMB",nil), mb];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.sections[section].assets.count;
}

- (void)collectionView:(UICollectionView *)collectionView
  didEndDisplayingCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![cell isKindOfClass:ASVideoCell.class]) return;
    ASVideoCell *c = (ASVideoCell *)cell;
    [self as_cancelCellRequestIfNeeded:c];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASVideoCell" forIndexPath:indexPath];

    PHAsset *asset = self.sections[indexPath.section].assets[indexPath.item];
    NSString *newId = asset.localIdentifier ?: @"";
    NSString *capturedId = [newId copy];

    if (cell.representedAssetIdentifier.length && ![cell.representedAssetIdentifier isEqualToString:newId]) {
        [self as_cancelCellRequestIfNeeded:cell];
        cell.thumbView.image = nil;
    }
    cell.representedAssetIdentifier = newId;

    uint64_t bytes = [self cachedFileSizeForAsset:asset];
    NSString *t = [self savePillTextForBytes:bytes];
    NSString *oldT = [cell.savePill titleForState:UIControlStateNormal] ?: @"";
    if (![oldT isEqualToString:t]) {
        [UIView performWithoutAnimation:^{
            [cell.savePill setTitle:t forState:UIControlStateNormal];
            [cell.savePill layoutIfNeeded];
        }];
    }

    if (!cell.thumbView.image && cell.requestId == PHInvalidImageRequestID) {

        PHImageRequestOptions *opt = [PHImageRequestOptions new];
        opt.networkAccessAllowed = YES;
        opt.resizeMode = PHImageRequestOptionsResizeModeExact;
        opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

        CGSize target = CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero) ? CGSizeMake(1000, 1000) : self.thumbPixelSize;

        __weak typeof(cell) weakCell = cell;
        cell.requestId =
        [self.cachingMgr requestImageForAsset:asset
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFill
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {

            if (!result) return;
            if (![weakCell.representedAssetIdentifier isEqualToString:capturedId]) return;

            BOOL cancelled = [info[PHImageCancelledKey] boolValue];
            if (cancelled) return;

            BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];

            if (degraded && weakCell.thumbView.image) return;

            weakCell.thumbView.image = result;

            if (!degraded) weakCell.requestId = PHInvalidImageRequestID;
        }];
    }

    return cell;
}

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

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    PHAsset *asset = self.sections[indexPath.section].assets[indexPath.item];
    VideoCompressionQualityViewController *vc =
    [[VideoCompressionQualityViewController alloc] initWithAssets:@[asset]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        ASVideoSectionHeader *h =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:@"ASVideoSectionHeader"
                                                  forIndexPath:indexPath];
        h.titleLabel.text = self.sections[indexPath.section].title ?: @"";
        return h;
    }
    return [UICollectionReusableView new];
}

#pragma mark - Actions

- (void)onBack {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Date Helpers

- (NSDate *)startOfDayForDate:(NSDate *)date {
    return [[NSCalendar currentCalendar] startOfDayForDate:date];
}

- (NSDate *)startOfWeekForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    cal.firstWeekday = 2;
    NSDate *start = nil;
    NSTimeInterval interval = 0;
    if ([cal rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:&interval forDate:date]) {
        return start;
    }
    return [self startOfDayForDate:date];
}

- (NSDate *)startOfMonthForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:date];
    c.day = 1;
    return [cal dateFromComponents:c];
}

@end
