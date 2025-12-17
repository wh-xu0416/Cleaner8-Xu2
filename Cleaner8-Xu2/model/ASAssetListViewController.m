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

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic, strong) NSMutableArray<ASAssetSection *> *sections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;

@property (nonatomic) uint64_t totalCleanableBytes;
@property (nonatomic) uint64_t selectedBytes;
@end

@implementation ASAssetListViewController

- (instancetype)initWithMode:(ASAssetListMode)mode {
    if (self=[super init]) {
        _mode = mode;
        _sections = [NSMutableArray array];
        _selectedIds = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    self.title = [self titleForMode:self.mode];

    [self setupUI];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 在后台构建 sections（注意不要触碰 UI）
        [self rebuildDataFromManager]; // 如果里面会用 Photos fetch，仍建议在主线程；纯逻辑才放后台

        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyDefaultSelectionRule];
            [self.cv reloadData];
            [self recomputeBytesAndRefreshUI];
        });
    });
    [self setupNavSelectAllIfNeeded];
}

#pragma mark - UI

- (void)setupUI {
    self.bottomBarH = 64;

    // 1) collectionView 先铺满（底部用 contentInset 给悬浮栏留空间）
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

    // 2) bottomBar（悬浮）
    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.whiteColor;
    bar.layer.cornerRadius = 16;
    bar.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.12].CGColor;
    bar.layer.shadowOpacity = 1;
    bar.layer.shadowOffset = CGSizeMake(0, -2);
    bar.layer.shadowRadius = 10;

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

    // 删除按钮：默认隐藏（只有选中才显示）
    self.deleteBtn.hidden = YES;
    self.deleteBtn.alpha = 0.0;

    // 关键：永远给列表底部留出空间（不要选中/取消时改 inset，避免闪）
    UIEdgeInsets inset = self.cv.contentInset;
    inset.bottom = self.bottomBarH + 16;
    self.cv.contentInset = inset;
    self.cv.scrollIndicatorInsets = inset;

    [self.view bringSubviewToFront:self.bottomBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.cv.frame = self.view.bounds;

    CGFloat side = 12;
    CGFloat barH = self.bottomBarH;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    CGFloat barW = self.view.bounds.size.width - side * 2;
    CGFloat barX = side;
    CGFloat barY = self.view.bounds.size.height - safeBottom - 8 - barH;

    self.bottomBar.frame = CGRectMake(barX, barY, barW, barH);

    // label / button 布局
    CGFloat pad = 14;
    CGFloat btnW = 110;
    CGFloat btnH = 36;

    self.deleteBtn.frame = CGRectMake(barW - pad - btnW, (barH - btnH)/2.0, btnW, btnH);
    self.totalLabel.frame = CGRectMake(pad, 8, barW - pad*2 - btnW - 10, barH - 16);
}

- (void)setupNavSelectAllIfNeeded {
    // 你要求：右上角全选（相似/重复：除每组第一个；其他：正常全选）
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

// 组日期：取该组里“最新”的那张（max）
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

- (void)rebuildDataFromManager {
    [self.sections removeAllObjects];

    if ([self isGroupMode]) {
        NSArray<ASAssetGroup *> *src = (self.mode == ASAssetListModeSimilarImage ||
                                        self.mode == ASAssetListModeSimilarVideo)
                                        ? (self.scanMgr.similarGroups ?: @[])
                                        : (self.scanMgr.duplicateGroups ?: @[]);

        ASGroupType t = [self wantedGroupType];

        for (ASAssetGroup *g in src) {
            if (g.type != t) continue;

            // 先收集该组所有 id
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (m.localId.length) [ids addObject:m.localId];
            }
            if (ids.count < 2) continue;

            // 一次性 fetch
            PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
            NSMutableSet<NSString *> *exist = [NSMutableSet setWithCapacity:fr.count];
            [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (obj.localIdentifier.length) [exist addObject:obj.localIdentifier];
            }];

            // 再过滤
            NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                if (![exist containsObject:m.localId]) continue;
                [valid addObject:m];
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
        return;
    }

    // ✅ 非分组：先拿到 arr
    NSArray<ASAssetModel *> *arr = @[];
    switch (self.mode) {
        case ASAssetListModeScreenshots:       arr = self.scanMgr.screenshots ?: @[]; break;
        case ASAssetListModeScreenRecordings:  arr = self.scanMgr.screenRecordings ?: @[]; break;
        case ASAssetListModeBigVideos:         arr = self.scanMgr.bigVideos ?: @[]; break;
        default: break;
    }

    // ✅ 批量过滤掉已删除的 localId
    NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (ASAssetModel *m in arr) {
        if (m.localId.length) [ids addObject:m.localId];
    }

    NSMutableSet<NSString *> *exist = [NSMutableSet set];
    if (ids.count > 0) {
        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
        exist = [NSMutableSet setWithCapacity:fr.count];
        [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.localIdentifier.length) [exist addObject:obj.localIdentifier];
        }];
    }

    for (ASAssetModel *m in arr) {
        if (!m.localId.length) continue;
        if (ids.count > 0 && ![exist containsObject:m.localId]) continue;
        [valid addObject:m];
    }

    ASAssetSection *s = [ASAssetSection new];
    s.isGrouped = NO;
    s.title = @"";
    s.assets = valid;

    [s.assets sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
        NSDate *da = [self dateForModel:a];
        NSDate *db = [self dateForModel:b];

        if (!da && !db) return NSOrderedSame;
        if (!da) return NSOrderedDescending;
        if (!db) return NSOrderedAscending;

        return [db compare:da];
    }];

    [self.sections addObject:s];
}


