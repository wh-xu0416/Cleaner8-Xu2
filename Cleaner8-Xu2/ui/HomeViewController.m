#import "HomeViewController.h"
#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"

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
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<ASHomeModuleVM *> *modules;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic, strong) UILabel *scanStateLabel; // 顶部实时状态
@end

@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"Home open, scan state = %lu", (unsigned long)self.scanMgr.snapshot.state);

    self.view.backgroundColor = UIColor.whiteColor;
    self.title = @"首页";

    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    [self setupUI];

    // 先载缓存 + 检查增量（杀死重启也能更新）
    [self.scanMgr loadCacheAndCheckIncremental];

    // 用缓存先刷一遍（立即显示）
    [self rebuildModulesFromManagerAndReload];

    // 请求权限并开始扫描（扫描期间实时更新总大小/总数量）
    [self requestPhotoPermissionThenStartScan];
}

- (void)startScanCallbacks {
    __weak typeof(self) weakSelf = self;

    // ✅ 如果上次已经扫完，有缓存，别再全量扫
    if (self.scanMgr.snapshot.state == ASScanStateFinished) {
        [weakSelf updateScanStateText:self.scanMgr.snapshot];
        // 这里你可以选择：只做增量检测（你 loadCacheAndCheckIncremental 已经做了）
        return;
    }

    [self.scanMgr startFullScanWithProgress:^(ASScanSnapshot *snapshot) {
        [weakSelf updateScanStateText:snapshot];
        [weakSelf rebuildModulesFromManagerAndReload];
    } completion:^(ASScanSnapshot *snapshot, NSError * _Nullable error) {
        [weakSelf updateScanStateText:snapshot];
        [weakSelf rebuildModulesFromManagerAndReload];
    }];
}


#pragma mark - UI

- (void)setupUI {
    self.scanStateLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 88, self.view.bounds.size.width - 32, 18)];
    self.scanStateLabel.font = [UIFont systemFontOfSize:13];
    self.scanStateLabel.textColor = [UIColor grayColor];
    [self.view addSubview:self.scanStateLabel];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(12, 16, 16, 16);

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 110, self.view.bounds.size.width, self.view.bounds.size.height - 110)
                                 collectionViewLayout:layout];
    self.cv.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1];
    self.cv.dataSource = self;
    self.cv.delegate = self;
    [self.cv registerClass:HomeModuleCell.class forCellWithReuseIdentifier:@"HomeModuleCell"];
    [self.view addSubview:self.cv];
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

    self.scanStateLabel.text = [NSString stringWithFormat:@"%@  已扫描:%lu  可清理:%lu",
                                state,
                                (unsigned long)s.scannedCount,
                                (unsigned long)s.cleanableCount];
}

#pragma mark - Build modules

- (void)rebuildModulesFromManagerAndReload {
    self.modules = [self buildModulesFromManager];
    [self.cv reloadData];
}

