#import "PrivateListViewController.h"
#import "UIViewController+ASPrivateBackground.h"
#import "UIViewController+ASRootNav.h"
#import "ASColors.h"
#import "ASCustomNavBar.h"
#import "PrivateMediaCell.h"
#import "ASPrivateMediaStore.h"
#import "Common.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import "ASMediaPreviewViewController.h"

static inline UIColor *ASHexBlack(void) {
    return [UIColor colorWithRed:0 green:0 blue:0 alpha:1.0];
}

@interface PrivateListViewController () <UICollectionViewDelegate, UICollectionViewDataSource, PHPickerViewControllerDelegate>
@property (nonatomic, strong) ASCustomNavBar *navBar;

@property (nonatomic, assign) NSInteger pendingBatchUpdates;
@property (nonatomic, assign) BOOL importNeedsReload;

@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *selectAllButton;
@property (nonatomic, strong) UIImageView *selectIconView;
@property (nonatomic, strong) UILabel *selectTextLabel;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIButton *bottomBtn;

@property (nonatomic, strong) NSMutableArray<NSURL *> *items;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPaths;

@property (nonatomic, assign) BOOL allSelected;

@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyTextLabel;

@property (nonatomic, strong) NSCache<NSString*, UIImage*> *thumbCache;
@property (nonatomic, strong) dispatch_queue_t thumbQueue;
@property (nonatomic, strong) NSOperationQueue *thumbOpQ;

@end

@implementation PrivateListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.items = [NSMutableArray array];
    self.selectedPaths = [NSMutableSet set];

    self.thumbOpQ = [NSOperationQueue new];
    self.thumbOpQ.maxConcurrentOperationCount = 2;
    self.thumbOpQ.qualityOfService = NSQualityOfServiceUserInitiated;

    self.thumbCache = [NSCache new];
    self.thumbCache.countLimit = 500;
    self.thumbQueue = dispatch_queue_create("as.private.thumb", DISPATCH_QUEUE_CONCURRENT);

    [self as_applyPrivateBackground];

    [self buildUI];
    [self reloadItems];
}

- (UIImage *)thumbForImageURL:(NSURL *)url maxPixel:(CGFloat)maxPixel {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;

    NSDictionary *opt = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel),
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
    CFRelease(src);
    if (!cg) return nil;

    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

- (UIImage *)thumbForVideoURL:(NSURL *)url maxPixel:(CGFloat)maxPixel {
    AVAsset *asset = [AVAsset assetWithURL:url];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(maxPixel, maxPixel);

    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0, 600) actualTime:NULL error:nil];
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self as_updatePrivateBackgroundLayout];

    UICollectionViewFlowLayout *lay = (UICollectionViewFlowLayout *)self.cv.collectionViewLayout;
    CGFloat w = self.cv.bounds.size.width;
    CGFloat item = floor((w - 2*3) / 4.0);
    lay.itemSize = CGSizeMake(item, item);
    
    CGFloat bottomInset = 70 + self.view.safeAreaInsets.bottom;

    self.cv.contentInset = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    self.cv.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);

    [self.view bringSubviewToFront:self.bottomBtn];
}

