#import "ASArchivedFilesViewController.h"
#import "ASMediaPreviewViewController.h"
#import "SwipeManager.h"
#import "Common.h"
#import "ASSelectTitleBar.h"
#import <Photos/Photos.h>

#pragma mark - Adapt Helpers (402)

static inline CGFloat ASDesignWidth(void) { return 402.0; }
static inline CGFloat ASScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / ASDesignWidth());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

static inline UIColor *ASColorFromRGBAHex(uint32_t rgba) {
    CGFloat r = ((rgba >> 24) & 0xFF) / 255.0;
    CGFloat g = ((rgba >> 16) & 0xFF) / 255.0;
    CGFloat b = ((rgba >> 8)  & 0xFF) / 255.0;
    CGFloat a = ((rgba)       & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

#pragma mark - Cell

@interface ArchivedCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, copy) NSString *representedAssetID;
@property (nonatomic, copy) void (^onTapPreview)(void);
@property (nonatomic, copy) void (^onTapCheck)(void);
- (void)setChecked:(BOOL)checked;
@end

@implementation ArchivedCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.clearColor;

        _imageView = [UIImageView new];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.layer.cornerRadius = AS(12);
        _imageView.layer.masksToBounds = YES;
        [self.contentView addSubview:_imageView];

        _checkView = [UIImageView new];
        _checkView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_checkView];

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_checkView.widthAnchor constraintEqualToConstant:AS(24)],
            [_checkView.heightAnchor constraintEqualToConstant:AS(24)],
            [_checkView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(6)],
            [_checkView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AS(6)],
        ]];

        UIButton *previewBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        previewBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [previewBtn addTarget:self action:@selector(_tapPreview) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:previewBtn];

        [NSLayoutConstraint activateConstraints:@[
            [previewBtn.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [previewBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [previewBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [previewBtn.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];

        UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        checkBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [checkBtn addTarget:self action:@selector(_tapCheck) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:checkBtn];

        [NSLayoutConstraint activateConstraints:@[
            [checkBtn.widthAnchor constraintEqualToConstant:AS(44)],
            [checkBtn.heightAnchor constraintEqualToConstant:AS(44)],
            [checkBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [checkBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        ]];

        [self setChecked:NO];
        self.selectedBackgroundView = [UIView new];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.imageView.image = nil;
    self.representedAssetID = nil;
    [self setChecked:NO];
}

- (void)setChecked:(BOOL)checked {
    NSString *name = checked ? @"ic_select_s" : @"ic_select_n";
    self.checkView.image = [[UIImage imageNamed:name] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)_tapPreview { if (self.onTapPreview) self.onTapPreview(); }
- (void)_tapCheck   { if (self.onTapCheck) self.onTapCheck(); }

@end

#pragma mark - VC

@interface ASArchivedFilesViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyLabel;

@property (nonatomic, strong) UIView *topGradientView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;

@property (nonatomic, strong) ASSelectTitleBar *titleBar;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *metaLabel;

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *bottomButtonsHost;
@property (nonatomic, strong) UIButton *deleteAllButton;
@property (nonatomic, strong) UIButton *recoverAllButton;

@property (nonatomic, strong) PHCachingImageManager *imageManager;

@property (nonatomic, strong) NSArray<NSString *> *archivedIDs;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIDs;
@end

@implementation ASArchivedFilesViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASColorFromRGBAHex(0xF6F6F6FF);

    self.imageManager = [PHCachingImageManager new];
    self.selectedIDs = [NSMutableSet set];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleUpdate)
                                                 name:SwipeManagerDidUpdateNotification
                                               object:nil];

    [self buildUI];
    [self handleUpdate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    self.topGradientView = [UIView new];
    self.topGradientView.translatesAutoresizingMaskIntoConstraints = NO;
    self.topGradientView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.topGradientView];

    [NSLayoutConstraint activateConstraints:@[
        [self.topGradientView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topGradientView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topGradientView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topGradientView.heightAnchor constraintEqualToConstant:AS(402)],
    ]];

    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.startPoint = CGPointMake(0.5, 0.0);
    self.gradientLayer.endPoint   = CGPointMake(0.5, 1.0);
    self.gradientLayer.colors = @[
        (__bridge id)ASColorFromRGBAHex(0xE0E0E0FF).CGColor,
        (__bridge id)ASColorFromRGBAHex(0x008DFF00).CGColor
    ];
    [self.topGradientView.layer insertSublayer:self.gradientLayer atIndex:0];

    self.titleBar = [[ASSelectTitleBar alloc] initWithTitle:@""];
    self.titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleBar.showTitle = NO;
    self.titleBar.showSelectButton = YES;
    __weak typeof(self) weakSelf = self;
    self.titleBar.onBack = ^{
        if (weakSelf.navigationController) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
        } else {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }
    };
    self.titleBar.onToggleSelectAll = ^(BOOL allSelected) {
        [weakSelf applySelectAll:allSelected];
    };
    [self.view addSubview:self.titleBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.titleBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.titleBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.titleBar.heightAnchor constraintEqualToConstant:AS(44)],
    ]];

    self.headerLabel = [UILabel new];
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLabel.text = NSLocalizedString(@"Archive Files", nil);
    self.headerLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.headerLabel.textColor = ASColorFromRGBAHex(0x000000FF);
    self.headerLabel.numberOfLines = 1;
    [self.view addSubview:self.headerLabel];

    self.metaLabel = [UILabel new];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metaLabel.numberOfLines = 1;
    [self.view addSubview:self.metaLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerLabel.topAnchor constraintEqualToAnchor:self.titleBar.bottomAnchor constant:AS(8)],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.headerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],

        [self.metaLabel.topAnchor constraintEqualToAnchor:self.headerLabel.bottomAnchor constant:AS(5)],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.headerLabel.leadingAnchor],
        [self.metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],
    ]];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = AS(5);
    layout.minimumInteritemSpacing = AS(5);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.allowsMultipleSelection = NO;
    [self.collectionView registerClass:ArchivedCell.class forCellWithReuseIdentifier:@"ArchivedCell"];
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:AS(15)],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], // 延伸到底
    ]];

    self.collectionView.contentInset = UIEdgeInsetsMake(0, AS(10), AS(12) + self.view.safeAreaInsets.bottom, AS(10));

    self.emptyView = [UIView new];
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyView.backgroundColor = UIColor.clearColor;
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyImageView = [UIImageView new];
    self.emptyImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyImageView.image = [UIImage imageNamed:@"ic_empty_photo"];
    [self.emptyView addSubview:self.emptyImageView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = NSLocalizedString(@"No Content", nil);
    self.emptyLabel.textColor = UIColor.blackColor;
    self.emptyLabel.font = ASFontS(24, UIFontWeightMedium);
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    [self.emptyView addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyView.centerXAnchor constraintEqualToAnchor:self.collectionView.centerXAnchor],
        [self.emptyView.centerYAnchor constraintEqualToAnchor:self.collectionView.centerYAnchor],

        [self.emptyImageView.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [self.emptyImageView.topAnchor constraintEqualToAnchor:self.emptyView.topAnchor],
        [self.emptyImageView.widthAnchor constraintEqualToConstant:AS(182)],
        [self.emptyImageView.heightAnchor constraintEqualToConstant:AS(168)],

        [self.emptyLabel.topAnchor constraintEqualToAnchor:self.emptyImageView.bottomAnchor constant:AS(2)],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.emptyView.leadingAnchor],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.emptyView.trailingAnchor],
        [self.emptyLabel.bottomAnchor constraintEqualToAnchor:self.emptyView.bottomAnchor],
    ]];

    self.bottomButtonsHost = [UIView new];
    self.bottomButtonsHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomButtonsHost.backgroundColor = UIColor.clearColor;
    self.bottomButtonsHost.hidden = YES;
    [self.view addSubview:self.bottomButtonsHost];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomButtonsHost.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.bottomButtonsHost.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],
        [self.bottomButtonsHost.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:0],
    ]];

    self.deleteAllButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.deleteAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.deleteAllButton.backgroundColor = ASColorFromRGBAHex(0x024DFFFF);
    self.deleteAllButton.layer.cornerRadius = AS(25.5); // 51/2
    self.deleteAllButton.layer.masksToBounds = YES;
    [self.deleteAllButton setTitle:NSLocalizedString(@"Delete All", nil) forState:UIControlStateNormal];
    [self.deleteAllButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.deleteAllButton.titleLabel.font = ASFontS(20, UIFontWeightRegular);
    [self.deleteAllButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomButtonsHost addSubview:self.deleteAllButton];

    self.recoverAllButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recoverAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.recoverAllButton.backgroundColor = UIColor.whiteColor;
    self.recoverAllButton.layer.cornerRadius = AS(25.5);
    self.recoverAllButton.layer.masksToBounds = YES;
    [self.recoverAllButton setTitle:NSLocalizedString(@"Recover All", nil) forState:UIControlStateNormal];
    [self.recoverAllButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.recoverAllButton.titleLabel.font = ASFontS(20, UIFontWeightMedium);
    [self.recoverAllButton addTarget:self action:@selector(recoverTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomButtonsHost addSubview:self.recoverAllButton];

    CGFloat btnH = AS(51.0);
    CGFloat gap = AS(15.0);

    [NSLayoutConstraint activateConstraints:@[
        [self.deleteAllButton.leadingAnchor constraintEqualToAnchor:self.bottomButtonsHost.leadingAnchor],
        [self.deleteAllButton.trailingAnchor constraintEqualToAnchor:self.bottomButtonsHost.trailingAnchor],
        [self.deleteAllButton.topAnchor constraintEqualToAnchor:self.bottomButtonsHost.topAnchor],
        [self.deleteAllButton.heightAnchor constraintEqualToConstant:btnH],

        [self.recoverAllButton.leadingAnchor constraintEqualToAnchor:self.bottomButtonsHost.leadingAnchor],
        [self.recoverAllButton.trailingAnchor constraintEqualToAnchor:self.bottomButtonsHost.trailingAnchor],
        [self.recoverAllButton.topAnchor constraintEqualToAnchor:self.deleteAllButton.bottomAnchor constant:gap],
        [self.recoverAllButton.heightAnchor constraintEqualToConstant:btnH],
        [self.recoverAllButton.bottomAnchor constraintEqualToAnchor:self.bottomButtonsHost.bottomAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.gradientLayer.frame = self.topGradientView.bounds;
}

- (void)recoverTapped {
    if (self.selectedIDs.count == 0) return;

    NSArray<NSString *> *ids = self.selectedIDs.allObjects;
    [[SwipeManager shared] recoverAssetIDsToUnprocessed:ids];

    [self.selectedIDs removeAllObjects];
    [self updateDeleteButtonVisibilityAndInsets];
    [self handleUpdate];
}

#pragma mark - Data / UI

- (NSArray<NSString *> *)sortedArchivedIDs {
    NSSet<NSString *> *archivedSet = [[SwipeManager shared] archivedAssetIDSet];
    NSArray<PHAsset *> *assets = [[SwipeManager shared] assetsForIDs:archivedSet.allObjects];
    NSArray<PHAsset *> *sorted = [assets sortedArrayUsingComparator:^NSComparisonResult(PHAsset *a, PHAsset *b) {
        NSDate *da = a.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *db = b.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
        return [db compare:da]; // 新 -> 旧
    }];
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:sorted.count];
    for (PHAsset *a in sorted) {
        if (a.localIdentifier) [ids addObject:a.localIdentifier];
    }
    return ids.copy;
}

- (void)handleUpdate {
    SwipeManager *mgr = [SwipeManager shared];

    self.archivedIDs = [self sortedArchivedIDs];

    BOOL isEmpty = (self.archivedIDs.count == 0);
    self.emptyView.hidden = !isEmpty;
    self.collectionView.hidden = isEmpty;

    self.titleBar.showSelectButton = !isEmpty;

    if (isEmpty) {
        [self.selectedIDs removeAllObjects];
        [self syncAllSelectedState];
        [self updateDeleteButtonVisibilityAndInsets];
    }

    NSMutableSet *valid = [NSMutableSet setWithArray:self.archivedIDs];
    [self.selectedIDs intersectSet:valid];

    [self updateMetaLabelWithCount:self.archivedIDs.count bytes:[mgr totalArchivedBytesCached]];

    self.titleBar.showSelectButton = (self.archivedIDs.count > 0);

    [self syncAllSelectedState];

    [self updateDeleteButtonVisibilityAndInsets];
    [self.collectionView reloadData];

    __weak typeof(self) weakSelf = self;
    [[SwipeManager shared] refreshArchivedBytesIfNeeded:^(unsigned long long newBytes) {
        [weakSelf updateMetaLabelWithCount:weakSelf.archivedIDs.count bytes:newBytes];
    }];
}

- (void)updateMetaLabelWithCount:(NSUInteger)count bytes:(unsigned long long)bytes {
    NSString *countStr = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    NSString *filesWord = NSLocalizedString(@" Files ", nil);
    NSString *sizeStr = [self.class bytesToString:bytes];

    NSString *full = [NSString stringWithFormat:@"%@%@%@", countStr, filesWord, sizeStr];

    UIColor *blue = ASColorFromRGBAHex(0x024DFFFF);
    UIColor *gray = ASColorFromRGBAHex(0x666666FF);

    UIFont *baseFont = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    UIFont *blueFont = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full
                                                                            attributes:@{
        NSForegroundColorAttributeName: gray,
        NSFontAttributeName: baseFont
    }];

    [att setAttributes:@{
        NSForegroundColorAttributeName: blue,
        NSFontAttributeName: blueFont
    } range:NSMakeRange(0, countStr.length)];

    NSRange sizeRange = NSMakeRange(full.length - sizeStr.length, sizeStr.length);
    [att setAttributes:@{
        NSForegroundColorAttributeName: blue,
        NSFontAttributeName: blueFont
    } range:sizeRange];

    self.metaLabel.attributedText = att;
}

+ (NSString *)bytesToString:(unsigned long long)bytes {
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb < 1024.0) return [NSString stringWithFormat:@"%.1fMB", mb];
    double gb = mb / 1024.0;
    return [NSString stringWithFormat:@"%.2fGB", gb];
}

- (void)applySelectAll:(BOOL)allSelected {
    if (self.archivedIDs.count == 0) return;

    if (allSelected) {
        [self.selectedIDs removeAllObjects];
        [self.selectedIDs addObjectsFromArray:self.archivedIDs];
    } else {
        [self.selectedIDs removeAllObjects];
    }

    for (ArchivedCell *cell in self.collectionView.visibleCells) {
        NSString *aid = cell.representedAssetID;
        [cell setChecked:(aid.length > 0 && [self.selectedIDs containsObject:aid])];
    }

    [self syncAllSelectedState];
    [self updateDeleteButtonVisibilityAndInsets];
}

- (void)syncAllSelectedState {
    BOOL all = (self.archivedIDs.count > 0 && self.selectedIDs.count == self.archivedIDs.count);
    self.titleBar.allSelected = all;
}

- (void)updateDeleteButtonVisibilityAndInsets {
    BOOL show = (self.selectedIDs.count > 0);
    self.bottomButtonsHost.hidden = !show;

    CGFloat btnH = AS(51.0);
    CGFloat gap = AS(15.0);
    CGFloat hostH = show ? (btnH + gap + btnH) : 0.0;

    CGFloat bottomInset = 12 + self.view.safeAreaInsets.bottom + hostH;

    UIEdgeInsets inset = self.collectionView.contentInset;
    inset.bottom = bottomInset;
    self.collectionView.contentInset = inset;
    self.collectionView.scrollIndicatorInsets = inset;
}

#pragma mark - Actions

- (void)deleteTapped {
    if (self.selectedIDs.count == 0) return;

    NSArray<NSString *> *ids = self.selectedIDs.allObjects;
    NSUInteger count = ids.count;

    BOOL hasVideo = NO;
    for (NSString *aid in ids) {
        PHAsset *a = [[SwipeManager shared] assetForID:aid];
        if (a.mediaType == PHAssetMediaTypeVideo) { hasVideo = YES; break; }
    }

    NSString *typePlural = hasVideo ? NSLocalizedString(@"videos",nil) : NSLocalizedString(@"photos",nil);
    NSString *typeSingle = hasVideo ? NSLocalizedString(@"video",nil)  : NSLocalizedString(@"photo",nil);

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"This action will delete the selected %@ from your system album.",nil), typePlural];

    NSString *deleteTitle = nil;
    if (count == 1) {
        deleteTitle = [NSString stringWithFormat:NSLocalizedString(@"Delete %@ (%lu)",nil), typeSingle, (unsigned long)count];
    } else {
        deleteTitle = [NSString stringWithFormat:NSLocalizedString(@"Delete %@ (%lu)",nil), typePlural, (unsigned long)count];
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil)
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];

    [ac addAction:[UIAlertAction actionWithTitle:deleteTitle
                                          style:UIAlertActionStyleDestructive
                                        handler:^(__unused UIAlertAction * _Nonnull action) {

        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSArray *delIDs = self.selectedIDs.allObjects;
        [[SwipeManager shared] deleteAssetsWithIDs:delIDs completion:^(__unused BOOL success, __unused NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.selectedIDs removeAllObjects];
                [self updateDeleteButtonVisibilityAndInsets];
                [self handleUpdate];
            });
        }];
    }]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIPopoverPresentationController *pop = ac.popoverPresentationController;
        pop.sourceView = self.deleteAllButton ?: self.view;
        pop.sourceRect = (self.deleteAllButton ? self.deleteAllButton.bounds
                                               : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds), 1, 1));
        pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [self presentViewController:ac animated:YES completion:nil];
}


