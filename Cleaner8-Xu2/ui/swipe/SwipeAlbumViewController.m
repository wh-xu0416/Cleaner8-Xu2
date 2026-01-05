#import "SwipeAlbumViewController.h"
#import "SwipeManager.h"

@interface SwipeThumbCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *processedOverlay;
@end

@implementation SwipeThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 10;
        self.contentView.layer.masksToBounds = YES;

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _processedOverlay = [[UIView alloc] initWithFrame:CGRectZero];
        _processedOverlay.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
        _processedOverlay.hidden = YES;
        [self.contentView addSubview:_processedOverlay];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.contentView.bounds;
    _processedOverlay.frame = self.contentView.bounds;
}
@end

#pragma mark - Card View (private)

@interface SwipeCardView : UIView
@property (nonatomic, copy) NSString *assetID;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation SwipeCardView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 18;
        self.layer.masksToBounds = YES;
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];

        _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hintLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        _hintLabel.textColor = UIColor.whiteColor;
        _hintLabel.alpha = 0;
        [self addSubview:_hintLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    _hintLabel.frame = CGRectMake(16, 16, self.bounds.size.width - 32, 30);
}
@end

#pragma mark - SwipeAlbumViewController

@interface SwipeAlbumViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) SwipeModule *module;

@property (nonatomic, strong) UILabel *topLabel;
@property (nonatomic, strong) UILabel *progressLabel;

@property (nonatomic, strong) UIView *cardContainer;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *sortButton;

@property (nonatomic, strong) UICollectionView *thumbs;

@property (nonatomic, strong) PHCachingImageManager *imageManager;

@property (nonatomic, strong) NSArray<NSString *> *allAssetIDs;
@property (nonatomic, strong) NSMutableArray<NSString *> *unprocessedIDs;

@property (nonatomic, copy, nullable) NSString *focusAssetID;

@property (nonatomic, strong) NSMutableArray<SwipeCardView *> *cards; // 0=top
@end

@implementation SwipeAlbumViewController

- (instancetype)initWithModule:(SwipeModule *)module {
    if ((self = [super init])) {
        _module = module;
        _imageManager = [PHCachingImageManager new];
        _cards = [NSMutableArray array];
        _unprocessedIDs = [NSMutableArray array];
    }
    return self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    NSString *top = self.unprocessedIDs.firstObject;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:top forModuleID:self.module.moduleID];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.module.title ?: @"相册";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUpdate) name:SwipeManagerDidUpdateNotification object:nil];

    [self buildUI];
    [self reloadFromManagerAndRender];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    _topLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _topLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _topLabel.textColor = UIColor.labelColor;
    [self.view addSubview:_topLabel];

    _progressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _progressLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _progressLabel.textColor = UIColor.secondaryLabelColor;
    _progressLabel.numberOfLines = 2;
    [self.view addSubview:_progressLabel];

    _cardContainer = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_cardContainer];

    _undoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_undoButton setTitle:@"撤回" forState:UIControlStateNormal];
    _undoButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_undoButton addTarget:self action:@selector(undoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_undoButton];

    _sortButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_sortButton setTitle:@"排序：↓" forState:UIControlStateNormal];
    _sortButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_sortButton addTarget:self action:@selector(sortTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sortButton];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);

    _thumbs = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _thumbs.backgroundColor = UIColor.clearColor;
    _thumbs.dataSource = self;
    _thumbs.delegate = self;
    _thumbs.showsHorizontalScrollIndicator = NO;
    [_thumbs registerClass:SwipeThumbCell.class forCellWithReuseIdentifier:@"SwipeThumbCell"];
    [self.view addSubview:_thumbs];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat w = self.view.bounds.size.width;

    self.topLabel.frame = CGRectMake(16, safeTop + 10, w - 32, 22);
    self.progressLabel.frame = CGRectMake(16, CGRectGetMaxY(self.topLabel.frame) + 6, w - 32, 40);

    CGFloat cardY = CGRectGetMaxY(self.progressLabel.frame) + 8;
    CGFloat cardH = self.view.bounds.size.height * 0.52;
    self.cardContainer.frame = CGRectMake(16, cardY, w - 32, cardH);

    CGFloat btnY = CGRectGetMaxY(self.cardContainer.frame) + 10;
    self.undoButton.frame = CGRectMake(16, btnY, 100, 40);
    self.sortButton.frame = CGRectMake(w - 16 - 120, btnY, 120, 40);

    CGFloat thumbsY = CGRectGetMaxY(self.undoButton.frame) + 8;
    self.thumbs.frame = CGRectMake(0, thumbsY, w, 96);

    [self layoutCards];
}

#pragma mark - Data

