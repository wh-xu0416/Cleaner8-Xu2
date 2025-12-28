#import "ASMyStudioViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVKit/AVKit.h>

#import "ASStudioStore.h"
#import "ASStudioCell.h"
#import "ASStudioUtils.h"
#import "ASTabSegmentView.h"

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }

@interface ASMyStudioViewController () <UITableViewDelegate, UITableViewDataSource, PHPhotoLibraryChangeObserver>

// UI
@property (nonatomic, strong) UIView *blueHeader;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIView *whiteCard;
@property (nonatomic, strong) ASTabSegmentView *tabs;

@property (nonatomic, strong) UITableView *table;

@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *limitedBtn;

// Data
@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) NSArray<ASStudioItem *> *data;
@property (nonatomic, assign) ASStudioMediaType currentType;

@end

@implementation ASMyStudioViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    self.imgMgr = [PHCachingImageManager new];
    self.data = @[];
    self.currentType = ASStudioMediaTypePhoto;

    [self buildUI];

    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    [self ensureAuthThenLoad];
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

#pragma mark - UI

- (void)buildUI {
    // 蓝色 header
    self.blueHeader = [UIView new];
    self.blueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.blueHeader.backgroundColor = ASBlue();
    [self.view addSubview:self.blueHeader];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.backBtn.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0,*)) [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    [self.blueHeader addSubview:self.backBtn];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"My studio";
    self.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.blueHeader addSubview:self.titleLabel];

    // 白色大圆角卡片容器
    self.whiteCard = [UIView new];
    self.whiteCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.whiteCard.backgroundColor = UIColor.whiteColor;
    self.whiteCard.layer.cornerRadius = 16;
    self.whiteCard.layer.masksToBounds = YES;
    [self.view addSubview:self.whiteCard];

    // tabs
    self.tabs = [ASTabSegmentView new];
    self.tabs.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabs.selectedIndex = 0;
    __weak typeof(self) weakSelf = self;
    self.tabs.onChange = ^(NSInteger idx) {
        weakSelf.currentType = (idx == 0) ? ASStudioMediaTypePhoto : ASStudioMediaTypeVideo;
        [weakSelf loadData];
    };
    [self.whiteCard addSubview:self.tabs];

    // table
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.backgroundColor = UIColor.whiteColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.rowHeight = 110;
    self.table.tableFooterView = [UIView new];
    [self.table registerClass:[ASStudioCell class] forCellReuseIdentifier:@"ASStudioCell"];
    [self.whiteCard addSubview:self.table];

    // empty
    self.emptyView = [UIView new];
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyView.backgroundColor = UIColor.whiteColor;
    [self.whiteCard addSubview:self.emptyView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.numberOfLines = 0;
    [self.emptyView addSubview:self.emptyLabel];

    self.limitedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.limitedBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.limitedBtn setTitle:@"Manage Limited Photos Access" forState:UIControlStateNormal];
    [self.limitedBtn addTarget:self action:@selector(onLimited:) forControlEvents:UIControlEventTouchUpInside];
    self.limitedBtn.hidden = YES;
    [self.emptyView addSubview:self.limitedBtn];

    // layout
    [NSLayoutConstraint activateConstraints:@[
        [self.blueHeader.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.blueHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.blueHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.blueHeader.leadingAnchor constant:18],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.blueHeader.safeAreaLayoutGuide.topAnchor constant:10],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.blueHeader.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.backBtn.centerYAnchor],

        [self.whiteCard.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:20],
        [self.blueHeader.bottomAnchor constraintEqualToAnchor:self.whiteCard.topAnchor constant:22],
        [self.whiteCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0],
        [self.whiteCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:0],
        [self.whiteCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:0],

        [self.tabs.topAnchor constraintEqualToAnchor:self.whiteCard.topAnchor constant:-5],
        [self.tabs.leadingAnchor constraintEqualToAnchor:self.whiteCard.leadingAnchor],
        [self.tabs.trailingAnchor constraintEqualToAnchor:self.whiteCard.trailingAnchor],
        [self.tabs.heightAnchor constraintEqualToConstant:62],

        [self.table.topAnchor constraintEqualToAnchor:self.tabs.bottomAnchor constant:6],
        [self.table.leadingAnchor constraintEqualToAnchor:self.whiteCard.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.whiteCard.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.whiteCard.bottomAnchor],

        [self.emptyView.topAnchor constraintEqualToAnchor:self.table.topAnchor],
        [self.emptyView.leadingAnchor constraintEqualToAnchor:self.whiteCard.leadingAnchor],
        [self.emptyView.trailingAnchor constraintEqualToAnchor:self.whiteCard.trailingAnchor],
        [self.emptyView.bottomAnchor constraintEqualToAnchor:self.whiteCard.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.emptyView.centerYAnchor constant:-20],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.emptyView.leadingAnchor constant:20],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.emptyView.trailingAnchor constant:-20],

        [self.limitedBtn.topAnchor constraintEqualToAnchor:self.emptyLabel.bottomAnchor constant:14],
        [self.limitedBtn.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
    ]];

    self.emptyView.hidden = YES;
}

