#import "ASAssetListViewController.h"
#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"

#pragma mark - UI helpers

static inline NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

static inline NSString *ASTypeText(PHAssetMediaType t) {
    return (t == PHAssetMediaTypeVideo) ? @"视频" : @"图片";
}

#pragma mark - Section model

@interface ASAssetSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *assets;
@property (nonatomic, strong) NSDate *groupDate; // 组排序
@property (nonatomic) BOOL isGrouped; // 相似/重复的那种分组 section
@end
@implementation ASAssetSection @end

#pragma mark - Cell

@interface ASAssetGridCell : UICollectionViewCell
@property (nonatomic, copy) NSString *representedLocalId;
@property (nonatomic, strong) UIImageView *img;
@property (nonatomic, strong) UILabel *badge;     // 右下角：类型
@property (nonatomic, strong) UILabel *sizeLabel; // 右下角：大小（在 badge 下）
@property (nonatomic, strong) UIView *checkDot;   // 右上角勾选点
- (void)applySelected:(BOOL)sel;
@end

@implementation ASAssetGridCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
        self.contentView.layer.cornerRadius = 10;
        self.contentView.clipsToBounds = YES;

        _img = [UIImageView new];
        _img.contentMode = UIViewContentModeScaleAspectFill;
        _img.clipsToBounds = YES;

        _badge = [UILabel new];
        _badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 8;
        _badge.clipsToBounds = YES;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _sizeLabel.textColor = UIColor.whiteColor;
        _sizeLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _sizeLabel.textAlignment = NSTextAlignmentCenter;
        _sizeLabel.layer.cornerRadius = 8;
        _sizeLabel.clipsToBounds = YES;

        _checkDot = [UIView new];
        _checkDot.layer.cornerRadius = 10;
        _checkDot.layer.borderWidth = 2;
        _checkDot.layer.borderColor = [UIColor whiteColor].CGColor;
        _checkDot.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];

        [self.contentView addSubview:_img];
        [self.contentView addSubview:_badge];
        [self.contentView addSubview:_sizeLabel];
        [self.contentView addSubview:_checkDot];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.img.frame = self.contentView.bounds;

    CGFloat pad = 6;
    self.checkDot.frame = CGRectMake(self.contentView.bounds.size.width - 20 - pad, pad, 20, 20);

    CGFloat w = 54;
    CGFloat h = 16;
    self.sizeLabel.frame = CGRectMake(self.contentView.bounds.size.width - w - pad,
                                      self.contentView.bounds.size.height - h - pad,
                                      w, h);
    self.badge.frame = CGRectMake(self.contentView.bounds.size.width - w - pad,
                                  CGRectGetMinY(self.sizeLabel.frame) - h - 4,
                                  w, h);
}
- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedLocalId = @"";
    self.img.image = nil;
    self.badge.text = @"";
    self.sizeLabel.text = @"";
    [self applySelected:NO];
}
- (void)applySelected:(BOOL)sel {
    self.checkDot.backgroundColor = sel ? [UIColor systemBlueColor] : [UIColor colorWithWhite:0 alpha:0.25];
}
@end

#pragma mark - Section header

@interface ASAssetSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *selectAllBtn;
@property (nonatomic, copy) void (^tapSelectAll)(void);
@end

@implementation ASAssetSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_selectAllBtn setTitle:@"全选" forState:UIControlStateNormal];
        [_selectAllBtn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:_titleLabel];
        [self addSubview:_selectAllBtn];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 16;
    self.titleLabel.frame = CGRectMake(pad, 0, self.bounds.size.width - pad*2 - 80, self.bounds.size.height);
    self.selectAllBtn.frame = CGRectMake(self.bounds.size.width - pad - 80, 0, 80, self.bounds.size.height);
}
- (void)onTap { if (self.tapSelectAll) self.tapSelectAll(); }
@end

#pragma mark - VC

@interface ASAssetListViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic) ASAssetListMode mode;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic) CGFloat bottomBarH;

@property (nonatomic, strong) UIView *customNavBar;  // 自定义导航栏
@property (nonatomic, strong) UILabel *titleLabel;   // 自定义标题
@property (nonatomic, strong) UIButton *backButton;  // 返回按钮
@property (nonatomic, strong) UIButton *selectAllButton; // 全选按钮

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic, strong) NSMutableArray<ASAssetSection *> *sections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;

