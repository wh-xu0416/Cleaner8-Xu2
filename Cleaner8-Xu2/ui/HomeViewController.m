#import "HomeViewController.h"
#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"
#import "ASAssetListViewController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Home Module Model

typedef NS_ENUM(NSUInteger, ASHomeModuleType) {
    ASHomeModuleTypeSimilarImage = 0,
    ASHomeModuleTypeSimilarVideo,
    ASHomeModuleTypeDuplicateImage,
    ASHomeModuleTypeDuplicateVideo,
    ASHomeModuleTypeScreenshots,
    ASHomeModuleTypeScreenRecordings,
    ASHomeModuleTypeBigVideos,
};

@interface ASHomeModuleVM : NSObject
@property (nonatomic) ASHomeModuleType type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSUInteger totalCount;
@property (nonatomic) uint64_t totalBytes;
@property (nonatomic, strong) NSArray<NSString *> *thumbLocalIds; // 最多2个
@end

@implementation ASHomeModuleVM
@end

#pragma mark - Cell

@interface HomeModuleCell : UICollectionViewCell
@property (nonatomic, copy) NSArray<NSString *> *representedLocalIds;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIImageView *img1;
@property (nonatomic, strong) UIImageView *img2;
- (void)applyVM:(ASHomeModuleVM *)vm;
@end

@implementation HomeModuleCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = 12;
        self.contentView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.1].CGColor;
        self.contentView.layer.shadowOpacity = 1;
        self.contentView.layer.shadowOffset = CGSizeMake(0, 2);
        self.contentView.layer.shadowRadius = 6;

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16];

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:13];
        _countLabel.textColor = [UIColor darkGrayColor];

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:13];
        _sizeLabel.textColor = [UIColor darkGrayColor];

        _img1 = [UIImageView new];
        _img2 = [UIImageView new];
        _img1.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
        _img2.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
        _img1.contentMode = UIViewContentModeScaleAspectFill;
        _img2.contentMode = UIViewContentModeScaleAspectFill;
        _img1.clipsToBounds = YES;
        _img2.clipsToBounds = YES;
        _img1.layer.cornerRadius = 8;
        _img2.layer.cornerRadius = 8;

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_countLabel];
        [self.contentView addSubview:_sizeLabel];
        [self.contentView addSubview:_img1];
        [self.contentView addSubview:_img2];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat pad = 12;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;

    self.titleLabel.frame = CGRectMake(pad, pad, w - pad*2, 20);
    self.countLabel.frame = CGRectMake(pad, CGRectGetMaxY(self.titleLabel.frame) + 6, w - pad*2, 18);
    self.sizeLabel.frame  = CGRectMake(pad, CGRectGetMaxY(self.countLabel.frame) + 2, w - pad*2, 18);

    CGFloat imgY = CGRectGetMaxY(self.sizeLabel.frame) + 10;
    CGFloat imgW = (w - pad*2 - 10) / 2.0;
    CGFloat imgH = h - imgY - pad;

    self.img1.frame = CGRectMake(pad, imgY, imgW, imgH);
    self.img2.frame = CGRectMake(CGRectGetMaxX(self.img1.frame) + 10, imgY, imgW, imgH);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedLocalIds = @[];
    self.img1.image = nil;
    self.img2.image = nil;
}

- (void)applyVM:(ASHomeModuleVM *)vm {
    self.titleLabel.text = vm.title;
    self.countLabel.text = [NSString stringWithFormat:@"数量：%lu", (unsigned long)vm.totalCount];
    self.sizeLabel.text  = [NSString stringWithFormat:@"大小：%@", [HomeModuleCell humanSize:vm.totalBytes]];
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

@interface HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, assign) ASScanState lastScanState;
@property (nonatomic, assign) BOOL didBuildOnce;

@property (nonatomic, strong) NSSet<NSString *> *allCleanableIds;   // 去重后的可删集合
@property (nonatomic, assign) uint64_t allCleanableBytes;           // 去重后的总大小
@property (nonatomic, strong) UILabel *totalBytesLabel;
@property (nonatomic, strong) UIButton *deleteAllBtn;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<ASHomeModuleVM *> *modules;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic, strong) UILabel *scanStateLabel; // 顶部实时状态
@end