- (void)buildUI {
    __weak typeof(self) ws = self;
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    self.navBar = [[ASCustomNavBar alloc] initWithTitle:self.navTitleText ?: NSLocalizedString(@"Secret", nil)];
    self.navBar.translatesAutoresizingMaskIntoConstraints = NO;

    self.navBar.onBack = ^{
        UINavigationController *nav = [ws as_rootNav];
        if (![nav isKindOfClass:UINavigationController.class]) return;
        [nav popViewControllerAnimated:YES];
    };

    self.navBar.showRightButton = YES;
    self.navBar.onRight = ^(BOOL allSelected) {
        UINavigationController *nav = [ws as_rootNav];
        if (![nav isKindOfClass:UINavigationController.class]) return;
        [nav popToRootViewControllerAnimated:YES];
    };

    [self.view addSubview:self.navBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.navBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.navBar.heightAnchor constraintEqualToConstant:88],
    ]];

    self.countLabel = [UILabel new];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.textColor = UIColor.blackColor;
    self.countLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [self.view addSubview:self.countLabel];

    self.selectAllButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectAllButton.backgroundColor = UIColor.whiteColor;
    self.selectAllButton.layer.cornerRadius = 18;
    self.selectAllButton.layer.masksToBounds = YES;
    self.selectAllButton.adjustsImageWhenHighlighted = NO;
    self.selectAllButton.showsTouchWhenHighlighted = NO;
    [self.selectAllButton addTarget:self action:@selector(selectAllTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.selectAllButton];

    self.selectIconView = [UIImageView new];
    self.selectIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectIconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.selectAllButton addSubview:self.selectIconView];

    self.selectTextLabel = [UILabel new];
    self.selectTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.selectTextLabel.textColor = ASHexBlack();
    [self.selectAllButton addSubview:self.selectTextLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.countLabel.topAnchor constraintEqualToAnchor:self.navBar.bottomAnchor constant:25],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [self.selectAllButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.selectAllButton.centerYAnchor constraintEqualToAnchor:self.countLabel.centerYAnchor],
        [self.selectAllButton.heightAnchor constraintEqualToConstant:36],

        [self.selectIconView.leadingAnchor constraintEqualToAnchor:self.selectAllButton.leadingAnchor constant:6],
        [self.selectIconView.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],
        [self.selectIconView.widthAnchor constraintEqualToConstant:24],
        [self.selectIconView.heightAnchor constraintEqualToConstant:24],

        [self.selectTextLabel.leadingAnchor constraintEqualToAnchor:self.selectIconView.trailingAnchor constant:6],
        [self.selectTextLabel.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],
        [self.selectTextLabel.trailingAnchor constraintEqualToAnchor:self.selectAllButton.trailingAnchor constant:-15],

        [self.selectAllButton.widthAnchor constraintGreaterThanOrEqualToConstant:36],

        [self.countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectAllButton.leadingAnchor constant:-12],
    ]];

    UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
    lay.minimumInteritemSpacing = 2;
    lay.minimumLineSpacing = 2;
    lay.sectionInset = UIEdgeInsetsZero;

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
    self.cv.translatesAutoresizingMaskIntoConstraints = NO;
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.delegate = self;
    self.cv.dataSource = self;
    self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.cv registerClass:PrivateMediaCell.class forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:self.cv];

    self.bottomBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bottomBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBtn.backgroundColor = ASBlue();
    self.bottomBtn.layer.cornerRadius = 35;
    self.bottomBtn.layer.masksToBounds = YES;
    self.bottomBtn.contentEdgeInsets = UIEdgeInsetsMake(23, 15, 23, 15);
    self.bottomBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    [self.bottomBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.bottomBtn addTarget:self action:@selector(bottomTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.bottomBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.bottomBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.bottomBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:0],
        [self.bottomBtn.heightAnchor constraintEqualToConstant:70],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.cv.topAnchor constraintEqualToAnchor:self.selectAllButton.bottomAnchor constant:10],
        [self.cv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.cv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.cv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    
    self.emptyView = [UIView new];
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyImageView = [UIImageView new];
    self.emptyImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyImageView.image = [[UIImage imageNamed:@"ic_empty_photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.emptyView addSubview:self.emptyImageView];

    self.emptyTextLabel = [UILabel new];
    self.emptyTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyTextLabel.text = NSLocalizedString(@"No Content", nil);
    self.emptyTextLabel.textColor = UIColor.blackColor;
    self.emptyTextLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightMedium];
    self.emptyTextLabel.textAlignment = NSTextAlignmentCenter;
    [self.emptyView addSubview:self.emptyTextLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-10],

        [self.emptyImageView.topAnchor constraintEqualToAnchor:self.emptyView.topAnchor],
        [self.emptyImageView.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [self.emptyImageView.widthAnchor constraintEqualToConstant:182],
        [self.emptyImageView.heightAnchor constraintEqualToConstant:168],

        [self.emptyTextLabel.topAnchor constraintEqualToAnchor:self.emptyImageView.bottomAnchor constant:2],
        [self.emptyTextLabel.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [self.emptyTextLabel.bottomAnchor constraintEqualToAnchor:self.emptyView.bottomAnchor],
    ]];

    [self updateSelectAllUI];
    [self updateBottomTitle];
}

- (void)updateEmptyStateUI {
    BOOL empty = (self.items.count == 0);

    self.countLabel.hidden = empty;
    self.selectAllButton.hidden = empty;
    self.emptyView.hidden = !empty;

    if (empty) {
        self.allSelected = NO;
        [self.selectedPaths removeAllObjects];
        [self updateSelectAllUI];
        [self updateBottomTitle];
    }
}

#pragma mark - Data

- (void)reloadItems {
    NSArray<NSURL *> *arr = [[ASPrivateMediaStore shared] allItems:self.mediaType];
    [self.items removeAllObjects];
    [self.items addObjectsFromArray:arr];

    NSString *suffix = (self.mediaType == ASPrivateMediaTypePhoto) ? NSLocalizedString(@"Photos", nil) : NSLocalizedString(@"Videos", nil);
    self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.items.count, suffix];

    // 修正 selected
    NSMutableSet *valid = [NSMutableSet set];
    for (NSURL *u in self.items) { [valid addObject:u.path ?: @""]; }
    [self.selectedPaths intersectSet:valid];

    self.allSelected = (self.items.count > 0 && self.selectedPaths.count == self.items.count);

    [self updateSelectAllUI];
    [self.cv reloadData];
    [self updateBottomTitle];
    [self updateEmptyStateUI];
}