- (void)onBack {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Auth

- (void)ensureAuthThenLoad {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (st == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self refreshUIForAuth:status];
                    [self loadData];
                });
            }];
            return;
        }
        [self refreshUIForAuth:st];
        [self loadData];
    } else {
        PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatus];
        if (st == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self refreshUIForAuth:status];
                    [self loadData];
                });
            }];
            return;
        }
        [self refreshUIForAuth:st];
        [self loadData];
    }
}

- (void)refreshUIForAuth:(PHAuthorizationStatus)st {
    BOOL canRead = (st == PHAuthorizationStatusAuthorized) || (st == PHAuthorizationStatusLimited);
    self.limitedBtn.hidden = !(st == PHAuthorizationStatusLimited);

    if (!canRead) {
        self.table.hidden = YES;
        self.emptyView.hidden = NO;
        self.emptyLabel.text = @"Photos access is required.\nPlease enable Photos permission in Settings.";
        return;
    }

    self.table.hidden = NO;
    // emptyView 在 reload 时决定
}

- (void)onLimited:(id)sender {
    if (@available(iOS 14, *)) {
        [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:self];
    }
}

#pragma mark - Data

- (void)loadData {
    self.data = [[ASStudioStore shared] itemsForType:self.currentType] ?: @[];
    [self syncCleanupForMissingAssetsThenReload];
}