#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.archivedIDs.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ArchivedCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ArchivedCell" forIndexPath:indexPath];
    NSString *aid = self.archivedIDs[indexPath.item];

    NSString *prev = cell.representedAssetID;
    cell.representedAssetID = aid;
    [cell setChecked:[self.selectedIDs containsObject:aid]];

    if (![prev isEqualToString:aid]) {
        cell.imageView.image = nil;
    }

    PHAsset *asset = [[SwipeManager shared] assetForID:aid];
    if (asset) {
        CGSize target = CGSizeMake(AS(240), AS(320));
        PHImageRequestOptions *opt = [PHImageRequestOptions new];
        opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
        opt.resizeMode = PHImageRequestOptionsResizeModeFast;
        opt.networkAccessAllowed = YES;

        __weak typeof(cell) weakCell = cell;
        [self.imageManager requestImageForAsset:asset
                                     targetSize:target
                                    contentMode:PHImageContentModeAspectFill
                                        options:opt
                                  resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            NSNumber *degraded = info[PHImageResultIsDegradedKey];
            if (degraded.boolValue) {
                if (!weakCell.imageView.image) {
                    weakCell.imageView.image = result;
                }
            } else {
                weakCell.imageView.image = result;
            }

            if (!result) return;
            if (![weakCell.representedAssetID isEqualToString:aid]) return;
            weakCell.imageView.image = result;
        }];
    }

    __weak typeof(self) weakSelf = self;
    __weak typeof(cv) weakCV = cv;
    __weak typeof(cell) weakCell = cell;

    cell.onTapPreview = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        PHAsset *asset = [[SwipeManager shared] assetForID:aid];
        if (!asset) return;

        NSArray<PHAsset *> *previewAssets = @[asset];
        NSIndexSet *preSel = [NSIndexSet indexSet];

        ASMediaPreviewViewController *p =
        [[ASMediaPreviewViewController alloc] initWithAssets:previewAssets
                                               initialIndex:0
                                            selectedIndexes:preSel];

        p.bestIndex = 0;
        p.showsBestBadge = NO;

        [self.navigationController pushViewController:p animated:YES];
    };

    cell.onTapCheck = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        BOOL checked = [self.selectedIDs containsObject:aid];
        if (checked) {
            [self.selectedIDs removeObject:aid];
            [weakCell setChecked:NO];
        } else {
            [self.selectedIDs addObject:aid];
            [weakCell setChecked:YES];
        }

        [self syncAllSelectedState];
        [self updateDeleteButtonVisibilityAndInsets];
    };

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {

    CGFloat availableW = collectionView.bounds.size.width
        - collectionView.contentInset.left
        - collectionView.contentInset.right;

    CGFloat spacing = AS(5.0);
    CGFloat maxW = AS(120.0);

    CGFloat w = floor((availableW - spacing * 2) / 3.0);
    w = MIN(maxW, w);

    CGFloat h = round(w * (AS(160.0) / AS(120.0)));
    return CGSizeMake(w, h);
}

@end