#pragma mark - Select All UI

- (void)selectAllTap {
    if (self.items.count == 0) return;

    self.allSelected = !self.allSelected;

    [self.selectedPaths removeAllObjects];
    if (self.allSelected) {
        for (NSURL *u in self.items) {
            if (u.path.length) [self.selectedPaths addObject:u.path];
        }
    }

    [self updateSelectAllUI];
    [self updateBottomTitle];

    for (NSIndexPath *ip in self.cv.indexPathsForVisibleItems) {
        if (ip.item >= self.items.count) continue;
        PrivateMediaCell *cell = (PrivateMediaCell *)[self.cv cellForItemAtIndexPath:ip];
        NSURL *u = self.items[ip.item];
        [cell setSelectedMark:[self.selectedPaths containsObject:(u.path ?: @"")]];
    }
}

- (void)updateSelectAllUI {
    NSString *iconName = self.allSelected ? @"ic_select_s" : @"ic_select_gray_n";
    NSString *text     = self.allSelected ? NSLocalizedString(@"Deselect All", nil) : NSLocalizedString(@"Select All", nil);

    self.selectIconView.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.selectTextLabel.text = text;

    self.selectAllButton.alpha = (self.items.count == 0) ? 0.4 : 1.0;
    self.selectAllButton.userInteractionEnabled = (self.items.count != 0);
}

#pragma mark - Bottom Title

- (void)updateBottomTitle {
    if (self.selectedPaths.count > 0) {
        [self.bottomBtn setTitle:NSLocalizedString(@"Delete", nil) forState:UIControlStateNormal];
    } else {
        NSString *t = (self.mediaType == ASPrivateMediaTypePhoto) ? NSLocalizedString(@"Add Photos", nil) : NSLocalizedString(@"Add Videos", nil);
        [self.bottomBtn setTitle:t forState:UIControlStateNormal];
    }
}

- (NSArray<NSURL *> *)selectedURLs {
    if (self.selectedPaths.count == 0) return @[];
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    for (NSURL *u in self.items) {
        if ([self.selectedPaths containsObject:(u.path ?: @"")]) {
            [out addObject:u];
        }
    }
    return out;
}

#pragma mark - Permission

- (BOOL)canImportFromLibrary {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus s =
        [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        return (s == PHAuthorizationStatusAuthorized || s == PHAuthorizationStatusLimited);
    } else {
        return ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized);
    }
}

- (void)handlePermissionCTA {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus s =
        [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (s == PHAuthorizationStatusLimited) {
            [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:self];
            return;
        }
    }
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)ensurePhotoAuthThen:(void(^)(BOOL ok))completion {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (s == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL ok = (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
                    completion(ok);
                });
            }];
            return;
        }
        BOOL ok = (s == PHAuthorizationStatusAuthorized || s == PHAuthorizationStatusLimited);
        completion(ok);
    } else {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatus];
        if (s == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(status == PHAuthorizationStatusAuthorized);
                });
            }];
            return;
        }
        completion(s == PHAuthorizationStatusAuthorized);
    }
}