@property (nonatomic) uint64_t totalCleanableBytes;
@property (nonatomic) uint64_t selectedBytes;

@property (nonatomic, strong) NSDictionary<NSString*, PHAsset*> *assetById;
@end

@implementation ASAssetListViewController

- (instancetype)initWithMode:(ASAssetListMode)mode {
    if (self=[super init]) {
        _mode = mode;
        _sections = [NSMutableArray array];
        _selectedIds = [NSMutableSet set];
        _assetById = @{};
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 隐藏系统的导航栏
    self.navigationController.navigationBar.hidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 隐藏系统的导航栏
    self.navigationController.navigationBar.hidden = YES;

    // 设置自定义导航栏
    [self setupCustomNavBar];

    // 继续执行原有代码
    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    self.title = [self titleForMode:self.mode];
    [self setupUI];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self rebuildDataFromManager];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyDefaultSelectionRule];
            [self.cv reloadData];
            [self recomputeBytesAndRefreshUI];
        });
    });

    [self setupNavSelectAllIfNeeded];
}

#pragma mark - 自定义导航栏设置

- (void)setupCustomNavBar {
    CGFloat navBarHeight = 44 + self.view.safeAreaInsets.top;  // 适配刘海屏

    // 创建自定义导航栏容器
    self.customNavBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, navBarHeight)];
    self.customNavBar.backgroundColor = [UIColor whiteColor]; // 设置背景色为白色

    // 创建返回按钮
    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.frame = CGRectMake(10, self.view.safeAreaInsets.top, 44, 44);  // 左上角按钮
    [self.backButton setImage:[UIImage systemImageNamed:@"arrow.left.circle.fill"] forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(onBackButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.customNavBar addSubview:self.backButton];

    // 创建标题
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.titleLabel.text = self.title;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textColor = [UIColor blackColor];
    [self.customNavBar addSubview:self.titleLabel];

    // 创建全选按钮
    self.selectAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectAllButton.frame = CGRectMake(self.view.bounds.size.width - 80, self.view.safeAreaInsets.top, 80, 44);
    [self.selectAllButton setTitle:@"全选" forState:UIControlStateNormal];
    [self.selectAllButton addTarget:self action:@selector(onSelectAllTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.customNavBar addSubview:self.selectAllButton];

    // 将自定义导航栏添加到视图
    [self.view addSubview:self.customNavBar];
}

- (void)onBackButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onSelectAllTapped {
    // 在这里添加全选的操作逻辑
    [self toggleSelectAll];
}

#pragma mark - 自定义布局调整

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // 确保自定义导航栏的frame正确
    CGFloat navBarHeight = 44 + self.view.safeAreaInsets.top;  // 适配刘海屏
    self.customNavBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navBarHeight);

    // 调整UICollectionView的contentInset，以避开自定义导航栏
    UIEdgeInsets inset = self.cv.contentInset;
    inset.top = navBarHeight;  // 更新 contentInset 的 top 值
    self.cv.contentInset = inset;
    self.cv.scrollIndicatorInsets = inset;

    // 确保自定义导航栏显示在最上面
    [self.view bringSubviewToFront:self.customNavBar];
}

#pragma mark - UI 设置

- (void)setupUI {
    self.bottomBarH = 64;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(10, 12, 12, 12);
    layout.headerReferenceSize = CGSizeMake(self.view.bounds.size.width, 44);

    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                 collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.whiteColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;

    [self.cv registerClass:ASAssetGridCell.class forCellWithReuseIdentifier:@"ASAssetGridCell"];
    [self.cv registerClass:ASAssetSectionHeader.class
forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
       withReuseIdentifier:@"ASAssetSectionHeader"];

    [self.view addSubview:self.cv];

    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.whiteColor;
    bar.layer.cornerRadius = 16;

    UILabel *lab = [UILabel new];
    lab.numberOfLines = 2;
    lab.font = [UIFont systemFontOfSize:13];
    lab.textColor = [UIColor darkGrayColor];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.layer.cornerRadius = 12;
    btn.backgroundColor = [UIColor systemRedColor];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [btn addTarget:self action:@selector(onDelete) forControlEvents:UIControlEventTouchUpInside];

    [bar addSubview:lab];
    [bar addSubview:btn];
    [self.view addSubview:bar];

    self.bottomBar = bar;
    self.totalLabel = lab;
    self.deleteBtn = btn;

    self.deleteBtn.hidden = YES;
    self.deleteBtn.alpha = 0.0;

    UIEdgeInsets inset = self.cv.contentInset;
    inset.bottom = self.bottomBarH + 16;
    self.cv.contentInset = inset;
    self.cv.scrollIndicatorInsets = inset;

    [self.view bringSubviewToFront:self.bottomBar];
}