#pragma mark - Default selection rule

- (void)applyDefaultSelectionRule {
    [self.selectedIds removeAllObjects];

    if ([self isGroupMode]) {
        // 默认全选：每组除第一个
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [self.selectedIds addObject:m.localId];
            }
        }
    } else {
        // 其他正常全选：全部
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

    // 先算 bytes（不要中途 reload）
    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                total += [self bytesForModel:m];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) total += [self bytesForModel:m];
        }
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
    // 判断当前是否“全选”
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
        // 取消全选（清空）
        [self.selectedIds removeAllObjects];
    } else {
        // 全选到目标集合
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

    // 是否本组已全选
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

    // 先拷贝，避免异步过程中 selectedIds 被改动
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

            // 修复 ScanManager 的缓存
//            [[ASPhotoScanManager shared] purgeDeletedAssetsAndRecalculate];

            // 再刷新当前列表
            [weakSelf.selectedIds removeAllObjects];
            [weakSelf rebuildDataFromManager];
            [weakSelf applyDefaultSelectionRule];
            [weakSelf.cv reloadData];
            [weakSelf recomputeBytesAndRefreshUI];
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
    cell.representedLocalId = m.localId;

    PHAsset *a = [PHAsset fetchAssetsWithLocalIdentifiers:@[m.localId] options:nil].firstObject;
    if (!a) return cell;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES; // iCloud 上的也能拉
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.synchronous = NO;

    // 用 imageView 实际尺寸 * 屏幕 scale
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize viewSize = cell.img.bounds.size;
    if (viewSize.width <= 1 || viewSize.height <= 1) {
        // 兜底：如果此时 bounds 还没布局好
        viewSize = cell.contentView.bounds.size;
    }
    CGSize target = CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            // 防复用：确保还是同一个 localId
            if (![cell.representedLocalId isEqualToString:m.localId]) return;
            cell.img.image = result;
        });
    }];

    return cell;
}


#pragma mark - Selection (tap)

- (BOOL)isIndexPathCleanable:(NSIndexPath *)ip {
    return YES; // 允许第一张也能单选删除
}

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

    //  只控制删除按钮显示/隐藏，bottomBar 一直浮着
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
    [collectionView deselectItemAtIndexPath:indexPath animated:NO]; //  去掉系统高亮闪

    ASAssetModel *m = self.sections[indexPath.section].assets[indexPath.item];
    if (!m.localId.length) return;

    if ([self.selectedIds containsObject:m.localId]) [self.selectedIds removeObject:m.localId];
    else [self.selectedIds addObject:m.localId];

    [self updateOneCell:indexPath];          //  只更新这个格子
    [self recomputeBytesAndRefreshTopOnly];  //  只更新顶部文字/按钮，不 reloadData
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
    return CGSizeMake(itemW, itemW); // 正方形
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

    // 非分组也给个“全选/取消”，你不想要就把按钮隐藏掉
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
