#import "VideoCompressionMainViewController.h"
#import "VideoCompressionQualityViewController.h"
#import "ASCustomNavBar.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

#pragma mark - Section Model

@interface ASVideoSizeSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@end
@implementation ASVideoSizeSection @end

#pragma mark - Header

@interface ASVideoSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation ASVideoSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.blackColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}
@end

#pragma mark - Cell

@interface ASVideoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIView *bottomMask;
@property (nonatomic, strong) UILabel *sizeLabel;      // e.g. 320 MB
@property (nonatomic, strong) UILabel *saveLabel;      // e.g. Save 160 MB
@property (nonatomic, strong) UILabel *durationLabel;  // e.g. 02:13
@property (nonatomic, copy) NSString *representedAssetIdentifier;
@end

@implementation ASVideoCell
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

        _bottomMask = [UIView new];
        _bottomMask.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        _bottomMask.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_bottomMask];

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = UIColor.whiteColor;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _saveLabel = [UILabel new];
        _saveLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _saveLabel.textColor = UIColor.whiteColor;
        _saveLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _durationLabel = [UILabel new];
        _durationLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _durationLabel.textColor = UIColor.whiteColor;
        _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [_bottomMask addSubview:_sizeLabel];
        [_bottomMask addSubview:_saveLabel];
        [_bottomMask addSubview:_durationLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumbView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_bottomMask.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_bottomMask.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_bottomMask.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_bottomMask.heightAnchor constraintEqualToConstant:48],

            [_sizeLabel.leadingAnchor constraintEqualToAnchor:_bottomMask.leadingAnchor constant:10],
            [_sizeLabel.topAnchor constraintEqualToAnchor:_bottomMask.topAnchor constant:6],

            [_saveLabel.leadingAnchor constraintEqualToAnchor:_bottomMask.leadingAnchor constant:10],
            [_saveLabel.bottomAnchor constraintEqualToAnchor:_bottomMask.bottomAnchor constant:-6],

            [_durationLabel.trailingAnchor constraintEqualToAnchor:_bottomMask.trailingAnchor constant:-10],
            [_durationLabel.centerYAnchor constraintEqualToAnchor:_bottomMask.centerYAnchor],
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

@property (nonatomic, strong) ASCustomNavBar *customNavBar;
@property (nonatomic, strong) UILabel *totalSpaceLabel;         // 当前筛选范围内总视频空间
@property (nonatomic, strong) UILabel *spaceSavedLabel;         // 当前筛选范围内预计节省(50%)
@property (nonatomic, strong) UISegmentedControl *filterSegmentedControl;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) NSArray<PHAsset *> *allVideos;        // 全量（不变）
@property (nonatomic, strong) NSArray<PHAsset *> *displayVideos;    // 当前筛选
@property (nonatomic, strong) NSArray<ASVideoSizeSection *> *sections;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sizeCache; // localId -> bytes (0=未知/取不到)
@property (nonatomic, strong) NSOperationQueue *sizeQueue;

@property (nonatomic) CGSize thumbPixelSize;  // 缩略图清晰度用
@property (nonatomic) BOOL isComputingAllSizes;

@end

@implementation VideoCompressionMainViewController

static const uint64_t MB = 1024ULL * 1024ULL;

#pragma mark - Lifecycle

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

    [self setupNavBar];
    [self setupUI];

    // 外部已保证权限，这里直接加载
    [self loadAssetsFastThenComputeSizesInBackground];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateThumbTargetSizeIfNeeded];
}

#pragma mark - UI

- (void)setupNavBar {
    self.customNavBar = [[ASCustomNavBar alloc] initWithTitle:@"Video Compressor"];
    __weak typeof(self) weakSelf = self;
    self.customNavBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.view addSubview:self.customNavBar];

    self.customNavBar.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.customNavBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.customNavBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.customNavBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.customNavBar.heightAnchor constraintEqualToConstant:56],
    ]];
}

