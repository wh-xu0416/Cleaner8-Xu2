#import "VideoCompressionMainViewController.h"
#import "VideoCompressionQualityViewController.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

#pragma mark - Helpers

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
        _titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.blackColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}
@end

#pragma mark - Cell (Screenshot style)

@interface ASVideoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UIButton *savePill;
@property (nonatomic, copy) NSString *representedAssetIdentifier;
@end

@implementation ASVideoCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = 22;
        self.contentView.layer.masksToBounds = YES;

        _thumbView = [UIImageView new];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_thumbView];

        // ✅ play icon：直接显示资源图，无背景
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
        _savePill.layer.cornerRadius = 20;
        _savePill.layer.masksToBounds = YES;
        _savePill.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_savePill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _savePill.userInteractionEnabled = NO;
        _savePill.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 16);
        _savePill.translatesAutoresizingMaskIntoConstraints = NO;

        if (@available(iOS 13.0, *)) {
            UIImage *chev = [[UIImage systemImageNamed:@"chevron.right"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [_savePill setImage:chev forState:UIControlStateNormal];
            _savePill.tintColor = UIColor.whiteColor;
            _savePill.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
            _savePill.imageEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
        }

        [self.contentView addSubview:_savePill];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumbView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            // ✅ 图标直接贴左上（24x24），无底
            [_playIcon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_playIcon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
            [_playIcon.widthAnchor constraintEqualToConstant:24],
            [_playIcon.heightAnchor constraintEqualToConstant:24],

            [_savePill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_savePill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
            [_savePill.heightAnchor constraintEqualToConstant:40],
        ]];
    }
    return self;
}
@end


#pragma mark - VC

@interface VideoCompressionMainViewController () <
UICollectionViewDelegate,
UICollectionViewDataSource
>

// Header (blue)
@property (nonatomic, strong) UIView *blueHeader;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) UILabel *headerTotal;     // 8.91GB
@property (nonatomic, strong) UILabel *headerSubtitle;  // Total storage... 4.45GB

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
    // 永远胶囊：圆角=高度/2
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

    self.sizeCache = [NSMutableDictionary dictionary];
    self.sizeQueue = [[NSOperationQueue alloc] init];
    self.sizeQueue.maxConcurrentOperationCount = 2;

    self.filterIndex = 0;

    [self setupHeaderAndCardUI];

    [self loadAssetsFastThenComputeSizesInBackground];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateThumbTargetSizeIfNeeded];

    if (@available(iOS 11.0, *)) {
        CGFloat bottom = self.view.safeAreaInsets.bottom; // TabBar 高度
        UIEdgeInsets insets = self.collectionView.contentInset;
        insets.bottom = bottom; // 只留 safeArea，不多留“空白”
        self.collectionView.contentInset = insets;
        self.collectionView.scrollIndicatorInsets = insets;
    }
}

#pragma mark - UI (Header + Card)