- (void)handleUpdate {
    // 跨模块状态变化也会触发
    [self reloadFromManagerAndRender];
}

- (void)reloadFromManagerAndRender {
    SwipeManager *mgr = [SwipeManager shared];

    // 找到最新的 module（因为 reloadModules 会重建对象）
    SwipeModule *latest = nil;
    for (SwipeModule *m in mgr.modules) {
        if ([m.moduleID isEqualToString:self.module.moduleID]) { latest = m; break; }
    }
    if (latest) self.module = latest;

    self.allAssetIDs = self.module.assetIDs ?: @[];

    [self.unprocessedIDs removeAllObjects];
    for (NSString *aid in self.allAssetIDs) {
        if ([mgr statusForAssetID:aid] == SwipeAssetStatusUnknown) {
            [self.unprocessedIDs addObject:aid];
        }
    }

    // 1) 先读持久化游标：上次处理到哪张
    NSString *cursor = [[SwipeManager shared] currentUnprocessedAssetIDForModuleID:self.module.moduleID];
    if (cursor.length > 0) {
        NSUInteger idx = [self.unprocessedIDs indexOfObject:cursor];
        if (idx != NSNotFound && idx != 0) {
            NSString *target = self.unprocessedIDs[idx];
            [self.unprocessedIDs removeObjectAtIndex:idx];
            [self.unprocessedIDs insertObject:target atIndex:0];
        }
    }

    // 2) 若本次是点击缩略图跳转，则以 focus 优先，并同步写入游标
    if (self.focusAssetID.length > 0) {
        NSUInteger idx = [self.unprocessedIDs indexOfObject:self.focusAssetID];
        if (idx != NSNotFound && idx != 0) {
            NSString *target = self.unprocessedIDs[idx];
            [self.unprocessedIDs removeObjectAtIndex:idx];
            [self.unprocessedIDs insertObject:target atIndex:0];
        }
        [[SwipeManager shared] setCurrentUnprocessedAssetID:self.focusAssetID forModuleID:self.module.moduleID];
        self.focusAssetID = nil;
    }

    // 3) 写回当前游标（如果都处理完了就置空）
    NSString *currentTop = self.unprocessedIDs.firstObject;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:currentTop forModuleID:self.module.moduleID];


    [self updateTopLabels];
    [self.thumbs reloadData];

    [self rebuildCardStack];
}

- (void)updateTopLabels {
    SwipeManager *mgr = [SwipeManager shared];

    NSUInteger total = [mgr totalCountInModule:self.module];
    NSUInteger processed = [mgr processedCountInModule:self.module];
    NSUInteger archived = [mgr archivedCountInModule:self.module];

    double percent = total > 0 ? (double)processed / (double)total : 0;
    self.topLabel.text = [NSString stringWithFormat:@"%@ · %lu 张", self.module.subtitle ?: @"", (unsigned long)total];
    self.progressLabel.text = [NSString stringWithFormat:@"已处理：%lu / %lu（%.0f%%）\n已归档：%lu",
                               (unsigned long)processed, (unsigned long)total, percent * 100.0, (unsigned long)archived];

    [self.sortButton setTitle:(self.module.sortAscending ? @"排序：↑" : @"排序：↓") forState:UIControlStateNormal];
}

#pragma mark - Cards

- (void)rebuildCardStack {
    for (UIView *v in self.cardContainer.subviews) [v removeFromSuperview];
    [self.cards removeAllObjects];

    if (self.unprocessedIDs.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:self.cardContainer.bounds];
        empty.text = @"本模块已全部处理";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [self.cardContainer addSubview:empty];
        return;
    }

    // 只构建最多3张堆叠
    NSInteger count = MIN(3, (NSInteger)self.unprocessedIDs.count);
    for (NSInteger i = count - 1; i >= 0; i--) {
        NSString *aid = self.unprocessedIDs[i];
        SwipeCardView *card = [[SwipeCardView alloc] initWithFrame:self.cardContainer.bounds];
        card.assetID = aid;

        [self.cardContainer addSubview:card];
        [self.cards addObject:card];

        [self loadImageForAssetID:aid intoImageView:card.imageView targetSize:self.cardContainer.bounds.size];

        if (i == 0) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
            [card addGestureRecognizer:pan];
            card.userInteractionEnabled = YES;
        } else {
            card.userInteractionEnabled = NO;
        }
    }

    [self layoutCards];
}