#pragma mark - Bottom Action

- (void)bottomTap {
    // Delete mode
    if (self.selectedPaths.count > 0) {
        NSArray<NSURL *> *toDelete = [self selectedURLs];
        if (toDelete.count == 0) return;

        // 1) 先删文件
        [[ASPrivateMediaStore shared] deleteItems:toDelete];

        // 2) 计算要删的 index
        NSMutableIndexSet *rm = [NSMutableIndexSet indexSet];
        [self.items enumerateObjectsUsingBlock:^(NSURL *obj, NSUInteger idx, BOOL *stop) {
            if ([self.selectedPaths containsObject:(obj.path ?: @"")]) [rm addIndex:idx];
        }];
        if (rm.count == 0) return;

        NSMutableArray<NSIndexPath *> *ips = [NSMutableArray array];
        [rm enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            [ips addObject:[NSIndexPath indexPathForItem:idx inSection:0]];
        }];

        // 3) 更新 UI：只在 batchUpdates 里改数据源一次
        [self.cv performBatchUpdates:^{
            [self.items removeObjectsAtIndexes:rm];
            [self.cv deleteItemsAtIndexPaths:ips];
        } completion:^(BOOL finished) {
            [self.selectedPaths removeAllObjects];
            self.allSelected = NO;

            NSString *suffix = (self.mediaType == ASPrivateMediaTypePhoto) ? NSLocalizedString(@"Photos", nil) : NSLocalizedString(@"Videos", nil);
            self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.items.count, suffix];

            [self updateSelectAllUI];
            [self updateBottomTitle];
            [self updateEmptyStateUI];
        }];

        return;
    }

    // Add mode
    [self ensurePhotoAuthThen:^(BOOL ok) {
        if (!ok) { [self handlePermissionCTA]; return; }
        [self presentPicker];
    }];
}

- (void)presentPicker {
    fprintf(stderr, " presentPicker called\n");

    PHPickerConfiguration *cfg =
    [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    cfg.selectionLimit = 0;
    if (@available(iOS 14, *)) {
        cfg.filter = (self.mediaType == ASPrivateMediaTypePhoto) ? PHPickerFilter.imagesFilter : PHPickerFilter.videosFilter;
    }
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - PHPickerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    fprintf(stderr, " didFinishPicking count=%lu\n", (unsigned long)results.count);

    __weak typeof(self) ws = self;

    NSArray<PHPickerResult *> *picked = [results copy];

    [picker dismissViewControllerAnimated:YES completion:^{
        if (picked.count == 0) return;

        [[ASPrivateMediaStore shared] importFromPickerResults:picked
                                                        type:ws.mediaType
                                                   onOneDone:^(NSURL * _Nullable dstURL, BOOL ok) {
            if (!ok || !dstURL) return;

            dispatch_async(dispatch_get_main_queue(), ^{
                NSUInteger insertIndex = ws.items.count;
                NSIndexPath *ip = [NSIndexPath indexPathForItem:insertIndex inSection:0];

                ws.pendingBatchUpdates += 1;
                [ws.cv performBatchUpdates:^{
                    [ws.items addObject:dstURL];
                    [ws.cv insertItemsAtIndexPaths:@[ip]];
                } completion:^(BOOL finished) {
                    ws.pendingBatchUpdates -= 1;
                    if (ws.importNeedsReload && ws.pendingBatchUpdates == 0) {
                        ws.importNeedsReload = NO;
                        [ws reloadItems];
                    }
                }];

                NSString *suffix = (ws.mediaType == ASPrivateMediaTypePhoto) ? NSLocalizedString(@"Photos", nil) : NSLocalizedString(@"Videos", nil);
                ws.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)ws.items.count, suffix];
                [ws updateEmptyStateUI];
                [ws updateBottomTitle];
                [ws updateSelectAllUI];
            });

        } completion:^(BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ws.importNeedsReload = YES;
                if (ws.pendingBatchUpdates == 0) {
                    ws.importNeedsReload = NO;
                    [ws reloadItems];
                }
            });
        }];
    }];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PrivateMediaCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];

    NSURL *u = self.items[indexPath.item];
    NSString *rid = u.path ?: @"";
    cell.representedId = rid;

    BOOL sel = [self.selectedPaths containsObject:rid];
    [cell setSelectedMark:sel];

    __weak typeof(self) ws = self;
    __weak typeof(cell) weakCell = cell;
    cell.onTapCheck = ^{
        NSIndexPath *ip = [ws.cv indexPathForCell:weakCell];
        if (!ip) return;
        [ws toggleSelectForURL:u atIndexPath:ip];
    };

    cell.thumb.image = nil;

    // maxPixel 按 cell 大小*scale
    CGSize s = ((UICollectionViewFlowLayout *)collectionView.collectionViewLayout).itemSize;
    CGFloat maxPixel = MAX(s.width, s.height) * UIScreen.mainScreen.scale;

    UIImage *cached = [self.thumbCache objectForKey:rid];
    if (cached) {
        cell.thumb.image = cached;
        return cell;
    }


    dispatch_async(self.thumbQueue, ^{
        NSIndexPath *reqIP = indexPath;
        NSString *reqId = rid;

        [self.thumbOpQ addOperationWithBlock:^{
            BOOL isVideo = (ws.mediaType == ASPrivateMediaTypeVideo);
            UIImage *img = isVideo ? [ws thumbForVideoURL:u maxPixel:maxPixel]
                                   : [ws thumbForImageURL:u maxPixel:maxPixel];
            if (!img) return;

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [ws.thumbCache setObject:img forKey:reqId];

                PrivateMediaCell *c = (PrivateMediaCell *)[ws.cv cellForItemAtIndexPath:reqIP];
                if (![c isKindOfClass:PrivateMediaCell.class]) return;
                if (![c.representedId isEqualToString:reqId]) return;
                c.thumb.image = img;
            }];
        }];
    });

    return cell;
}