- (void)syncCleanupForMissingAssetsThenReload {
    NSArray<ASStudioItem *> *all = [[ASStudioStore shared] allItems] ?: @[];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (ASStudioItem *it in all) {
        if (it.assetId.length > 0) [ids addObject:it.assetId];
    }

    if (ids.count > 0) {
        PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
        NSMutableSet<NSString *> *existing = [NSMutableSet setWithCapacity:r.count];
        [r enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [existing addObject:obj.localIdentifier];
        }];
        [[ASStudioStore shared] removeItemsNotInAssetIdSet:existing];
    }

    self.data = [[ASStudioStore shared] itemsForType:self.currentType] ?: @[];
    [self.table reloadData];

    // empty state
    PHAuthorizationStatus st;
    if (@available(iOS 14.0,*)) st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    else st = [PHPhotoLibrary authorizationStatus];

    BOOL canRead = (st == PHAuthorizationStatusAuthorized) || (st == PHAuthorizationStatusLimited);
    if (!canRead) return;

    BOOL has = (self.data.count > 0);
    self.emptyView.hidden = has;
    if (!has) {
        self.emptyLabel.text = (self.currentType == ASStudioMediaTypePhoto)
        ? @"No photos yet.\nCompress photos to see them here."
        : @"No videos yet.\nCompress videos to see them here.";
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.data.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    ASStudioCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ASStudioCell" forIndexPath:ip];
    ASStudioItem *it = self.data[ip.row];

    // 统一 item：只改文件名
    cell.nameLabel.text = it.displayName.length ? it.displayName : @"(Unnamed)";

    NSString *sizeText = [ASStudioUtils humanBytes:it.afterBytes];
    if (it.type == ASStudioMediaTypeVideo) {
        NSString *dur = [ASStudioUtils formatDuration:it.duration];
        cell.metaLabel.text = [NSString stringWithFormat:@"%@ • %@", sizeText, dur];
    } else {
        cell.metaLabel.text = sizeText;
    }
    cell.dateLabel.text = [ASStudioUtils formatDateYMD:it.compressedAt];

    [cell showVideoBadge:(it.type == ASStudioMediaTypeVideo)];

    // delete
    cell.deleteButton.tag = ip.row;
    [cell.deleteButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.deleteButton addTarget:self action:@selector(onDelete:) forControlEvents:UIControlEventTouchUpInside];

    // thumb
    cell.thumbView.image = nil;
    if (it.assetId.length > 0) {
        PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[it.assetId] options:nil];
        PHAsset *asset = r.firstObject;
        if (asset) {
            CGFloat scale = UIScreen.mainScreen.scale;
            CGSize target = CGSizeMake(70 * scale, 70 * scale);

            PHImageRequestOptions *opt = [PHImageRequestOptions new];
            opt.networkAccessAllowed = YES;
            opt.resizeMode = PHImageRequestOptionsResizeModeFast;
            opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

            [self.imgMgr requestImageForAsset:asset
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFill
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
                if (!result) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    ASStudioCell *updateCell = (ASStudioCell *)[tableView cellForRowAtIndexPath:ip];
                    if (updateCell) updateCell.thumbView.image = result;
                });
            }];
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    ASStudioItem *it = self.data[ip.row];
    if (it.assetId.length == 0) return;

    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[it.assetId] options:nil];
    PHAsset *asset = r.firstObject;
    if (!asset) return;

    if (it.type == ASStudioMediaTypePhoto) [self previewPhotoAsset:asset];
    else [self previewVideoAsset:asset];
}

#pragma mark - Preview

- (void)previewPhotoAsset:(PHAsset *)asset {
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    CGSize target = CGSizeMake(asset.pixelWidth, asset.pixelHeight);
    [self.imgMgr requestImageForAsset:asset
                           targetSize:target
                          contentMode:PHImageContentModeAspectFit
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = [UIViewController new];
            vc.view.backgroundColor = UIColor.blackColor;

            UIImageView *iv = [[UIImageView alloc] initWithImage:result];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.frame = vc.view.bounds;
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [vc.view addSubview:iv];

            [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)previewVideoAsset:(PHAsset *)asset {
    PHVideoRequestOptions *opt = [PHVideoRequestOptions new];
    opt.networkAccessAllowed = YES;

    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:opt resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if (!avAsset) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            AVPlayerViewController *pvc = [AVPlayerViewController new];
            pvc.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:avAsset]];
            [self presentViewController:pvc animated:YES completion:^{
                [pvc.player play];
            }];
        });
    }];
}

#pragma mark - Delete

- (void)onDelete:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= self.data.count) return;

    ASStudioItem *it = self.data[idx];

    NSString *title = (it.type == ASStudioMediaTypePhoto)
    ? @"Are you sure you want to delete this image?"
    : @"Are you sure you want to delete this video?";

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Confirm Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteItem:it];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)deleteItem:(ASStudioItem *)it {
    if (it.assetId.length == 0) return;

    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[it.assetId] options:nil];
    PHAsset *asset = r.firstObject;
    if (!asset) {
        [[ASStudioStore shared] removeByAssetId:it.assetId];
        [self loadData];
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:@[asset]];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [[ASStudioStore shared] removeByAssetId:it.assetId];
                [self loadData];
            } else {
                UIAlertController *ac =
                [UIAlertController alertControllerWithTitle:@"Delete failed"
                                                    message:error.localizedDescription ?: @""
                                             preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:ac animated:YES completion:nil];
            }
        });
    }];
}

#pragma mark - Photo library changes

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncCleanupForMissingAssetsThenReload];
    });
}

@end