- (void)layoutCards {
    // 简单堆叠：后面缩小一点并下移
    for (NSInteger i = 0; i < self.cards.count; i++) {
        SwipeCardView *card = self.cards[i];
        CGFloat scale = 1.0 - (CGFloat)i * 0.04;
        CGFloat y = (CGFloat)i * 10;
        card.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, y),
                                                 CGAffineTransformMakeScale(scale, scale));
        card.center = CGPointMake(self.cardContainer.bounds.size.width/2.0,
                                  self.cardContainer.bounds.size.height/2.0);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    SwipeCardView *card = (SwipeCardView *)pan.view;
    CGPoint t = [pan translationInView:self.cardContainer];

    CGFloat rotationStrength = MIN(t.x / 320.0, 1.0);
    CGFloat rotationAngle = (CGFloat)(M_PI / 10.0) * rotationStrength;

    CGAffineTransform move = CGAffineTransformMakeTranslation(t.x, t.y);
    CGAffineTransform rotate = CGAffineTransformMakeRotation(rotationAngle);
    card.transform = CGAffineTransformConcat(move, rotate);

    // hint
    if (t.x > 30) {
        card.hintLabel.text = @"保留";
        card.hintLabel.alpha = MIN(1.0, t.x / 120.0);
    } else if (t.x < -30) {
        card.hintLabel.text = @"归档";
        card.hintLabel.alpha = MIN(1.0, -t.x / 120.0);
    } else {
        card.hintLabel.alpha = 0;
    }

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat threshold = 120;
        if (t.x > threshold) {
            [self commitSwipeForCard:card archived:NO];
        } else if (t.x < -threshold) {
            [self commitSwipeForCard:card archived:YES];
        } else {
            [UIView animateWithDuration:0.18 animations:^{
                card.transform = CGAffineTransformIdentity;
                card.hintLabel.alpha = 0;
            } completion:^(__unused BOOL finished) {
                [self layoutCards];
            }];
        }
    }
}

- (void)commitSwipeForCard:(SwipeCardView *)card archived:(BOOL)archived {
    CGFloat offX = archived ? -self.view.bounds.size.width : self.view.bounds.size.width;
    [UIView animateWithDuration:0.22 animations:^{
        card.center = CGPointMake(card.center.x + offX, card.center.y + 30);
        card.alpha = 0.2;
    } completion:^(__unused BOOL finished) {
        NSString *aid = card.assetID;

        SwipeAssetStatus newStatus = archived ? SwipeAssetStatusArchived : SwipeAssetStatusKept;
        [[SwipeManager shared] setStatus:newStatus forAssetID:aid sourceModule:self.module.moduleID recordUndo:YES];

        // 本地 unprocessed 队列移除
        if (self.unprocessedIDs.count > 0 && [self.unprocessedIDs.firstObject isEqualToString:aid]) {
            [self.unprocessedIDs removeObjectAtIndex:0];
        } else {
            [self.unprocessedIDs removeObject:aid];
        }

        [self reloadFromManagerAndRender];
    }];
}

#pragma mark - Buttons

- (void)undoTapped {
    BOOL ok = [[SwipeManager shared] undoLastActionInModuleID:self.module.moduleID];
    if (!ok) return;
    [self reloadFromManagerAndRender];
}

- (void)sortTapped {
    self.module.sortAscending = !self.module.sortAscending;
    [[SwipeManager shared] setSortAscending:self.module.sortAscending forModuleID:self.module.moduleID];
    // 直接翻转顺序（避免等待 reloadModules）
    self.module.assetIDs = [[self.module.assetIDs reverseObjectEnumerator] allObjects];
    [self reloadFromManagerAndRender];
}

#pragma mark - Thumbs

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.allAssetIDs.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SwipeThumbCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"SwipeThumbCell" forIndexPath:indexPath];
    NSString *aid = self.allAssetIDs[indexPath.item];

    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    cell.processedOverlay.hidden = (st == SwipeAssetStatusUnknown);

    cell.imageView.image = nil;
    PHAsset *asset = [[SwipeManager shared] assetForID:aid];
    if (asset) {
        CGSize target = CGSizeMake(140, 140);
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

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(78, 78);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *aid = self.allAssetIDs[indexPath.item];
    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    if (st != SwipeAssetStatusUnknown) return; // 只允许跳到未处理

    self.focusAssetID = aid;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:aid forModuleID:self.module.moduleID];
    [self reloadFromManagerAndRender];
}

#pragma mark - Image loading

- (void)loadImageForAssetID:(NSString *)assetID intoImageView:(UIImageView *)iv targetSize:(CGSize)size {
    PHAsset *asset = [[SwipeManager shared] assetForID:assetID];
    if (!asset) return;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(size.width * scale, size.height * scale);

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.networkAccessAllowed = YES;

    [self.imageManager requestImageForAsset:asset
                                 targetSize:target
                                contentMode:PHImageContentModeAspectFill
                                    options:opt
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) iv.image = result;
    }];
}

@end