- (void)toggleSelectForURL:(NSURL *)url atIndexPath:(NSIndexPath *)indexPath {
    NSString *key = url.path ?: @"";
    if ([self.selectedPaths containsObject:key]) [self.selectedPaths removeObject:key];
    else [self.selectedPaths addObject:key];

    self.allSelected = (self.items.count > 0 && self.selectedPaths.count == self.items.count);
    [self updateSelectAllUI];
    [self updateBottomTitle];

    PrivateMediaCell *cell = (PrivateMediaCell *)[self.cv cellForItemAtIndexPath:indexPath];
    if (cell) [cell setSelectedMark:[self.selectedPaths containsObject:key]];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item >= self.items.count) return;

    NSMutableIndexSet *idxs = [NSMutableIndexSet indexSet];
    [self.items enumerateObjectsUsingBlock:^(NSURL *obj, NSUInteger idx, BOOL *stop) {
        if ([self.selectedPaths containsObject:obj.path ?: @""]) [idxs addIndex:idx];
    }];

    ASMediaPreviewViewController *vc =
    [[ASMediaPreviewViewController alloc] initWithFileURLs:self.items
                                              initialIndex:indexPath.item
                                           selectedIndexes:idxs];

    __weak typeof(self) ws = self;
    vc.onSelectionChanged = ^(NSIndexSet *selectedIndexes) {
        [ws.selectedPaths removeAllObjects];
        [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            if (idx < ws.items.count) [ws.selectedPaths addObject:(ws.items[idx].path ?: @"")];
        }];

        ws.allSelected = (ws.items.count > 0 && ws.selectedPaths.count == ws.items.count);
        [ws updateSelectAllUI];
        [ws updateBottomTitle];

        for (NSIndexPath *ip in ws.cv.indexPathsForVisibleItems) {
            PrivateMediaCell *cell = (PrivateMediaCell *)[ws.cv cellForItemAtIndexPath:ip];
            if (!cell) continue;
            NSURL *u = ws.items[ip.item];
            [cell setSelectedMark:[ws.selectedPaths containsObject:(u.path ?: @"")]];
        }
    };

    UINavigationController *nav = [self as_rootNav];
    if (![nav isKindOfClass:UINavigationController.class]) return;
    [nav pushViewController:vc animated:YES];
}

@end