- (void)setupUI {
    self.totalSpaceLabel = [self createLabel:@"Total Video Space: --"];
    self.spaceSavedLabel = [self createLabel:@"Estimated Saved (50%): --"];

    self.filterSegmentedControl =
    [[UISegmentedControl alloc] initWithItems:@[@"All", @"Today", @"This Week", @"This Month", @"Last Month", @"Past 6 Months"]];
    self.filterSegmentedControl.selectedSegmentIndex = 0;
    [self.filterSegmentedControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.totalSpaceLabel,
        self.spaceSavedLabel,
        self.filterSegmentedControl
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.customNavBar.bottomAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    UICollectionViewLayout *layout = [self buildLayout];

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.whiteColor;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;

    [self.collectionView registerClass:[ASVideoCell class] forCellWithReuseIdentifier:@"ASVideoCell"];
    [self.collectionView registerClass:[ASVideoSectionHeader class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"ASVideoSectionHeader"];

    [self.view addSubview:self.collectionView];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];
}

- (UILabel *)createLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    l.textColor = UIColor.blackColor;
    return l;
}

- (UICollectionViewLayout *)buildLayout {
    if (@available(iOS 13.0, *)) {

        // 每屏 3 个
        NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:(1.0/3.0)]
                                      heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];

        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        item.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 10);

        CGFloat itemHeight = 160;
        NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];

        NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:3];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging;
        section.contentInsets = NSDirectionalEdgeInsetsMake(8, 0, 24, 0);

        // header
        NSCollectionLayoutSize *headerSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                      heightDimension:[NSCollectionLayoutDimension absoluteDimension:32]];

        NSCollectionLayoutBoundarySupplementaryItem *header =
        [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                 elementKind:UICollectionElementKindSectionHeader
                                                                                  alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[header];

        return [[UICollectionViewCompositionalLayout alloc] initWithSection:section];
    }

    // iOS12 fallback（如果你最低 >= iOS13 可删）
    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.scrollDirection = UICollectionViewScrollDirectionVertical;
    fl.minimumLineSpacing = 12;
    fl.itemSize = CGSizeMake(100, 160);
    return fl;
}

- (void)updateThumbTargetSizeIfNeeded {
    CGFloat w = self.collectionView.bounds.size.width;
    if (w <= 0) return;

    CGFloat itemW = floor((w - 20) / 3.0);
    CGFloat itemH = 160;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize px = CGSizeMake(itemW * scale * 1.8, itemH * scale * 1.8); // 更清晰一点

    if (!CGSizeEqualToSize(self.thumbPixelSize, px)) {
        self.thumbPixelSize = px;
    }
}

#pragma mark - Data Loading (默认最新排序)

- (void)loadAssetsFastThenComputeSizesInBackground {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        PHFetchOptions *opt = [PHFetchOptions new];
        // ✅ 默认按最新日期排序
        opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];

        PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:opt];

        NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:result.count];
        [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [arr addObject:obj];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allVideos = [arr copy];

            [self applyFilterIndex:self.filterSegmentedControl.selectedSegmentIndex];
            [self refreshTopStatsWithPossiblyUnknown:YES];

            // 后台计算 size，最终会刷新分组
            [self computeSizesForAssetsIfNeeded:self.allVideos rebuildSectionsWhenFinished:YES];
        });
    });
}

#pragma mark - Size Compute