@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;
    self.title = @"首页";

    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    __weak typeof(self) weakSelf = self;
    [self.scanMgr subscribeProgress:^(ASScanSnapshot *snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateScanStateText:snapshot];

            // ✅ 只在首次构建一次（比如从缓存来的）
            if (!weakSelf.didBuildOnce) {
                weakSelf.didBuildOnce = YES;
                weakSelf.lastScanState = snapshot.state;
                [weakSelf rebuildModulesFromManagerAndReload];
                return;
            }

            // ✅ 扫描中不刷新模块，避免闪
            // ✅ 只有状态从 scanning -> finished 才刷新一次
            if (weakSelf.lastScanState != snapshot.state &&
                snapshot.state == ASScanStateFinished) {
                weakSelf.lastScanState = snapshot.state;
                [weakSelf rebuildModulesFromManagerAndReload];
                return;
            }

            weakSelf.lastScanState = snapshot.state;
        });
    }];


    [self setupUI];

    [self.scanMgr loadCacheAndCheckIncremental];

    [self rebuildModulesFromManagerAndReload];

    [self requestPhotoPermissionThenStartScan];
}

- (void)startScanCallbacks {
    __weak typeof(self) weakSelf = self;

    // 如果上次已经扫完，有缓存，别再全量扫
    if (self.scanMgr.snapshot.state == ASScanStateFinished) {
        // 不用 return 了，增量靠 subscribeProgress 推进 UI
        return;
    }

    [self.scanMgr startFullScanWithProgress:^(ASScanSnapshot *snapshot) {
//        [weakSelf updateScanStatomManagerAndReload];
    } completion:^(ASScanSnapshot *snapshot, NSError * _Nullable error) {
//        [weakSelf updateScanStateText:snapshot];
//        [weakSelf rebuildModulesFromManagerAndReload];
    }];
}


#pragma mark - UI

- (void)setupUI {
    CGFloat w = self.view.bounds.size.width;

    self.scanStateLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 88, w - 32, 18)];
    self.scanStateLabel.font = [UIFont systemFontOfSize:13];
    self.scanStateLabel.textColor = [UIColor grayColor];
    [self.view addSubview:self.scanStateLabel];

    // ✅ 总大小（去重）
    self.totalBytesLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(self.scanStateLabel.frame) + 8, w - 32 - 110, 18)];
    self.totalBytesLabel.font = [UIFont systemFontOfSize:13];
    self.totalBytesLabel.textColor = [UIColor grayColor];
    self.totalBytesLabel.text = @"可清理总大小：--";
    [self.view addSubview:self.totalBytesLabel];

    // ✅ 一键删除
    self.deleteAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.deleteAllBtn.frame = CGRectMake(w - 16 - 100, CGRectGetMinY(self.totalBytesLabel.frame) - 4, 100, 26);
    self.deleteAllBtn.layer.cornerRadius = 6;
    self.deleteAllBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1];
    [self.deleteAllBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.deleteAllBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.deleteAllBtn setTitle:@"一键删除" forState:UIControlStateNormal];
    [self.deleteAllBtn addTarget:self action:@selector(onDeleteAllTapped) forControlEvents:UIControlEventTouchUpInside];
    self.deleteAllBtn.enabled = NO;
    self.deleteAllBtn.alpha = 0.4;
    [self.view addSubview:self.deleteAllBtn];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(12, 16, 16, 16);

    CGFloat top = CGRectGetMaxY(self.totalBytesLabel.frame) + 10;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, top, w, self.view.bounds.size.height - top)
                                 collectionViewLayout:layout];
    self.cv.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1];
    self.cv.dataSource = self;
    self.cv.delegate = self;
    [self.cv registerClass:HomeModuleCell.class forCellWithReuseIdentifier:@"HomeModuleCell"];
    [self.view addSubview:self.cv];
}

- (void)onDeleteAllTapped {
    if (self.allCleanableIds.count == 0) return;

    // ✅ 可选：扫描中先不让删（更稳）
    if (self.scanMgr.snapshot.state == ASScanStateScanning) {
        NSLog(@"scanning... consider stop scan before deleting");
        // 你也可以弹 UIAlertController 提示
        // return;
    }

    NSArray<NSString *> *ids = self.allCleanableIds.allObjects;
    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        [PHAssetChangeRequest deleteAssets:fr];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                NSLog(@"delete failed: %@", error);
                return;
            }
            [self.scanMgr loadCacheAndCheckIncremental];
            [self rebuildModulesFromManagerAndReload];
        });
    }];
}

#pragma mark - Permission + scan

- (void)requestPhotoPermissionThenStartScan {
    PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited) {
        [self startScanCallbacks];
        return;
    }

    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                [self startScanCallbacks];
            } else {
                self.scanStateLabel.text = @"未获得相册权限";
            }
        });
    }];
}