- (void)setupHeaderAndCardUI {

    CGFloat sideInset = 20;

    // Blue header
    self.blueHeader = [UIView new];
    self.blueHeader.backgroundColor = ASBlue();
    self.blueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blueHeader];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    }
    self.backBtn.tintColor = UIColor.whiteColor;
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.backBtn];

    self.headerTitle = [UILabel new];
    self.headerTitle.text = @"Video Compression";
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
    self.headerSubtitle.text = @"Total storage space saved by compressed videos --";
    self.headerSubtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.headerSubtitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:1];
    self.headerSubtitle.textAlignment = NSTextAlignmentCenter;
    self.headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blueHeader addSubview:self.headerSubtitle];

    // White card (rounded top corners)
    self.card = [UIView new];
    self.card.backgroundColor = UIColor.whiteColor;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = 16;
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

    // ✅ 关键：让“按钮”不吞滑动手势（你之前 delaysContentTouches=NO 很容易导致滑不动）
    self.filterScroll.delaysContentTouches = YES;
    self.filterScroll.canCancelContentTouches = YES;

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
    self.filterStack.distribution = UIStackViewDistributionFill;
    self.filterStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterScroll addSubview:self.filterStack];

    [NSLayoutConstraint activateConstraints:@[
        // ✅ 筛选栏离白卡顶部 20
        [self.filterScroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:20],
        [self.filterScroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.filterScroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],

        // content
        [self.filterStack.leadingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.leadingAnchor constant:20],
        [self.filterStack.trailingAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.trailingAnchor constant:-20],
        [self.filterStack.topAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.topAnchor],
        [self.filterStack.bottomAnchor constraintEqualToAnchor:self.filterScroll.contentLayoutGuide.bottomAnchor],

        // ✅ 关键：scroll 的“高度”跟随 stack 的高度（按钮自适应高度）
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
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:16],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.blueHeader.safeAreaLayoutGuide.topAnchor constant:10],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.headerTitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTitle.centerYAnchor constraintEqualToAnchor:self.backBtn.centerYAnchor],

        [self.headerTotal.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerTotal.topAnchor constraintEqualToAnchor:self.headerTitle.bottomAnchor constant:18],

        [self.headerSubtitle.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.headerSubtitle.topAnchor constraintEqualToAnchor:self.headerTotal.bottomAnchor constant:10],
        [self.headerSubtitle.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:sideInset],
        [self.headerSubtitle.trailingAnchor constraintEqualToAnchor:self.blueHeader.trailingAnchor constant:-sideInset],

        // ✅ 白卡离上面文字 30
        [self.card.topAnchor constraintEqualToAnchor:self.headerSubtitle.bottomAnchor constant:30],

        // header 刚好到白卡顶部（保证白卡圆角“露出来”）
        [self.blueHeader.bottomAnchor constraintEqualToAnchor:self.card.topAnchor constant:22],

        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        // ✅ 底部不盖住列表：卡片到底用 safeArea（避免盖住底部导航/TabBar）
        [self.card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // ✅ 列表离筛选 20
        [self.collectionView.topAnchor constraintEqualToAnchor:self.filterScroll.bottomAnchor constant:20],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],
    ]];

    [self updateFilterButtonStyles];
}

- (UIButton *)makeFilterButton:(NSString *)title tag:(NSInteger)tag {
    ASPillButton *b = [ASPillButton new];
    [b setTitle:title forState:UIControlStateNormal];

    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];

    // ✅ 你要的边距：左右15 上下5
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
            b.backgroundColor = ASBlue10(); // ✅ 10% 透明蓝
            [b setTitleColor:[UIColor colorWithWhite:0 alpha:0.9] forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Layout

- (UICollectionViewLayout *)buildLayout {
    if (@available(iOS 13.0, *)) {

        CGFloat cardW = 150.0;
        CGFloat cardH = 200.0;

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

        // 卡片间距 10
        section.interGroupSpacing = 10;

        // 顺滑横滑（不分页）
        section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;

        // 卡片左边对齐 20（标题也跟随）
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, 20, 0, 0);
        section.supplementariesFollowContentInsets = YES;
        
        // header
        NSCollectionLayoutSize *headerSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:40]];
        NSCollectionLayoutBoundarySupplementaryItem *header =
        [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                 elementKind:UICollectionElementKindSectionHeader
                                                                                  alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];

        UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSection:section];

        UICollectionViewCompositionalLayoutConfiguration *config =
            [UICollectionViewCompositionalLayoutConfiguration new];
        config.interSectionSpacing = 20;
        layout.configuration = config;

        return layout;
    }

    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.scrollDirection = UICollectionViewScrollDirectionVertical;
    fl.minimumLineSpacing = 20;
    fl.itemSize = CGSizeMake(150, 200);
    return fl;
}

- (void)updateThumbTargetSizeIfNeeded {
    CGFloat cardW = 150.0;
    CGFloat cardH = 200.0;

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

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allVideos = [arr copy];
            [self applyFilterIndex:self.filterIndex];
            [self refreshHeaderStatsPossiblyUnknown:YES];

            [self computeSizesForAssetsIfNeeded:self.allVideos rebuildSectionsWhenFinished:YES];
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
    NSDate *now = [NSDate date];
    NSArray<PHAsset *> *base = self.allVideos ?: @[];
    self.displayVideos = [self filteredVideosByIndex:idx fromVideos:base now:now];

    [self rebuildSectionsFromDisplayVideos];
    [self.collectionView reloadData];
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
    // ✅ 顶部永远统计 allVideos，不跟筛选走
    NSArray<PHAsset *> *videos = self.allVideos ?: @[];

    uint64_t total = 0;
    NSInteger unknown = 0;

    for (PHAsset *a in videos) {
        NSNumber *n = nil;
        @synchronized (self.sizeCache) {
            n = self.sizeCache[a.localIdentifier];
        }
        if (!n) { unknown++; continue; }
        uint64_t s = n.unsignedLongLongValue;
        if (s == 0) { unknown++; continue; }
        total += s;
    }

    uint64_t saved = total / 2;

    self.headerTotal.text = (total > 0) ? ASHumanSizeShort(total) : @"--";

    NSString *savedText = (saved > 0) ? ASHumanSizeShort(saved) : @"--";
    NSString *prefix = @"Total storage space saved by compressed videos ";
    NSString *full = [prefix stringByAppendingString:savedText];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full];
    [att addAttribute:NSForegroundColorAttributeName value:[[UIColor whiteColor] colorWithAlphaComponent:0.85] range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] range:NSMakeRange(0, full.length)];
    [att addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]
              range:NSMakeRange(prefix.length, savedText.length)];
    [att addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor
              range:NSMakeRange(prefix.length, savedText.length)];
    self.headerSubtitle.attributedText = att;

    if (possiblyUnknown && unknown > 0 && total > 0) {
        self.headerTotal.text = [self.headerTotal.text stringByAppendingString:@"+"];
    }
}