#pragma mark - 全选功能

- (void)toggleSelectAll {
    NSMutableSet<NSString *> *shouldAll = [NSMutableSet set];

    // 根据模式选择全选的内容
    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [shouldAll addObject:m.localId];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) if (m.localId.length) [shouldAll addObject:m.localId];
        }
    }

    // 检查当前是否已经全选，如果已全选则取消选择，否则全选
    BOOL alreadyAll = YES;
    for (NSString *lid in shouldAll) {
        if (![self.selectedIds containsObject:lid]) { alreadyAll = NO; break; }
    }

    if (alreadyAll) {
        [self.selectedIds removeAllObjects];
    } else {
        [self.selectedIds unionSet:shouldAll];
    }

    [self recomputeBytesAndRefreshUI];
}

- (void)setupNavSelectAllIfNeeded {
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:@"全选"
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(onSelectAllToggle)];
    self.navigationItem.rightBarButtonItem = btn;
}

#pragma mark - Build data

- (NSString *)titleForMode:(ASAssetListMode)mode {
    switch (mode) {
        case ASAssetListModeSimilarImage: return @"相似图片";
        case ASAssetListModeSimilarVideo: return @"相似视频";
        case ASAssetListModeDuplicateImage: return @"重复图片";
        case ASAssetListModeDuplicateVideo: return @"重复视频";
        case ASAssetListModeScreenshots: return @"截屏";
        case ASAssetListModeScreenRecordings: return @"录屏";
        case ASAssetListModeBigVideos: return @">20MB 视频";
    }
    return @"列表";
}

- (NSDate *)dateForModel:(ASAssetModel *)m {
    return m.creationDate ?: m.modificationDate;
}

- (NSDate *)dateForGroupAssets:(NSArray<ASAssetModel *> *)assets {
    NSDate *best = nil;
    for (ASAssetModel *m in assets) {
        NSDate *d = [self dateForModel:m];
        if (!d) continue;
        if (!best || [d compare:best] == NSOrderedDescending) best = d;
    }
    return best ?: [NSDate dateWithTimeIntervalSince1970:0];
}

- (BOOL)isGroupMode {
    return (self.mode == ASAssetListModeSimilarImage ||
            self.mode == ASAssetListModeSimilarVideo ||
            self.mode == ASAssetListModeDuplicateImage ||
            self.mode == ASAssetListModeDuplicateVideo);
}

- (ASGroupType)wantedGroupType {
    switch (self.mode) {
        case ASAssetListModeSimilarImage:   return ASGroupTypeSimilarImage;
        case ASAssetListModeSimilarVideo:   return ASGroupTypeSimilarVideo;
        case ASAssetListModeDuplicateImage: return ASGroupTypeDuplicateImage;
        case ASAssetListModeDuplicateVideo: return ASGroupTypeDuplicateVideo;
        default: return ASGroupTypeDuplicateImage;
    }
}