- (void)updateScanStateText:(ASScanSnapshot *)s {
    NSString *state = @"未扫描";
    if (s.state == ASScanStateScanning) state = @"扫描中";
    if (s.state == ASScanStateFinished) state = @"扫描完成";

    self.scanStateLabel.text = [NSString stringWithFormat:@"%@  已扫描:%lu",
                                state,
                                (unsigned long)s.scannedCount];
}

#pragma mark - Build modules

- (void)rebuildModulesFromManagerAndReload {
    self.modules = [self buildModulesFromManager];

    self.totalBytesLabel.text = [NSString stringWithFormat:@"总可清理（去重）：%@  (%lu项)",
                                 [HomeModuleCell humanSize:self.allCleanableBytes],
                                 (unsigned long)self.allCleanableIds.count];

    BOOL canDelete = (self.allCleanableIds.count > 0);
    self.deleteAllBtn.enabled = canDelete;
    self.deleteAllBtn.alpha = canDelete ? 1.0 : 0.4;

    [UIView performWithoutAnimation:^{
          [self.cv reloadData];
    }];
}


- (NSArray<ASHomeModuleVM *> *)buildModulesFromManager {

    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    __block NSArray<ASAssetModel *> *shots = self.scanMgr.screenshots ?: @[];
    __block NSArray<ASAssetModel *> *recs  = self.scanMgr.screenRecordings ?: @[];
    __block NSArray<ASAssetModel *> *bigs  = self.scanMgr.bigVideos ?: @[];

    // ✅ 0) 批量校验当前仍存在的 asset（避免用到已删除的 localId）
    NSMutableArray<NSString *> *candidateIds = [NSMutableArray array];

    void (^collectIdsFromModels)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
        for (ASAssetModel *m in arr) {
            if (m.localId.length) [candidateIds addObject:m.localId];
        }
    };

    void (^collectIdsFromGroups)(NSArray<ASAssetGroup *> *) = ^(NSArray<ASAssetGroup *> *groups) {
        for (ASAssetGroup *g in groups) {
            for (ASAssetModel *m in g.assets) {
                if (m.localId.length) [candidateIds addObject:m.localId];
            }
        }
    };

    collectIdsFromGroups(sim);
    collectIdsFromGroups(dup);
    collectIdsFromModels(shots);
    collectIdsFromModels(recs);
    collectIdsFromModels(bigs);

    PHFetchResult<PHAsset *> *existFR = [PHAsset fetchAssetsWithLocalIdentifiers:candidateIds options:nil];
    NSMutableSet<NSString *> *existIdSet = [NSMutableSet setWithCapacity:existFR.count];
    
    NSArray<ASAssetModel *> *(^filterValidModels)(NSArray<ASAssetModel *> *) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetModel *> *arr) {
        NSMutableArray<ASAssetModel *> *out = [NSMutableArray array];
        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
            if (![existIdSet containsObject:m.localId]) continue;
            [out addObject:m];
        }
        return out;
    };

    shots = filterValidModels(shots);
    recs  = filterValidModels(recs);
    bigs  = filterValidModels(bigs);

    [existFR enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) [existIdSet addObject:obj.localIdentifier];
    }];

    
    // 1) flatten groups（你原来就有）
    NSArray<ASAssetModel *> *(^flattenGroups)(NSArray<ASAssetGroup *> *, ASGroupType) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetGroup *> *groups, ASGroupType type) {
        NSMutableArray *arr = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;
            // ✅ 小于2个不算分组（你新要求）
            // ✅ 小于2个不算分组（但这里要以“有效资产数”判断）
            NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                if (![existIdSet containsObject:m.localId]) continue; // ✅ 已删除的过滤掉
                [valid addObject:m];
            }
            if (valid.count < 2) continue;

            [arr addObjectsFromArray:valid];
        }
        [arr sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
            NSDate *da = a.creationDate ?: a.modificationDate;
            NSDate *db = b.creationDate ?: b.modificationDate;
            if (!da && !db) return NSOrderedSame;
            if (!da) return NSOrderedDescending;
            if (!db) return NSOrderedAscending;
            return [db compare:da];
        }];
        return arr;
    };

    // 只取“第一个有效分组(>=2)”的前两张；凑不齐两张就返回空
    NSArray<NSString *> *(^thumbsFromFirstValidGroup)(NSArray<ASAssetGroup *> *, ASGroupType) =
    ^NSArray<NSString *>* (NSArray<ASAssetGroup *> *groups, ASGroupType type) {

        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;
            NSInteger validCount = 0;
            for (ASAssetModel *m in g.assets) {
                if (m.localId.length && [existIdSet containsObject:m.localId]) validCount++;
            }
            if (validCount < 2) continue;

            NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:2];
            for (ASAssetModel *m in g.assets) {
                if (!m.localId.length) continue;
                if (![existIdSet containsObject:m.localId]) continue; //  加这一行
                [ids addObject:m.localId];
                if (ids.count == 2) break;
            }
            return (ids.count == 2) ? ids : @[]; //  不允许只返回1张
        }
        return @[];
    };

    NSArray<ASAssetModel *> *simImg = flattenGroups(sim, ASGroupTypeSimilarImage);
    NSArray<ASAssetModel *> *simVid = flattenGroups(sim, ASGroupTypeSimilarVideo);
    NSArray<ASAssetModel *> *dupImg = flattenGroups(dup, ASGroupTypeDuplicateImage);
    NSArray<ASAssetModel *> *dupVid = flattenGroups(dup, ASGroupTypeDuplicateVideo);

    // --- 3) 全局去重统计（总可清理：去重）
    NSMutableDictionary<NSString*, NSNumber*> *bytesById = [NSMutableDictionary dictionary];

    void (^collect)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr) {
        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
            if (![existIdSet containsObject:m.localId]) continue; // ✅ 加这一行
            if (!bytesById[m.localId]) bytesById[m.localId] = @(m.fileSizeBytes);
        }
    };

    collect(simImg); collect(simVid); collect(dupImg); collect(dupVid);
    collect(shots); collect(recs); collect(bigs);

    uint64_t uniqBytes = 0;
    for (NSNumber *n in bytesById.allValues) uniqBytes += n.unsignedLongLongValue;

    self.allCleanableIds = [NSSet setWithArray:bytesById.allKeys];
    self.allCleanableBytes = uniqBytes;

    // --- 4) 普通列表模块缩略图：跨模块去重（仅给 shots/recs/bigs 用）
    NSMutableSet<NSString *> *usedThumbIds = [NSMutableSet set];

    NSArray<NSString *> *(^pickThumbIds)(NSArray<ASAssetModel *> *) =
    ^NSArray<NSString *> *(NSArray<ASAssetModel *> *arr) {
        NSMutableArray *ids = [NSMutableArray array];

        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
            if (![existIdSet containsObject:m.localId]) continue;
            if ([usedThumbIds containsObject:m.localId]) continue;
            [usedThumbIds addObject:m.localId];
            [ids addObject:m.localId];
            if (ids.count == 2) return ids;
        }
        // 不够2张就不补（你也可以保留“补齐”逻辑）
        return ids;
    };

    // 5) VM builders
    ASHomeModuleVM *(^makeVM)(ASHomeModuleType, NSString *, NSArray<ASAssetModel *> *) =
    ^ASHomeModuleVM *(ASHomeModuleType type, NSString *title, NSArray<ASAssetModel *> *arr) {
        ASHomeModuleVM *vm = [ASHomeModuleVM new];
        vm.type = type;
        vm.title = title;

        uint64_t bytes = 0;
        for (ASAssetModel *m in arr) bytes += m.fileSizeBytes;
        vm.totalCount = arr.count;
        vm.totalBytes = bytes;

        vm.thumbLocalIds = pickThumbIds(arr);
        return vm;
    };

    ASHomeModuleVM *(^makeGroupVM)(ASHomeModuleType, NSString *, NSArray<ASAssetGroup *> *, ASGroupType, NSArray<ASAssetModel *> *) =
    ^ASHomeModuleVM *(ASHomeModuleType type, NSString *title, NSArray<ASAssetGroup *> *groups, ASGroupType gt, NSArray<ASAssetModel *> *flat) {
        ASHomeModuleVM *vm = [ASHomeModuleVM new];
        vm.type = type;
        vm.title = title;

        uint64_t bytes = 0;
        for (ASAssetModel *m in flat) bytes += m.fileSizeBytes;
        vm.totalCount = flat.count;
        vm.totalBytes = bytes;

        // ✅ 只看第一个分组：没有分组则空白
        vm.thumbLocalIds = thumbsFromFirstValidGroup(groups, gt);
        return vm;
    };

    return @[
        makeGroupVM(ASHomeModuleTypeSimilarImage,   @"相似图片", sim, ASGroupTypeSimilarImage,   simImg),
        makeGroupVM(ASHomeModuleTypeSimilarVideo,   @"相似视频", sim, ASGroupTypeSimilarVideo,   simVid),
        makeGroupVM(ASHomeModuleTypeDuplicateImage, @"重复图片", dup, ASGroupTypeDuplicateImage, dupImg),
        makeGroupVM(ASHomeModuleTypeDuplicateVideo, @"重复视频", dup, ASGroupTypeDuplicateVideo, dupVid),

        makeVM(ASHomeModuleTypeScreenshots,        @"截屏", shots),
        makeVM(ASHomeModuleTypeScreenRecordings,   @"录屏", recs),
        makeVM(ASHomeModuleTypeBigVideos,          @"大视频", bigs),
    ];
}

