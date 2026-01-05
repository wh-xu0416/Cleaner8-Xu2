#import "ASArchivedFilesViewController.h"
#import "SwipeManager.h"

@interface ArchivedCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *selectedOverlay;
@end

@implementation ArchivedCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _selectedOverlay = [[UIView alloc] initWithFrame:CGRectZero];
        _selectedOverlay.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.25];
        _selectedOverlay.hidden = YES;
        [self.contentView addSubview:_selectedOverlay];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.contentView.bounds;
    _selectedOverlay.frame = self.contentView.bounds;
}
@end

@interface ASArchivedFilesViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *undoButton;

@property (nonatomic, strong) PHCachingImageManager *imageManager;

@property (nonatomic, strong) NSArray<NSString *> *archivedIDs;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIDs;
@end

@implementation ASArchivedFilesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已归档";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.imageManager = [PHCachingImageManager new];
    self.selectedIDs = [NSMutableSet set];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUpdate) name:SwipeManagerDidUpdateNotification object:nil];

    [self buildUI];
    [self handleUpdate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    _summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _summaryLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _summaryLabel.textColor = UIColor.labelColor;
    _summaryLabel.numberOfLines = 2;
    [self.view addSubview:_summaryLabel];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = UIColor.clearColor;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.allowsMultipleSelection = YES;
    _collectionView.contentInset = UIEdgeInsetsMake(12, 16, 16, 16);
    [_collectionView registerClass:ArchivedCell.class forCellWithReuseIdentifier:@"ArchivedCell"];
    [self.view addSubview:_collectionView];

    _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_deleteButton setTitle:@"删除" forState:UIControlStateNormal];
    _deleteButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_deleteButton];

    _undoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_undoButton setTitle:@"撤销" forState:UIControlStateNormal];
    _undoButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_undoButton addTarget:self action:@selector(undoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_undoButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat w = self.view.bounds.size.width;

    self.summaryLabel.frame = CGRectMake(16, safeTop + 10, w - 32, 44);

    CGFloat btnY = CGRectGetMaxY(self.summaryLabel.frame) + 4;
    self.undoButton.frame = CGRectMake(16, btnY, 90, 40);
    self.deleteButton.frame = CGRectMake(w - 16 - 90, btnY, 90, 40);

    CGFloat y = CGRectGetMaxY(self.undoButton.frame) + 6;
    self.collectionView.frame = CGRectMake(0, y, w, self.view.bounds.size.height - y);
}

- (void)handleUpdate {
    SwipeManager *mgr = [SwipeManager shared];
    self.archivedIDs = [[[mgr archivedAssetIDSet] allObjects] sortedArrayUsingSelector:@selector(compare:)];

    unsigned long long bytes = [mgr totalArchivedBytesCached];
    self.summaryLabel.text = [NSString stringWithFormat:@"已归档：%lu 张\n总大小：%@（去重）",
                              (unsigned long)self.archivedIDs.count, [self.class bytesToString:bytes]];

    // 清理已不存在的选择
    NSMutableSet *valid = [NSMutableSet setWithArray:self.archivedIDs];
    [self.selectedIDs intersectSet:valid];

    [self updateButtons];
    [self.collectionView reloadData];

    [[SwipeManager shared] refreshArchivedBytesIfNeeded:^(unsigned long long newBytes) {
        self.summaryLabel.text = [NSString stringWithFormat:@"已归档：%lu 张\n总大小：%@（去重）",
                                  (unsigned long)self.archivedIDs.count, [self.class bytesToString:newBytes]];
    }];
}

+ (NSString *)bytesToString:(unsigned long long)bytes {
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb < 1024) return [NSString stringWithFormat:@"%.1fMB", mb];
    double gb = mb / 1024.0;
    return [NSString stringWithFormat:@"%.2fGB", gb];
}

- (void)updateButtons {
    BOOL has = self.selectedIDs.count > 0;
    self.deleteButton.enabled = has;
    self.undoButton.enabled = has;
    self.deleteButton.alpha = has ? 1.0 : 0.4;
    self.undoButton.alpha = has ? 1.0 : 0.4;
}

#pragma mark - Actions

- (void)undoTapped {
    if (self.selectedIDs.count == 0) return;
    NSArray *ids = self.selectedIDs.allObjects;

    for (NSString *aid in ids) {
        [[SwipeManager shared] resetStatusForAssetID:aid sourceModule:nil recordUndo:NO];
    }
    [self.selectedIDs removeAllObjects];
    [self updateButtons];
    [self handleUpdate];
}

- (void)deleteTapped {
    if (self.selectedIDs.count == 0) return;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"删除"
                                                                message:@"确定要从系统相册删除选中的照片吗？此操作不可恢复。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSArray *ids = weakSelf.selectedIDs.allObjects;
        [[SwipeManager shared] deleteAssetsWithIDs:ids completion:^(BOOL success, NSError * _Nullable error) {
            [weakSelf.selectedIDs removeAllObjects];
            [weakSelf updateButtons];
            [weakSelf handleUpdate];
        }];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.archivedIDs.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ArchivedCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ArchivedCell" forIndexPath:indexPath];
    NSString *aid = self.archivedIDs[indexPath.item];

    cell.selectedOverlay.hidden = ![self.selectedIDs containsObject:aid];

    cell.imageView.image = nil;
    PHAsset *asset = [[SwipeManager shared] assetForID:aid];
    if (asset) {
        CGSize target = CGSizeMake(240, 240);
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
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *aid = self.archivedIDs[indexPath.item];
    [self.selectedIDs addObject:aid];
    [self updateButtons];
    [collectionView reloadItemsAtIndexPaths:@[indexPath]];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *aid = self.archivedIDs[indexPath.item];
    [self.selectedIDs removeObject:aid];
    [self updateButtons];
    [collectionView reloadItemsAtIndexPaths:@[indexPath]];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = collectionView.bounds.size.width - collectionView.contentInset.left - collectionView.contentInset.right;
    CGFloat itemW = (w - 24) / 3.0;
    return CGSizeMake(itemW, itemW);
}

@end