- (NSArray<ASHomeModuleVM *> *)buildModulesFromManager {
    // 分别统计 7 个模块
    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    NSArray<ASAssetModel *> *shots = self.scanMgr.screenshots ?: @[];
    NSArray<ASAssetModel *> *recs  = self.scanMgr.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigs  = self.scanMgr.bigVideos ?: @[];

    // 拍平组：按类型分
    NSArray<ASAssetModel *> *(^flattenGroups)(NSArray<ASAssetGroup *> *, ASGroupType) =
    ^NSArray<ASAssetModel *> *(NSArray<ASAssetGroup *> *groups, ASGroupType type) {
        NSMutableArray *arr = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            if (g.type != type) continue;
            [arr addObjectsFromArray:g.assets ?: @[]];
        }
        // 简单按创建时间倒序（如果 creationDate 为空就保持顺序）
        [arr sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
            if (!a.creationDate || !b.creationDate) return NSOrderedSame;
            return [b.creationDate compare:a.creationDate];
        }];
        return arr;
    };

    NSArray<ASAssetModel *> *simImg = flattenGroups(sim, ASGroupTypeSimilarImage);
    NSArray<ASAssetModel *> *simVid = flattenGroups(sim, ASGroupTypeSimilarVideo);
    NSArray<ASAssetModel *> *dupImg = flattenGroups(dup, ASGroupTypeDuplicateImage);
    NSArray<ASAssetModel *> *dupVid = flattenGroups(dup, ASGroupTypeDuplicateVideo);

    ASHomeModuleVM *(^makeVM)(ASHomeModuleType, NSString *, NSArray<ASAssetModel *> *) =
    ^ASHomeModuleVM *(ASHomeModuleType type, NSString *title, NSArray<ASAssetModel *> *arr) {
        ASHomeModuleVM *vm = [ASHomeModuleVM new];
        vm.type = type;
        vm.title = title;

        uint64_t bytes = 0;
        for (ASAssetModel *m in arr) bytes += m.fileSizeBytes;

        vm.totalCount = arr.count;
        vm.totalBytes = bytes;

        // 两张缩略图：取前两个
        NSMutableArray *ids = [NSMutableArray array];
        for (NSInteger i=0; i<MIN(2, (NSInteger)arr.count); i++) {
            ASAssetModel *m = arr[i];
            if (m.localId.length > 0) [ids addObject:m.localId];
        }
        vm.thumbLocalIds = ids;
        return vm;
    };

    return @[
        makeVM(ASHomeModuleTypeSimilarImage, @"相似图片", simImg),
        makeVM(ASHomeModuleTypeSimilarVideo, @"相似视频", simVid),
        makeVM(ASHomeModuleTypeDuplicateImage, @"重复图片", dupImg),
        makeVM(ASHomeModuleTypeDuplicateVideo, @"重复视频", dupVid),
        makeVM(ASHomeModuleTypeScreenshots, @"截屏", shots),
        makeVM(ASHomeModuleTypeScreenRecordings, @"录屏", recs),
        makeVM(ASHomeModuleTypeBigVideos, @">20MB 视频", bigs),
    ];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HomeModuleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeModuleCell" forIndexPath:indexPath];
    ASHomeModuleVM *vm = self.modules[indexPath.item];
    [cell applyVM:vm];

    // 两张缩略图
    cell.img1.image = nil;
    cell.img2.image = nil;
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
    if (vm.thumbLocalIds.count == 0) return;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:vm.thumbLocalIds options:nil];

    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    for (NSInteger i = 0; i < MIN(2, fr.count); i++) {
        [assets addObject:[fr objectAtIndex:i]];
    }
    if (assets.count == 0) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    CGSize target = CGSizeMake(160, 160);

    // 注意：异步回调要防止 cell 复用错位
    __weak typeof(self) weakSelf = self;

    void (^setImg)(NSInteger, UIImage *) = ^(NSInteger idx, UIImage *img) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 校验 indexPath 仍然可见且对应同一个模块
            NSArray<NSIndexPath *> *visible = [weakSelf.cv indexPathsForVisibleItems];
            if (![visible containsObject:indexPath]) return;

            HomeModuleCell *nowCell = (HomeModuleCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            if (idx == 0) nowCell.img1.image = img;
            else nowCell.img2.image = img;
        });
    };

    // 第 1 张
    [[PHImageManager defaultManager] requestImageForAsset:assets[0]
                                               targetSize:target
                                              contentMode:PHImageContentModeAspectFill
                                                  options:opt
                                            resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) setImg(0, result);
    }];

    // 第 2 张
    if (assets.count >= 2) {
        [[PHImageManager defaultManager] requestImageForAsset:assets[1]
                                                   targetSize:target
                                                  contentMode:PHImageContentModeAspectFill
                                                      options:opt
                                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(1, result);
        }];
    }
}

@end

NS_ASSUME_NONNULL_END