#pragma mark - Tap Module -> Push List

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item >= self.modules.count) return;
    ASHomeModuleVM *vm = self.modules[indexPath.item];

    ASAssetListMode mode;
    if (![self mapHomeModule:vm.type toListMode:&mode]) {
        return; // 没映射就不跳（理论上不会）
    }

    ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:mode];
    vc.hidesBottomBarWhenPushed = YES;   //隐藏底部 tabbar
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)mapHomeModule:(ASHomeModuleType)type toListMode:(ASAssetListMode *)outMode {
    if (!outMode) return NO;

    switch (type) {
        case ASHomeModuleTypeSimilarImage:      *outMode = ASAssetListModeSimilarImage; return YES;
        case ASHomeModuleTypeSimilarVideo:      *outMode = ASAssetListModeSimilarVideo; return YES;
        case ASHomeModuleTypeDuplicateImage:    *outMode = ASAssetListModeDuplicateImage; return YES;
        case ASHomeModuleTypeDuplicateVideo:    *outMode = ASAssetListModeDuplicateVideo; return YES;
        case ASHomeModuleTypeScreenshots:       *outMode = ASAssetListModeScreenshots; return YES;
        case ASHomeModuleTypeScreenRecordings:  *outMode = ASAssetListModeScreenRecordings; return YES;
        case ASHomeModuleTypeBigVideos:         *outMode = ASAssetListModeBigVideos; return YES;
    }
    return NO;
}