/// ✅ 核心：构建 sections + 一次性 batch fetch 所有 ids，填 assetById
- (void)rebuildDataFromManager {
    [self.sections removeAllObjects];
    self.assetById = @{}; // 先清空

    if ([self isGroupMode]) {
        NSArray<ASAssetGroup *> *src = (self.mode == ASAssetListModeSimilarImage ||
                                        self.mode == ASAssetListModeSimilarVideo)
                                        ? (self.scanMgr.similarGroups ?: @[])
                                        : (self.scanMgr.duplicateGroups ?: @[]);

        ASGroupType t = [self wantedGroupType];

        // 先建 section（这一步只处理 ASAssetModel，不触碰 PHAsset）
        for (ASAssetGroup *g in src) {
            if (g.type != t) continue;

            NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (m.localId.length) [valid addObject:m];
            }
            if (valid.count < 2) continue;

            ASAssetSection *s = [ASAssetSection new];
            s.isGrouped = YES;
            s.assets = valid;
            s.groupDate = [self dateForGroupAssets:s.assets];
            [self.sections addObject:s];
        }

        [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
            return [b.groupDate compare:a.groupDate];
        }];

        NSInteger idx = 1;
        for (ASAssetSection *sec in self.sections) {
            sec.title = [NSString stringWithFormat:@"第 %ld 组（%lu）", (long)idx, (unsigned long)sec.assets.count];
            idx++;
        }
    } else {
        NSArray<ASAssetModel *> *arr = @[];
        switch (self.mode) {
            case ASAssetListModeScreenshots:       arr = self.scanMgr.screenshots ?: @[]; break;
            case ASAssetListModeScreenRecordings:  arr = self.scanMgr.screenRecordings ?: @[]; break;
            case ASAssetListModeBigVideos:         arr = self.scanMgr.bigVideos ?: @[]; break;
            default: break;
        }

        NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
        for (ASAssetModel *m in arr) {
            if (m.localId.length) [valid addObject:m];
        }

        [valid sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
            NSDate *da = [self dateForModel:a];
            NSDate *db = [self dateForModel:b];

            if (!da && !db) return NSOrderedSame;
            if (!da) return NSOrderedDescending;
            if (!db) return NSOrderedAscending;

            return [db compare:da];
        }];

        ASAssetSection *s = [ASAssetSection new];
        s.isGrouped = NO;
        s.title = @"";
        s.assets = valid;

        [self.sections addObject:s];
    }

    // ✅ 统一收集所有 localId，一次性 fetch PHAsset，并过滤掉已经不存在的 id
    NSMutableArray<NSString *> *allIds = [NSMutableArray array];

    for (ASAssetSection *sec in self.sections) {
        for (ASAssetModel *m in sec.assets) {
            if (m.localId.length) [allIds addObject:m.localId];
        }
    }

    if (allIds.count == 0) {
        self.assetById = @{};
        return;
    }

    // 去重（避免 fetch 重复 id）
    NSOrderedSet<NSString *> *uniq = [NSOrderedSet orderedSetWithArray:allIds];
    NSArray<NSString *> *uniqIds = uniq.array;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:uniqIds options:nil];
    NSMutableDictionary<NSString*, PHAsset*> *map = [NSMutableDictionary dictionaryWithCapacity:fr.count];

    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) {
            map[obj.localIdentifier] = obj;
        }
    }];

    self.assetById = map;

    // ✅ 过滤掉 asset 不存在的 model（避免列表里出现空格子/闪）
    for (NSInteger si = self.sections.count - 1; si >= 0; si--) {
        ASAssetSection *sec = self.sections[si];

        NSMutableArray<ASAssetModel *> *kept = [NSMutableArray arrayWithCapacity:sec.assets.count];
        for (ASAssetModel *m in sec.assets) {
            if (!m.localId.length) continue;
            if (!self.assetById[m.localId]) continue;
            [kept addObject:m];
        }

        sec.assets = kept;

        // 分组：不足 2 就整组丢掉
        if (sec.isGrouped && sec.assets.count < 2) {
            [self.sections removeObjectAtIndex:si];
        }
    }

    // 分组标题重排（因为过滤后可能删了组）
    if ([self isGroupMode]) {
        NSInteger idx2 = 1;
        for (ASAssetSection *sec in self.sections) {
            sec.title = [NSString stringWithFormat:@"第 %ld 组（%lu）", (long)idx2, (unsigned long)sec.assets.count];
            idx2++;
        }
    }
}

#pragma mark - Default selection rule

- (void)applyDefaultSelectionRule {
    [self.selectedIds removeAllObjects];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [self.selectedIds addObject:m.localId];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) {
                if (m.localId.length) [self.selectedIds addObject:m.localId];
            }
        }
    }
}

#pragma mark - Bytes + UI refresh

- (uint64_t)bytesForModel:(ASAssetModel *)m { return m.fileSizeBytes; }