- (void)computeSizesForAssetsIfNeeded:(NSArray<PHAsset *> *)assets rebuildSectionsWhenFinished:(BOOL)rebuild {
    if (assets.count == 0) return;

    // 防止重复启动全量计算
    if (rebuild && self.isComputingAllSizes) {
        return;
    }
    if (rebuild) {
        self.isComputingAllSizes = YES;
    }

    NSObject *lock = [NSObject new];
    __block NSInteger done = 0;
    __block NSInteger scheduled = 0;

    // 只对“没缓存过”的 asset 计算
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
            @synchronized (lock) {
                done += 1;
                c = done;
            }

            // 每 60 个更新一次 UI（避免太频繁）
            if (c % 60 == 0 || c == scheduled) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [weakSelf refreshTopStatsWithPossiblyUnknown:YES];

                    if (rebuild) {
                        [weakSelf rebuildSectionsFromDisplayVideos];
                        [weakSelf.collectionView reloadData];   // 关键：让 50-200 / 200-500 / >500 及时出现
                    } else {
                        NSArray<NSIndexPath *> *visible = weakSelf.collectionView.indexPathsForVisibleItems;
                        if (visible.count > 0) [weakSelf.collectionView reloadItemsAtIndexPaths:visible];
                    }
                }];
            }
        }];
    }

    // 如果这次没有任何要算的，直接收尾
    if (scheduled == 0) {
        if (rebuild) self.isComputingAllSizes = NO;
        [self refreshTopStatsWithPossiblyUnknown:NO];
        if (rebuild) {
            [self rebuildSectionsFromDisplayVideos];
            [self.collectionView reloadData];
        }
        return;
    }

    // 收尾：等队列都跑一段后，在主线程最终重建分组（保证分组正确）
    __weak typeof(self) weakSelf = self;
    [self.sizeQueue addOperationWithBlock:^{
        // 等待本次 scheduled 的计算大概率完成（简化：轮询缓存数量也行，这里用一个轻量等待）
        // 更稳做法：用依赖链/dispatch_group；这里保持简单但足够用
        for (int i = 0; i < 200; i++) {
            [NSThread sleepForTimeInterval:0.05];
        }
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (rebuild) weakSelf.isComputingAllSizes = NO;
            [weakSelf refreshTopStatsWithPossiblyUnknown:NO];
            if (rebuild) {
                [weakSelf rebuildSectionsFromDisplayVideos];
                [weakSelf.collectionView reloadData];
            }
        }];
    }];
}

#pragma mark - Filter

- (void)filterChanged:(UISegmentedControl *)sender {
    [self applyFilterIndex:sender.selectedSegmentIndex];

    // 切到更小范围：优先把当前 display 的 size 算出来，算完重分组
    [self computeSizesForAssetsIfNeeded:self.displayVideos rebuildSectionsWhenFinished:YES];
}

- (void)applyFilterIndex:(NSInteger)idx {
    NSDate *now = [NSDate date];
    NSArray<PHAsset *> *base = self.allVideos ?: @[];
    self.displayVideos = [self filteredVideosByIndex:idx fromVideos:base now:now];

    [self rebuildSectionsFromDisplayVideos];
    [self.collectionView reloadData];

    [self refreshTopStatsWithPossiblyUnknown:YES];
}