#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HomeModuleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeModuleCell" forIndexPath:indexPath];
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    [cell applyVM:vm];

    NSArray *ids = vm.thumbLocalIds ?: @[];
    cell.representedLocalIds = ids;

    if (ids.count < 2) {
        cell.img1.image = nil;
        cell.img2.image = nil;
        return cell;
    }

    [self loadThumbsForVM:vm intoCell:cell atIndexPath:indexPath];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat totalW = collectionView.bounds.size.width;
    CGFloat leftRight = 16 * 2;
    CGFloat gap = 12;
    CGFloat w = (totalW - leftRight - gap) / 2.0;
    return CGSizeMake(w, 180);
}

#pragma mark - Thumbnails

- (void)loadThumbsForVM:(ASHomeModuleVM *)vm intoCell:(HomeModuleCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (vm.thumbLocalIds.count < 2) {
         cell.img1.image = nil;
         cell.img2.image = nil;
         return;
     }

     PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:vm.thumbLocalIds options:nil];
     if (fr.count < 2) { // fetch 不足两张也当空
         cell.img1.image = nil;
         cell.img2.image = nil;
         return;
     }

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;

    // 兜底：如果此时 bounds 还没布局好，用 frame 或固定值
    CGSize s1 = cell.img1.bounds.size;
    CGSize s2 = cell.img2.bounds.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = cell.img1.frame.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = cell.img2.frame.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = CGSizeMake(80, 80);
    if (s2.width <= 1 || s2.height <= 1) s2 = CGSizeMake(80, 80);

    CGSize t1 = CGSizeMake(s1.width * scale, s1.height * scale);
    CGSize t2 = CGSizeMake(s2.width * scale, s2.height * scale);

    __weak typeof(self) weakSelf = self;

    void (^setImg)(NSInteger, UIImage *) = ^(NSInteger idx, UIImage *img) {
        dispatch_async(dispatch_get_main_queue(), ^{
            HomeModuleCell *nowCell = (HomeModuleCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            // 防复用：确保还是同一个模块的 localIds
            if (![nowCell.representedLocalIds isEqualToArray:vm.thumbLocalIds]) return;

            if (idx == 0) nowCell.img1.image = img;
            else nowCell.img2.image = img;
        });
    };

    PHAsset *a0 = fr.count > 0 ? [fr objectAtIndex:0] : nil;
    PHAsset *a1 = fr.count > 1 ? [fr objectAtIndex:1] : nil;

    if (a0) {
        [self.imgMgr requestImageForAsset:a0
                               targetSize:t1
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(0, result);
        }];
    }

    if (a1) {
        [self.imgMgr requestImageForAsset:a1
                               targetSize:t2
                              contentMode:PHImageContentModeAspectFill
                                  options:opt
                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(1, result);
        }];
    }
}

@end

NS_ASSUME_NONNULL_END