- (void)recomputeBytesAndRefreshUI {
    uint64_t total = 0;
    uint64_t selected = 0;

    [self recomputeBytesAndRefreshTopOnly];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i=1; i<sec.assets.count; i++) total += [self bytesForModel:sec.assets[i]];
        }
    } else {
        for (ASAssetSection *sec in self.sections)
            for (ASAssetModel *m in sec.assets) total += [self bytesForModel:m];
    }

    for (ASAssetSection *sec in self.sections) {
        for (ASAssetModel *m in sec.assets) {
            if ([self.selectedIds containsObject:m.localId]) selected += [self bytesForModel:m];
        }
    }

    self.totalCleanableBytes = total;
    self.selectedBytes = selected;

    self.totalLabel.text = [NSString stringWithFormat:@"总可清理：%@\n已选：%@",
                            ASHumanSize(self.totalCleanableBytes),
                            ASHumanSize(self.selectedBytes)];

    BOOL canDelete = (self.selectedIds.count > 0);
    self.deleteBtn.enabled = canDelete;
    self.deleteBtn.alpha = canDelete ? 1.0 : 0.4;
    [self.deleteBtn setTitle:[NSString stringWithFormat:@"删除(%@)", ASHumanSize(self.selectedBytes)]
                    forState:UIControlStateNormal];

    for (NSIndexPath *ip in self.cv.indexPathsForVisibleItems) {
        if (ip.section >= self.sections.count) continue;
        ASAssetSection *sec = self.sections[ip.section];
        if (ip.item >= sec.assets.count) continue;

        ASAssetGridCell *cell = (ASAssetGridCell *)[self.cv cellForItemAtIndexPath:ip];
        if (!cell) continue;

        ASAssetModel *m = sec.assets[ip.item];
        [cell applySelected:[self.selectedIds containsObject:m.localId]];
    }
}

#pragma mark - Select all (nav)

- (void)onSelectAllToggle {
    NSMutableSet<NSString *> *shouldAll = [NSMutableSet set];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [shouldAll addObject:m.localId];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) if (m.localId.length) [shouldAll addObject:m.localId];
        }
    }

    BOOL alreadyAll = YES;
    for (NSString *lid in shouldAll) {
        if (![self.selectedIds containsObject:lid]) { alreadyAll = NO; break; }
    }

    if (alreadyAll) {
        [self.selectedIds removeAllObjects];
    } else {
        [self.selectedIds unionSet:shouldAll];
    }

    [self recomputeBytesAndRefreshUI];
}

#pragma mark - Per section select all

- (void)toggleSectionAll:(NSInteger)sectionIndex {
    if (sectionIndex >= self.sections.count) return;
    ASAssetSection *sec = self.sections[sectionIndex];

    NSMutableArray<ASAssetModel *> *targets = [NSMutableArray array];
    if ([self isGroupMode] && sec.isGrouped) {
        for (NSInteger i = 1; i < sec.assets.count; i++) [targets addObject:sec.assets[i]];
    } else {
        [targets addObjectsFromArray:sec.assets];
    }

    BOOL allSel = YES;
    for (ASAssetModel *m in targets) {
        if (![self.selectedIds containsObject:m.localId]) { allSel = NO; break; }
    }

    if (allSel) {
        for (ASAssetModel *m in targets) [self.selectedIds removeObject:m.localId];
    } else {
        for (ASAssetModel *m in targets) if (m.localId.length) [self.selectedIds addObject:m.localId];
    }

    [self recomputeBytesAndRefreshUI];
}

#pragma mark - Delete

- (void)onDelete {
    if (self.selectedIds.count == 0) return;

    NSSet<NSString *> *toDelete = [self.selectedIds copy];
    NSArray<NSString *> *ids = toDelete.allObjects;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    __weak typeof(self) weakSelf = self;

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:fr];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) return;

            [weakSelf.selectedIds removeAllObjects];

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf rebuildDataFromManager];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf applyDefaultSelectionRule];
                    [weakSelf.cv reloadData];
                    [weakSelf recomputeBytesAndRefreshUI];
                });
            });
        });
    }];
}

#pragma mark - Collection DS

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.sections[section].assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASAssetGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASAssetGridCell" forIndexPath:indexPath];
    ASAssetModel *m = self.sections[indexPath.section].assets[indexPath.item];

    cell.badge.text = ASTypeText(m.mediaType);
    cell.sizeLabel.text = ASHumanSize(m.fileSizeBytes);

    BOOL sel = [self.selectedIds containsObject:m.localId];
    [cell applySelected:sel];

    // 先清空，避免复用闪旧图
    cell.img.image = nil;
    cell.representedLocalId = m.localId ?: @"";

    // ✅ 关键：不再每个 cell fetch，一次性缓存里拿
    PHAsset *a = (m.localId.length ? self.assetById[m.localId] : nil);
    if (!a) return cell;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize viewSize = cell.img.bounds.size;
    if (viewSize.width <= 1 || viewSize.height <= 1) {
        viewSize = cell.contentView.bounds.size;
    }
    CGSize target = CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    __weak typeof(cell) weakCell = cell;
    NSString *expectId = cell.representedLocalId;

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            ASAssetGridCell *c = weakCell;
            if (!c) return;
            if (![c.representedLocalId isEqualToString:expectId]) return;
            c.img.image = result;
        });
    }];

    return cell;
}