- (NSArray<PHAsset *> *)filteredVideosByIndex:(NSInteger)idx fromVideos:(NSArray<PHAsset *> *)videos now:(NSDate *)now {
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

#pragma mark - Build Sections (4 groups & hide empty)

- (void)rebuildSectionsFromDisplayVideos {
    NSArray<PHAsset *> *videos = self.displayVideos ?: @[];

    NSMutableArray<PHAsset *> *g1 = [NSMutableArray array]; // > 500MB
    NSMutableArray<PHAsset *> *g2 = [NSMutableArray array]; // 200-500
    NSMutableArray<PHAsset *> *g3 = [NSMutableArray array]; // 50-200
    NSMutableArray<PHAsset *> *g4 = [NSMutableArray array]; // < 50 (含未知)

    for (PHAsset *a in videos) {
        uint64_t s = [self cachedFileSizeForAsset:a];
        // 未知 size 先放到 <50MB 组，等后台算完会重分组
        if (s == 0) {
            [g4 addObject:a];
            continue;
        }

        if (s > 500ULL * MB) {
            [g1 addObject:a];
        } else if (s > 200ULL * MB) {
            [g2 addObject:a];
        } else if (s > 50ULL * MB) {
            [g3 addObject:a];
        } else {
            [g4 addObject:a];
        }
    }

    NSMutableArray<ASVideoSizeSection *> *secs = [NSMutableArray array];

    if (g1.count > 0) {
        ASVideoSizeSection *s = [ASVideoSizeSection new];
        s.title = @"> 500MB";
        s.assets = [g1 copy];
        [secs addObject:s];
    }
    if (g2.count > 0) {
        ASVideoSizeSection *s = [ASVideoSizeSection new];
        s.title = @"200MB - 500MB";
        s.assets = [g2 copy];
        [secs addObject:s];
    }
    if (g3.count > 0) {
        ASVideoSizeSection *s = [ASVideoSizeSection new];
        s.title = @"50MB - 200MB";
        s.assets = [g3 copy];
        [secs addObject:s];
    }
    if (g4.count > 0) {
        ASVideoSizeSection *s = [ASVideoSizeSection new];
        s.title = @"< 50MB";
        s.assets = [g4 copy];
        [secs addObject:s];
    }

    self.sections = [secs copy];
}

#pragma mark - Top Stats

- (void)refreshTopStatsWithPossiblyUnknown:(BOOL)possiblyUnknown {
    NSArray<PHAsset *> *videos = self.displayVideos ?: @[];

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

    if (possiblyUnknown && unknown > 0) {
        self.totalSpaceLabel.text = [NSString stringWithFormat:@"Total Video Space: %@ +", [self humanSize:total]];
        self.spaceSavedLabel.text = [NSString stringWithFormat:@"Estimated Saved (50%%): %@ +", [self humanSize:saved]];
    } else {
        self.totalSpaceLabel.text = [NSString stringWithFormat:@"Total Video Space: %@", [self humanSize:total]];
        self.spaceSavedLabel.text = [NSString stringWithFormat:@"Estimated Saved (50%%): %@", [self humanSize:saved]];
    }
}

#pragma mark - Size / Thumbnail Helpers

- (uint64_t)cachedFileSizeForAsset:(PHAsset *)asset {
    NSNumber *n = nil;
    @synchronized (self.sizeCache) {
        n = self.sizeCache[asset.localIdentifier];
    }
    return n ? n.unsignedLongLongValue : 0;
}

// fileSize 是 KVC 私有字段，可能取不到 -> 返回0
- (uint64_t)fileSizeForAsset:(PHAsset *)asset {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    PHAssetResource *target = nil;
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypeVideo || r.type == PHAssetResourceTypePairedVideo) {
            target = r;
            break;
        }
    }
    if (!target) target = resources.firstObject;
    if (!target) return 0;

    NSNumber *n = nil;
    @try {
        n = [target valueForKey:@"fileSize"];
    } @catch (__unused NSException *e) {
        n = nil;
    }
    return n.unsignedLongLongValue;
}

- (NSString *)humanSize:(uint64_t)bytes {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024;
    if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024;
    if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024;
    return [NSString stringWithFormat:@"%.2f GB", b];
}

- (NSString *)saveMBTextForBytes:(uint64_t)bytes {
    double saveBytes = (double)bytes / 2.0;
    double mb = saveBytes / (1024.0 * 1024.0);
    if (mb <= 0.0) return @"Save -- MB";
    return [NSString stringWithFormat:@"Save %.0f MB", mb];
}

- (NSString *)durationText:(NSTimeInterval)duration {
    NSInteger d = (NSInteger)llround(duration);
    NSInteger m = d / 60;
    NSInteger s = d % 60;
    if (m >= 60) {
        NSInteger h = m / 60;
        m = m % 60;
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    ASVideoSizeSection *sec = self.sections[section];
    return sec.assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASVideoCell" forIndexPath:indexPath];

    ASVideoSizeSection *sec = self.sections[indexPath.section];
    PHAsset *asset = sec.assets[indexPath.item];
    cell.representedAssetIdentifier = asset.localIdentifier;

    uint64_t bytes = [self cachedFileSizeForAsset:asset];

    cell.sizeLabel.text = (bytes > 0) ? [self humanSize:bytes] : @"--";
    cell.saveLabel.text = (bytes > 0) ? [self saveMBTextForBytes:bytes] : @"Save -- MB";
    cell.durationLabel.text = [self durationText:asset.duration];

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
    // 例：单选
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

#pragma mark - Date Helpers

- (NSDate *)startOfDayForDate:(NSDate *)date {
    return [[NSCalendar currentCalendar] startOfDayForDate:date];
}

- (NSDate *)startOfWeekForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    cal.firstWeekday = 2; // 周一
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

@end