#pragma mark - Size Compute

- (void)computeSizesForAssetsIfNeeded:(NSArray<PHAsset *> *)assets rebuildSectionsWhenFinished:(BOOL)rebuild {
    if (assets.count == 0) return;

    if (rebuild && self.isComputingAllSizes) return;
    if (rebuild) self.isComputingAllSizes = YES;

    NSObject *lock = [NSObject new];
    __block NSInteger done = 0;
    __block NSInteger scheduled = 0;

    for (PHAsset *a in assets) {
        BOOL hasCached = NO;
        @synchronized (self.sizeCache) {
            hasCached = (self.sizeCache[a.localIdentifier] != nil);
        }
        if (hasCached) continue;

        scheduled += 1;

        __weak typeof(self) weakSelf = self;
        [self.sizeQueue addOperationWithBlock:^{
            uint64_t size = [weakSelf fileSizeForAsset:a];

            @synchronized (weakSelf.sizeCache) {
                weakSelf.sizeCache[a.localIdentifier] = @(size);
            }

            NSInteger c = 0;
            @synchronized (lock) { done += 1; c = done; }

            if (c % 60 == 0 || c == scheduled) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [weakSelf refreshHeaderStatsPossiblyUnknown:YES];
                    if (rebuild) {
                        [weakSelf rebuildSectionsFromDisplayVideos];
                        [weakSelf.collectionView reloadData];
                    } else {
                        NSArray<NSIndexPath *> *visible = weakSelf.collectionView.indexPathsForVisibleItems;
                        if (visible.count > 0) [weakSelf.collectionView reloadItemsAtIndexPaths:visible];
                    }
                }];
            }
        }];
    }

    if (scheduled == 0) {
        if (rebuild) self.isComputingAllSizes = NO;
        [self refreshHeaderStatsPossiblyUnknown:NO];
        if (rebuild) {
            [self rebuildSectionsFromDisplayVideos];
            [self.collectionView reloadData];
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.sizeQueue addOperationWithBlock:^{
        for (int i = 0; i < 200; i++) { [NSThread sleepForTimeInterval:0.05]; }
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (rebuild) weakSelf.isComputingAllSizes = NO;
            [weakSelf refreshHeaderStatsPossiblyUnknown:NO];
            if (rebuild) {
                [weakSelf rebuildSectionsFromDisplayVideos];
                [weakSelf.collectionView reloadData];
            }
        }];
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
    // 截图样式：Save 234MB
    if (bytes == 0) return @"Save --MB";
    uint64_t saveBytes = bytes / 2;
    double mb = (double)saveBytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"Save %.0fMB", mb];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.sections[section].assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASVideoCell" forIndexPath:indexPath];

    PHAsset *asset = self.sections[indexPath.section].assets[indexPath.item];
    cell.representedAssetIdentifier = asset.localIdentifier;

    uint64_t bytes = [self cachedFileSizeForAsset:asset];
    NSString *t = [self savePillTextForBytes:bytes];
    [UIView performWithoutAnimation:^{
        [cell.savePill setTitle:t forState:UIControlStateNormal];
        [cell.savePill layoutIfNeeded];
    }];

    cell.thumbView.image = nil;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    CGSize target = CGSizeEqualToSize(self.thumbPixelSize, CGSizeZero) ? CGSizeMake(1000, 1000) : self.thumbPixelSize;

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if (![cell.representedAssetIdentifier isEqualToString:asset.localIdentifier]) return;
        cell.thumbView.image = result;
    }];

    return cell;
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
