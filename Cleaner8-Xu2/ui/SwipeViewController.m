#import "SwipeViewController.h"
#import "SwipeManager.h"
#import "SwipeAlbumViewController.h"
#import "ASArchivedFilesViewController.h"

@interface SwipeModuleCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *doneOverlay;
@end

@implementation SwipeModuleCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _countLabel.font = [UIFont boldSystemFontOfSize:13];
        _countLabel.textColor = UIColor.whiteColor;
        _countLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        _countLabel.layer.cornerRadius = 10;
        _countLabel.layer.masksToBounds = YES;
        _countLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_countLabel];

        _dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _dateLabel.textColor = UIColor.whiteColor;
        _dateLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        _dateLabel.layer.cornerRadius = 10;
        _dateLabel.layer.masksToBounds = YES;
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_dateLabel];

        _doneOverlay = [[UIView alloc] initWithFrame:CGRectZero];
        _doneOverlay.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
        _doneOverlay.hidden = YES;
        [self.contentView addSubview:_doneOverlay];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.frame = self.contentView.bounds;
    self.doneOverlay.frame = self.contentView.bounds;

    CGFloat pad = 8;
    self.countLabel.frame = CGRectMake(pad, pad, 56, 20);
    self.dateLabel.frame = CGRectMake(pad, CGRectGetHeight(self.contentView.bounds) - pad - 20, 100, 20);
}
@end

@interface SwipeViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UILabel *archivedLabel;
@property (nonatomic, strong) UIButton *archivedButton;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@end

@implementation SwipeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Swipe";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.imageManager = [[PHCachingImageManager alloc] init];

    [self buildUI];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUpdate) name:SwipeManagerDidUpdateNotification object:nil];

    __weak typeof(self) weakSelf = self;
    [[SwipeManager shared] requestAuthorizationAndLoadIfNeeded:^(BOOL granted) {
        if (!granted) {
            weakSelf.progressLabel.text = @"未获得相册权限";
        } else {
            [weakSelf handleUpdate];
        }
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    CGFloat topPad = 16;

    _progressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _progressLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _progressLabel.textColor = UIColor.labelColor;
    _progressLabel.numberOfLines = 2;
    [self.view addSubview:_progressLabel];

    _archivedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _archivedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _archivedLabel.textColor = UIColor.secondaryLabelColor;
    _archivedLabel.numberOfLines = 2;
    [self.view addSubview:_archivedLabel];

    _archivedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_archivedButton setTitle:@"已归档" forState:UIControlStateNormal];
    _archivedButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [_archivedButton addTarget:self action:@selector(openArchived) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_archivedButton];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = UIColor.clearColor;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.contentInset = UIEdgeInsetsMake(12, 16, 24, 16);
    [_collectionView registerClass:SwipeModuleCell.class forCellWithReuseIdentifier:@"SwipeModuleCell"];
    [self.view addSubview:_collectionView];

    // Layout
    CGFloat w = self.view.bounds.size.width;
    _progressLabel.frame = CGRectMake(16, self.view.safeAreaInsets.top + topPad, w - 32 - 90, 44);
    _archivedButton.frame = CGRectMake(w - 16 - 80, self.view.safeAreaInsets.top + topPad, 80, 36);
    _archivedLabel.frame = CGRectMake(16, CGRectGetMaxY(_progressLabel.frame) + 4, w - 32, 34);

    CGFloat y = CGRectGetMaxY(_archivedLabel.frame) + 8;
    _collectionView.frame = CGRectMake(0, y, w, self.view.bounds.size.height - y);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self buildUI];
}

- (void)handleUpdate {
    SwipeManager *mgr = [SwipeManager shared];
    NSUInteger total = [mgr totalAssetCount];
    NSUInteger processed = [mgr totalProcessedCount];
    NSUInteger archivedCount = [mgr totalArchivedCount];
    unsigned long long bytes = [mgr totalArchivedBytesCached];

    double percent = total > 0 ? (double)processed / (double)total : 0;
    self.progressLabel.text = [NSString stringWithFormat:@"总进度：%lu / %lu（%.0f%%）",
                               (unsigned long)processed, (unsigned long)total, percent * 100.0];

    self.archivedLabel.text = [NSString stringWithFormat:@"已归档：%lu 张 · %@（去重）",
                               (unsigned long)archivedCount, [self.class bytesToString:bytes]];

    [self.collectionView reloadData];

    // 可选：后台补齐归档大小（若你不想耗时可删掉这一段）
    [[SwipeManager shared] refreshArchivedBytesIfNeeded:^(unsigned long long newBytes) {
        self.archivedLabel.text = [NSString stringWithFormat:@"已归档：%lu 张 · %@（去重）",
                                   (unsigned long)[mgr totalArchivedCount], [self.class bytesToString:newBytes]];
    }];
}

+ (NSString *)bytesToString:(unsigned long long)bytes {
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb < 1024) return [NSString stringWithFormat:@"%.1fMB", mb];
    double gb = mb / 1024.0;
    return [NSString stringWithFormat:@"%.2fGB", gb];
}

- (void)openArchived {
    ASArchivedFilesViewController *vc = [ASArchivedFilesViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [SwipeManager shared].modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SwipeModuleCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"SwipeModuleCell" forIndexPath:indexPath];
    SwipeModule *m = [SwipeManager shared].modules[indexPath.item];

    cell.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)m.assetIDs.count];
    cell.dateLabel.text = m.subtitle ?: @"";
    cell.doneOverlay.hidden = ![[SwipeManager shared] isModuleCompleted:m];

    // 封面：模块最新一张（我们构造 assetIDs 默认是降序；若升序则取最后一张）
    NSString *coverID = nil;
    if (m.assetIDs.count > 0) {
        coverID = m.sortAscending ? m.assetIDs.lastObject : m.assetIDs.firstObject;
    }

    cell.imageView.image = nil;
    if (coverID) {
        PHAsset *asset = [[SwipeManager shared] assetForID:coverID];
        if (asset) {
            CGSize target = CGSizeMake(400, 400);
            PHImageRequestOptions *opt = [PHImageRequestOptions new];
            opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
            opt.resizeMode = PHImageRequestOptionsResizeModeFast;
            opt.networkAccessAllowed = YES;

            [self.imageManager requestImageForAsset:asset
                                         targetSize:target
                                        contentMode:PHImageContentModeAspectFill
                                            options:opt
                                      resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
                if (result) cell.imageView.image = result;
            }];
        }
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SwipeModule *m = [SwipeManager shared].modules[indexPath.item];
    SwipeAlbumViewController *vc = [[SwipeAlbumViewController alloc] initWithModule:m];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Layout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = collectionView.bounds.size.width - collectionView.contentInset.left - collectionView.contentInset.right;
    CGFloat itemW = (w - 12) / 2.0;
    return CGSizeMake(itemW, itemW * 1.1);
}

@end