#pragma mark - Selection (tap)

- (void)recomputeBytesAndRefreshTopOnly {
    uint64_t total = 0;
    uint64_t selected = 0;

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i=1; i<sec.assets.count; i++) total += sec.assets[i].fileSizeBytes;
        }
    } else {
        for (ASAssetSection *sec in self.sections)
            for (ASAssetModel *m in sec.assets) total += m.fileSizeBytes;
    }

    for (ASAssetSection *sec in self.sections)
        for (ASAssetModel *m in sec.assets)
            if ([self.selectedIds containsObject:m.localId]) selected += m.fileSizeBytes;

    self.totalCleanableBytes = total;
    self.selectedBytes = selected;

    self.totalLabel.text = [NSString stringWithFormat:@"总可清理：%@\n已选：%@",
                            ASHumanSize(self.totalCleanableBytes),
                            ASHumanSize(self.selectedBytes)];

    BOOL canDelete = (self.selectedIds.count > 0);

    [self.deleteBtn setTitle:[NSString stringWithFormat:@"删除(%@)", ASHumanSize(self.selectedBytes)]
                    forState:UIControlStateNormal];
    self.deleteBtn.enabled = canDelete;

    if (canDelete && self.deleteBtn.hidden) {
        self.deleteBtn.hidden = NO;
        [UIView animateWithDuration:0.15 animations:^{
            self.deleteBtn.alpha = 1.0;
        }];
    } else if (!canDelete && !self.deleteBtn.hidden) {
        [UIView animateWithDuration:0.15 animations:^{
            self.deleteBtn.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.deleteBtn.hidden = YES;
        }];
    } else {
        self.deleteBtn.alpha = canDelete ? 1.0 : 0.0;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];

    ASAssetModel *m = self.sections[indexPath.section].assets[indexPath.item];
    if (!m.localId.length) return;

    if ([self.selectedIds containsObject:m.localId]) [self.selectedIds removeObject:m.localId];
    else [self.selectedIds addObject:m.localId];

    [self updateOneCell:indexPath];
    [self recomputeBytesAndRefreshTopOnly];
}

- (void)updateOneCell:(NSIndexPath *)ip {
    ASAssetGridCell *cell = (ASAssetGridCell *)[self.cv cellForItemAtIndexPath:ip];
    if (!cell) return;
    ASAssetModel *m = self.sections[ip.section].assets[ip.item];
    [cell applySelected:[self.selectedIds containsObject:m.localId]];
}

#pragma mark - Layout (3 columns)

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    UIEdgeInsets inset = ((UICollectionViewFlowLayout *)layout).sectionInset;
    CGFloat gap = ((UICollectionViewFlowLayout *)layout).minimumInteritemSpacing;
    CGFloat w = collectionView.bounds.size.width - inset.left - inset.right;
    CGFloat itemW = floor((w - gap*2) / 3.0);
    return CGSizeMake(itemW, itemW);
}

#pragma mark - Header (group section select all)

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) return [UICollectionReusableView new];

    ASAssetSectionHeader *h = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                withReuseIdentifier:@"ASAssetSectionHeader"
                                                                       forIndexPath:indexPath];
    ASAssetSection *sec = self.sections[indexPath.section];
    h.titleLabel.text = sec.isGrouped ? sec.title : @"";

    BOOL showBtn = YES;
    h.selectAllBtn.hidden = !showBtn;

    __weak typeof(self) weakSelf = self;
    h.tapSelectAll = ^{
        [weakSelf toggleSectionAll:indexPath.section];
    };
    return h;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
    ASAssetSection *sec = self.sections[section];
    if ([self isGroupMode]) return CGSizeMake(collectionView.bounds.size.width, 44);
    return CGSizeMake(collectionView.bounds.size.width, 0.01);
}

@end
