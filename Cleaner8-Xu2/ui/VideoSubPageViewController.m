#import "VideoSubPageViewController.h"
#import "ASCustomNavBar.h"

#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"
#import "ASAssetListViewController.h"
#import "Common.h"
#import "VideoCompressionMainViewController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UI Helpers
static NSString *ASHumanSizeTight(uint64_t bytes) {
    double b = (double)bytes;
    double kb = b / 1024.0;
    double mb = kb / 1024.0;
    double gb = mb / 1024.0;

    if (gb >= 1.0) return [NSString stringWithFormat:@"%.1fGB", gb];
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.0fMB", mb];
    if (kb >= 1.0) return [NSString stringWithFormat:@"%.0fKB", kb];
    return [NSString stringWithFormat:@"%.0fB", b];
}

static inline UIColor *ASBgColor(void) {
    return [UIColor colorWithRed:246/255.0 green:248/255.0 blue:251/255.0 alpha:1.0];
}

static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASBlue(void) { return ASRGB(2, 77, 255); }

static NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

#pragma mark - Video Card Type

typedef NS_ENUM(NSUInteger, ASVideoSubCardType) {
    ASVideoSubCardTypeSimilar = 0,
    ASVideoSubCardTypeDuplicate,
    ASVideoSubCardTypeRecordings,
    ASVideoSubCardTypeBig,
    ASVideoSubCardTypeCompression,
};

#pragma mark - VM

@interface ASVideoSubCardVM : NSObject
@property (nonatomic) ASVideoSubCardType type;
@property (nonatomic, copy, nullable) NSString *badgeText;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *countText;
@property (nonatomic) NSUInteger totalCount;
@property (nonatomic) uint64_t totalBytes;

@property (nonatomic, strong) NSArray<NSString *> *thumbLocalIds;
@property (nonatomic, copy) NSString *thumbKey;

@property (nonatomic) BOOL didSetThumb;
@end
@implementation ASVideoSubCardVM @end

#pragma mark - Cell

@interface VideoSubCardCell : UICollectionViewCell
@property (nonatomic, strong) UIView *shadowContainer;
@property (nonatomic, strong) UIView *cardContainer;

@property (nonatomic, strong) UIImageView *topDecor;
@property (nonatomic, strong) UIView *whiteContent;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *badgeBtn;

@property (nonatomic, strong) UIImageView *img1;
@property (nonatomic, strong) UIImageView *img2;
@property (nonatomic, strong) UIImageView *play1;
@property (nonatomic, strong) UIImageView *play2;

@property (nonatomic, copy) NSString *appliedCoverKey;
@property (nonatomic, copy) NSArray<NSString *> *representedLocalIds;
@property (nonatomic, assign) PHImageRequestID reqId1;
@property (nonatomic, assign) PHImageRequestID reqId2;
@property (nonatomic) BOOL hasFinalThumb1;
@property (nonatomic) BOOL hasFinalThumb2;
@property (nonatomic) NSInteger renderToken;

- (void)applyVM:(ASVideoSubCardVM *)vm;
- (void)prepareForNoAccess;
@end

@implementation VideoSubCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.backgroundColor = UIColor.clearColor;
        _reqId1 = PHInvalidImageRequestID;
        _reqId2 = PHInvalidImageRequestID;
        _renderToken = 0;

        _shadowContainer = [UIView new];
        _shadowContainer.backgroundColor = UIColor.clearColor;
        _shadowContainer.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.10].CGColor;
        _shadowContainer.layer.shadowOpacity = 1;
        _shadowContainer.layer.shadowOffset = CGSizeMake(0, 2);
        _shadowContainer.layer.shadowRadius = 8;
        [self.contentView addSubview:_shadowContainer];

        _cardContainer = [UIView new];
        _cardContainer.backgroundColor = UIColor.clearColor;
        _cardContainer.layer.cornerRadius = 22;
        _cardContainer.clipsToBounds = YES;
        [_shadowContainer addSubview:_cardContainer];

        _topDecor = [UIImageView new];
        _topDecor.contentMode = UIViewContentModeScaleAspectFill;
        _topDecor.clipsToBounds = YES;
        [_cardContainer addSubview:_topDecor];

        _whiteContent = [UIView new];
        _whiteContent.backgroundColor = UIColor.whiteColor;
        _whiteContent.layer.cornerRadius = 22;
        if (@available(iOS 11.0, *)) {
            _whiteContent.layer.maskedCorners = (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
        }
        [_cardContainer addSubview:_whiteContent];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        _titleLabel.textColor = UIColor.blackColor;
        [_whiteContent addSubview:_titleLabel];

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _countLabel.textColor = ASRGB(102, 102, 102);
        [_whiteContent addSubview:_countLabel];

        _badgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _badgeBtn.backgroundColor = ASBlue();
        _badgeBtn.layer.cornerRadius = 18;
        _badgeBtn.clipsToBounds = YES;
        _badgeBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        [_badgeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _badgeBtn.userInteractionEnabled = NO;
        _badgeBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 18);
        _badgeBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

        UIImage *todo = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (todo) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(9, 16), NO, 0);
            [todo drawInRect:CGRectMake(0, 0, 9, 16)];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            [_badgeBtn setImage:scaled forState:UIControlStateNormal];

            CGFloat spacing = 8;
            _badgeBtn.imageEdgeInsets = UIEdgeInsetsMake(0, spacing, 0, 0);
            _badgeBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, spacing);
        }
        [_whiteContent addSubview:_badgeBtn];

        _img1 = [UIImageView new];
        _img2 = [UIImageView new];
        _img1.contentMode = UIViewContentModeScaleAspectFill;
        _img2.contentMode = UIViewContentModeScaleAspectFill;
        _img1.clipsToBounds = YES;
        _img2.clipsToBounds = YES;
        _img1.layer.cornerRadius = 10;
        _img2.layer.cornerRadius = 10;

        _img1.layer.borderWidth = 1;
        _img2.layer.borderWidth = 1;
        _img1.layer.borderColor = UIColor.whiteColor.CGColor;
        _img2.layer.borderColor = UIColor.whiteColor.CGColor;

        _img1.backgroundColor = ASRGB(240, 242, 247);
        _img2.backgroundColor = ASRGB(240, 242, 247);

        [_whiteContent addSubview:_img1];
        [_whiteContent addSubview:_img2];

        _play1 = [UIImageView new];
        _play1.image = [UIImage imageNamed:@"ic_play"];
        _play1.contentMode = UIViewContentModeScaleAspectFit;
        [_whiteContent addSubview:_play1];

        _play2 = [UIImageView new];
        _play2.image = [UIImage imageNamed:@"ic_play"];
        _play2.contentMode = UIViewContentModeScaleAspectFit;
        [_whiteContent addSubview:_play2];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.shadowContainer.frame = self.contentView.bounds;
    self.cardContainer.frame = self.shadowContainer.bounds;

    CGFloat w = self.cardContainer.bounds.size.width;
    CGFloat h = self.cardContainer.bounds.size.height;

    CGFloat topDecorH = 30;
    CGFloat gap = 6;

    self.topDecor.frame = CGRectMake(0, 0, w, topDecorH);

    CGFloat contentY = topDecorH + gap;

    CGFloat whiteH = MIN(150.0, h - contentY);
    self.whiteContent.frame = CGRectMake(0, contentY, w, whiteH);

    CGFloat padX = 16;
    CGFloat padY = 20;

    CGFloat bigW = 92,  bigH = 120;
    CGFloat smallW = 60, smallH = 80;

    CGFloat rightInset = 22;
    CGFloat bigY = padY;

    CGFloat smallX = w - rightInset - smallW;

    CGFloat bigX = smallX + 30 - bigW;

    CGFloat smallY = bigY + (bigH - smallH) * 0.5;

    self.img2.frame = CGRectMake(smallX, smallY, smallW, smallH);
    self.img1.frame = CGRectMake(bigX,   bigY,   bigW,   bigH);

    [self.whiteContent bringSubviewToFront:self.play2];
    [self.whiteContent bringSubviewToFront:self.img1];
    [self.whiteContent bringSubviewToFront:self.play1];

    self.play1.frame = CGRectMake(CGRectGetMinX(self.img1.frame) + 10, CGRectGetMinY(self.img1.frame) + 10, 18, 18);
    self.play2.frame = CGRectMake(CGRectGetMinX(self.img2.frame) + 10, CGRectGetMinY(self.img2.frame) + 10, 18, 18);

    CGFloat textW = MAX(0, bigX - padX - 12);
    self.titleLabel.frame = CGRectMake(padX, padY, textW, 24);
    self.countLabel.frame = CGRectMake(padX, CGRectGetMaxY(self.titleLabel.frame) + 4, textW, 16);

    NSString *t = self.badgeBtn.currentTitle ?: @"";
    CGSize ts = [t sizeWithAttributes:@{NSFontAttributeName:self.badgeBtn.titleLabel.font ?: [UIFont systemFontOfSize:20]}];
    UIImage *bi = [self.badgeBtn imageForState:UIControlStateNormal];
    CGFloat spacing = bi ? 8 : 0;
    UIEdgeInsets in = self.badgeBtn.contentEdgeInsets;
    CGFloat badgeW = ceil(in.left + ts.width + spacing + (bi?bi.size.width:0) + in.right);
    CGFloat badgeH = 48;
    self.badgeBtn.layer.cornerRadius = badgeH / 2.0;
    self.badgeBtn.frame = CGRectMake(padX, CGRectGetMaxY(self.countLabel.frame) + 14, badgeW, badgeH);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.renderToken += 1;

    self.appliedCoverKey = nil;
    self.representedLocalIds = @[];

    self.reqId1 = PHInvalidImageRequestID;
    self.reqId2 = PHInvalidImageRequestID;

    self.hasFinalThumb1 = NO;
    self.hasFinalThumb2 = NO;

    self.img1.image = nil;
    self.img2.image = nil;
}

- (void)applyVM:(ASVideoSubCardVM *)vm {
    self.titleLabel.text = vm.title ?: @"";
    self.countLabel.text = vm.countText ?: @"";
    NSString *badge = vm.badgeText.length ? vm.badgeText : ASHumanSizeTight(vm.totalBytes);
    [self.badgeBtn setTitle:badge forState:UIControlStateNormal];

    switch (vm.type) {
        case ASVideoSubCardTypeSimilar:    self.topDecor.image = [UIImage imageNamed:@"ic_video_tip"]; break;
        case ASVideoSubCardTypeDuplicate:  self.topDecor.image = [UIImage imageNamed:@"ic_video_tip"]; break;
        case ASVideoSubCardTypeRecordings: self.topDecor.image = [UIImage imageNamed:@"ic_video_tip"]; break;
        case ASVideoSubCardTypeBig:        self.topDecor.image = [UIImage imageNamed:@"ic_video_tip"]; break;
        case ASVideoSubCardTypeCompression:self.topDecor.image = [UIImage imageNamed:@"ic_video_tip"]; break;
    }

    self.play1.hidden = NO;
    self.play2.hidden = NO;
}

- (void)prepareForNoAccess {
    self.img1.image = [UIImage imageNamed:@"ic_placeholder"];
    self.img2.image = [UIImage imageNamed:@"ic_placeholder"];
    self.hasFinalThumb1 = NO;
    self.hasFinalThumb2 = NO;
}

@end

#pragma mark - VideoSubPageViewController

@interface VideoSubPageViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UILabel *summaryLine1;
@property (nonatomic, strong) UILabel *summaryLine2;

@property (nonatomic, strong) UIImageView *homeBgImageView;
@property (nonatomic, strong) ASCustomNavBar *navBar;
@property (nonatomic, strong) UICollectionView *cv;

@property (nonatomic, copy) NSString *pageTitle;

// data
@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;
@property (nonatomic, strong) NSArray<ASVideoSubCardVM *> *modules;

@property (nonatomic, strong) NSTimer *scanUITimer;
@property (nonatomic) BOOL pendingScanUIUpdate;
@property (nonatomic) CFTimeInterval lastScanUIFire;
@property (nonatomic, strong) NSUUID *scanProgressToken;

@end

@implementation VideoSubPageViewController

- (instancetype)init {
    if (self = [super init]) {
        _pageTitle = NSLocalizedString(@"Video Cleanup", nil);
    }
    return self;
}

- (void)dealloc {
    if (self.scanProgressToken) {
         [[ASPhotoScanManager shared] removeProgressObserver:self.scanProgressToken];
         self.scanProgressToken = nil;
     }
    [self.scanUITimer invalidate];
    self.scanUITimer = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASBgColor();

    [self buildBackground];
    [self buildNavBar];
    [self buildSummary];
    [self buildCards];

    self.imgMgr = [[PHCachingImageManager alloc] init];
    self.scanMgr = [ASPhotoScanManager shared];

    [self rebuildModulesAndReloadIsFinal:(self.scanMgr.snapshot.state != ASScanStateScanning)];

    __weak typeof(self) weakSelf = self;
    self.scanProgressToken = [[ASPhotoScanManager shared] addProgressObserver:^(ASScanSnapshot *snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf) return;

            if (snapshot.state == ASScanStateScanning) {
                [weakSelf scheduleScanUIUpdateCoalesced];
            } else {
                [weakSelf.scanUITimer invalidate];
                weakSelf.scanUITimer = nil;
                weakSelf.pendingScanUIUpdate = NO;
                [weakSelf rebuildModulesAndReloadIsFinal:YES];
            }
        });
    }];
}

#pragma mark - Build UI

- (NSAttributedString *)as_attrSummary1WithSize:(NSString *)sizeStr {
    NSString *s = [NSString stringWithFormat:NSLocalizedString(@"%@ Free Up", nil), sizeStr ?: @"0B"];

    UIFont *font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    UIColor *gray = ASRGB(102, 102, 102);
    UIColor *blue = ASRGB(2, 77, 255); // #024DFFFF

    NSMutableAttributedString *att =
    [[NSMutableAttributedString alloc] initWithString:s
                                           attributes:@{NSFontAttributeName:font,
                                                        NSForegroundColorAttributeName:gray}];

    if (sizeStr.length > 0 && sizeStr.length <= s.length) {
        [att addAttribute:NSForegroundColorAttributeName value:blue range:NSMakeRange(0, sizeStr.length)];
    }
    return att;
}

- (NSAttributedString *)as_attrSummary2WithString:(NSString *)s {
    UIFont *font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    UIColor *gray = ASRGB(102, 102, 102);
    UIColor *blue = ASRGB(2, 77, 255);

    NSMutableAttributedString *att =
    [[NSMutableAttributedString alloc] initWithString:s ?: @""
                                           attributes:@{NSFontAttributeName:font,
                                                        NSForegroundColorAttributeName:gray}];

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+(?:\\.\\d+)?"
                                                                        options:0
                                                                          error:nil];
    NSArray<NSTextCheckingResult *> *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *m in ms) {
        [att addAttribute:NSForegroundColorAttributeName value:blue range:m.range];
    }
    return att;
}

- (void)buildSummary {
    UILabel *l1 = [UILabel new];
    l1.textAlignment = NSTextAlignmentCenter;
    l1.numberOfLines = 1;
    [self.view addSubview:l1];
    self.summaryLine1 = l1;

    UILabel *l2 = [UILabel new];
    l2.textAlignment = NSTextAlignmentCenter;
    l2.numberOfLines = 1;
    [self.view addSubview:l2];
    self.summaryLine2 = l2;
}

- (void)buildBackground {
    UIImageView *bgTop = [UIImageView new];
    bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    bgTop.contentMode = UIViewContentModeScaleAspectFill;
    bgTop.clipsToBounds = YES;
    bgTop.userInteractionEnabled = NO;

    [self.view addSubview:bgTop];
    [self.view sendSubviewToBack:bgTop];
    self.homeBgImageView = bgTop;

    [NSLayoutConstraint activateConstraints:@[
        [bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bgTop.heightAnchor constraintEqualToConstant:236],
    ]];
}

- (void)buildNavBar {
    NSString *title = self.pageTitle ?: @"";
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:title];

    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };

    [self.view addSubview:self.navBar];
}

- (void)buildCards {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumLineSpacing = 20;
    layout.sectionInset = UIEdgeInsetsMake(0, 30, 30, 30);

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;

    if (@available(iOS 11.0, *)) {
        self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [self.cv registerClass:VideoSubCardCell.class forCellWithReuseIdentifier:@"VideoSubCardCell"];

    [self.view addSubview:self.cv];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat topSafe = self.view.safeAreaInsets.top;
    CGFloat navH = 44 + topSafe;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    self.navBar.frame = CGRectMake(0, 0, w, navH);
    [self.view bringSubviewToFront:self.navBar];

    CGFloat y = navH + 10.0;
    CGFloat lineH = 22.0;

    self.summaryLine1.frame = CGRectMake(0, y, w, lineH);
    y += lineH + 6.0;
    self.summaryLine2.frame = CGRectMake(0, y, w, lineH);

    CGFloat cardsTop = CGRectGetMaxY(self.summaryLine2.frame) + 20.0;
    self.cv.frame = CGRectMake(0, cardsTop, w, h - cardsTop);

    UIEdgeInsets in = UIEdgeInsetsMake(0, 0, self.view.safeAreaInsets.bottom + 20.0, 0);
    self.cv.contentInset = in;
    self.cv.scrollIndicatorInsets = in;
}

#pragma mark - Permission

- (BOOL)hasPhotoAccess {
    PHAuthorizationStatus st;
    if (@available(iOS 14.0, *)) {
        st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        st = [PHPhotoLibrary authorizationStatus];
#pragma clang diagnostic pop
    }
    return (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited);
}

#pragma mark - Throttle

- (void)scheduleScanUIUpdateCoalesced {
    self.pendingScanUIUpdate = YES;

    if (!self.scanUITimer) {
        self.scanUITimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                           target:self
                                                         selector:@selector(handleScanUITimerFire)
                                                         userInfo:nil
                                                          repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.scanUITimer forMode:NSRunLoopCommonModes];
    }
}

- (void)handleScanUITimerFire {
    if (!self.pendingScanUIUpdate) return;
    if (self.scanMgr.snapshot.state != ASScanStateScanning) return;

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastScanUIFire < 0.6) return;

    self.lastScanUIFire = now;
    self.pendingScanUIUpdate = NO;

    [self rebuildModulesAndReloadIsFinal:NO];
}

#pragma mark - Build Modules

// 全部视频数量（只统计 type == video 的 PHAsset）
- (NSUInteger)as_allVideoCount {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeVideo];
    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithOptions:opt];
    return fr.count;
}

// 最新两个视频的 localId（按 creationDate/modificationDate 取最新）
- (NSArray<NSString *> *)as_latestVideoThumbIdsLimit:(NSUInteger)limit {
    if (limit == 0) return @[];

    PHFetchOptions *opt = [PHFetchOptions new];
    opt.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeVideo];
    opt.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"modificationDate" ascending:NO],
    ];
    opt.fetchLimit = limit;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithOptions:opt];
    if (fr.count == 0) return @[];

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) [out addObject:obj.localIdentifier];
        if (out.count == limit) *stop = YES;
    }];
    return out;
}

- (NSDate *)as_assetBestDate:(PHAsset *)a {
    return a.creationDate ?: a.modificationDate ?: [NSDate distantPast];
}

// 从 localIds 取最新 limit 个（内部 cap，避免极端数据）
- (NSArray<NSString *> *)as_pickNewestLocalIds:(NSArray<NSString *> *)localIds limit:(NSUInteger)limit {
    if (limit == 0 || localIds.count == 0) return @[];
    NSUInteger cap = MIN(localIds.count, 300);
    NSArray<NSString *> *cands = [localIds subarrayWithRange:NSMakeRange(0, cap)];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:cands options:nil];
    if (fr.count == 0) return @[];

    NSMutableArray<PHAsset *> *arr = [NSMutableArray arrayWithCapacity:fr.count];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [arr addObject:obj];
    }];

    [arr sortUsingComparator:^NSComparisonResult(PHAsset *a, PHAsset *b) {
        return [[self as_assetBestDate:b] compare:[self as_assetBestDate:a]];
    }];

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (PHAsset *a in arr) {
        if (a.localIdentifier.length) {
            [out addObject:a.localIdentifier];
            if (out.count == limit) break;
        }
    }
    return out;
}

// 从 groups 找“最新的组”，再从该组里取最新 maxCount 个
- (NSArray<NSString *> *)as_thumbsFromNewestGroup:(NSArray<ASAssetGroup *> *)groups
                                           type:(ASGroupType)type
                                       maxCount:(NSUInteger)maxCount {
    if (groups.count == 0 || maxCount == 0) return @[];

    NSMutableArray<NSString *> *repIds = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *groupIds = [NSMutableArray array];

    for (ASAssetGroup *g in groups) {
        if (g.type != type) continue;

        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (ASAssetModel *m in g.assets) {
            if (m.localId.length) [ids addObject:m.localId];
        }
        if (ids.count < 2) continue;

        [repIds addObject:ids.firstObject];
        [groupIds addObject:ids];
    }

    if (repIds.count == 0) return @[];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:repIds options:nil];
    if (fr.count == 0) return [self as_pickNewestLocalIds:groupIds.firstObject limit:maxCount];

    NSMutableDictionary<NSString *, NSDate *> *dateById = [NSMutableDictionary dictionary];
    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) dateById[obj.localIdentifier] = [self as_assetBestDate:obj];
    }];

    NSInteger bestIdx = 0;
    NSDate *bestDate = [NSDate distantPast];
    for (NSInteger i = 0; i < repIds.count; i++) {
        NSDate *d = dateById[repIds[i]] ?: [NSDate distantPast];
        if ([d compare:bestDate] == NSOrderedDescending) {
            bestDate = d;
            bestIdx = i;
        }
    }

    return [self as_pickNewestLocalIds:groupIds[bestIdx] limit:maxCount];
}

- (NSArray<ASAssetModel *> *)flattenGroups:(NSArray<ASAssetGroup *> *)groups type:(ASGroupType)type {
    NSMutableArray<ASAssetModel *> *arr = [NSMutableArray array];
    for (ASAssetGroup *g in groups) {
        if (g.type != type) continue;
        if (g.assets.count < 2) continue;
        [arr addObjectsFromArray:g.assets];
    }
    return arr;
}

- (NSString *)coverKeyForVM:(ASVideoSubCardVM *)vm {
    return [NSString stringWithFormat:@"%lu|%@", (unsigned long)vm.type, (vm.thumbKey ?: @"")];
}

- (void)rebuildModulesAndReloadIsFinal:(BOOL)isFinal {
    // 四块数据源
    NSArray<ASAssetGroup *> *sim = self.scanMgr.similarGroups ?: @[];
    NSArray<ASAssetGroup *> *dup = self.scanMgr.duplicateGroups ?: @[];
    NSArray<ASAssetModel *> *recs = self.scanMgr.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigs = self.scanMgr.bigVideos ?: @[];

    NSArray<ASAssetModel *> *simVid = [self flattenGroups:sim type:ASGroupTypeSimilarVideo];
    NSArray<ASAssetModel *> *dupVid = [self flattenGroups:dup type:ASGroupTypeDuplicateVideo];

    uint64_t simBytes = 0; for (ASAssetModel *m in simVid) simBytes += m.fileSizeBytes;
    uint64_t dupBytes = 0; for (ASAssetModel *m in dupVid) dupBytes += m.fileSizeBytes;
    uint64_t recBytes = 0; for (ASAssetModel *m in recs)   recBytes += m.fileSizeBytes;
    uint64_t bigBytes = 0; for (ASAssetModel *m in bigs)   bigBytes += m.fileSizeBytes;

    uint64_t freeBytes = simBytes + dupBytes + recBytes + bigBytes;
    NSString *freeStr = ASHumanSizeTight(freeBytes);

    // 这里按“items”理解：dupVid.count / simVid.count
    // 如果你想让 Duplicate 显示“组数”，改成：dup.count（并且筛 type）即可
    NSString *line2 = [NSString stringWithFormat:NSLocalizedString(@"%lu Duplicates & %lu Similar Items Found", nil),
                       (unsigned long)dupVid.count,
                       (unsigned long)simVid.count];

    self.summaryLine1.attributedText = [self as_attrSummary1WithSize:freeStr];
    self.summaryLine2.attributedText = [self as_attrSummary2WithString:line2];

    // 封面：扫描中 thumb 只设置一次；finished 可重算（但也不会频繁）
    NSArray<ASVideoSubCardVM *> *old = self.modules ?: @[];

    ASVideoSubCardVM *(^makeVM)(ASVideoSubCardType, NSString *, NSArray<NSString *> *, NSUInteger, uint64_t) =
    ^ASVideoSubCardVM *(ASVideoSubCardType type, NSString *title, NSArray<NSString *> *thumbIds, NSUInteger cnt, uint64_t bytes) {

        ASVideoSubCardVM *vm = [ASVideoSubCardVM new];
        vm.type = type;
        vm.title = title ?: @"";
        vm.totalCount = cnt;
        vm.totalBytes = bytes;
        vm.countText = [NSString stringWithFormat:NSLocalizedString(@"%lu Videos", nil), (unsigned long)cnt];
        vm.thumbLocalIds = thumbIds ?: @[];
        vm.thumbKey = [vm.thumbLocalIds componentsJoinedByString:@"|"];
        vm.didSetThumb = (vm.thumbLocalIds.count > 0);
        return vm;
    };

    NSArray<NSString *> *simThumbs = [self as_thumbsFromNewestGroup:sim type:ASGroupTypeSimilarVideo maxCount:2];
    NSArray<NSString *> *dupThumbs = [self as_thumbsFromNewestGroup:dup type:ASGroupTypeDuplicateVideo maxCount:2];

    NSMutableArray<NSString *> *recIds = [NSMutableArray array];
    for (ASAssetModel *m in recs) if (m.localId.length) [recIds addObject:m.localId];
    NSArray<NSString *> *recThumbs = [self as_pickNewestLocalIds:recIds limit:2];

    NSMutableArray<NSString *> *bigIds = [NSMutableArray array];
    for (ASAssetModel *m in bigs) if (m.localId.length) [bigIds addObject:m.localId];
    NSArray<NSString *> *bigThumbs = [self as_pickNewestLocalIds:bigIds limit:2];

    NSArray<NSString *> *compressionThumbs = [self as_latestVideoThumbIdsLimit:2];
    NSUInteger allVideoCnt = [self as_allVideoCount];

    ASVideoSubCardVM *cvm =
    makeVM(ASVideoSubCardTypeCompression,
           NSLocalizedString(@"Compression Video", nil),
           compressionThumbs,
           allVideoCnt,
           0);
    cvm.badgeText = NSLocalizedString(@"Start Now", nil);

    NSArray<ASVideoSubCardVM *> *newMods = @[
        makeVM(ASVideoSubCardTypeSimilar,    NSLocalizedString(@"Similar Videos", nil),    simThumbs, simVid.count, simBytes),
        makeVM(ASVideoSubCardTypeDuplicate,  NSLocalizedString(@"Duplicate Videos", nil),  dupThumbs, dupVid.count, dupBytes),
        makeVM(ASVideoSubCardTypeRecordings, NSLocalizedString(@"Screen Recordings", nil), recThumbs, recs.count,   recBytes),
        makeVM(ASVideoSubCardTypeBig,        NSLocalizedString(@"Big Videos", nil),        bigThumbs, bigs.count,   bigBytes),
        cvm,
    ];

    if (!isFinal && old.count == newMods.count) {
        for (NSInteger i = 0; i < newMods.count; i++) {
            ASVideoSubCardVM *o = old[i];
            ASVideoSubCardVM *n = newMods[i];

            n.didSetThumb = o.didSetThumb;
            if (o.didSetThumb && o.thumbLocalIds.count > 0) {
                n.thumbLocalIds = o.thumbLocalIds;
                n.thumbKey = o.thumbKey;
            } else {
                // 还没设置过封面：如果有就设置一次
                if (n.thumbLocalIds.count > 0) n.didSetThumb = YES;
            }
        }
    }

    self.modules = newMods;

    // reload
    [self.cv reloadData];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.modules.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    VideoSubCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VideoSubCardCell" forIndexPath:indexPath];
    ASVideoSubCardVM *vm = self.modules[indexPath.item];

    [cell applyVM:vm];

    // 没权限：直接占位，不请求
    if (![self hasPhotoAccess]) {
        [self cancelCellRequests:cell];
        [cell prepareForNoAccess];
        return cell;
    }

    // 没封面：占位
    if (vm.thumbLocalIds.count == 0) {
        [self cancelCellRequests:cell];
        [cell prepareForNoAccess];
        return cell;
    }

    // 请求封面（防闪：同 key 不重复 cancel/placeholder）
    [self requestCoverIfNeededForCell:cell vm:vm atIndexPath:indexPath];

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item >= self.modules.count) return;
    ASVideoSubCardVM *vm = self.modules[indexPath.item];

    if (vm.type == ASVideoSubCardTypeCompression) {
        VideoCompressionMainViewController *vc = [VideoCompressionMainViewController new];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    ASAssetListMode mode = ASAssetListModeSimilarVideo;
    switch (vm.type) {
        case ASVideoSubCardTypeSimilar:    mode = ASAssetListModeSimilarVideo; break;
        case ASVideoSubCardTypeDuplicate:  mode = ASAssetListModeDuplicateVideo; break;
        case ASVideoSubCardTypeRecordings: mode = ASAssetListModeScreenRecordings; break;
        case ASVideoSubCardTypeBig:        mode = ASAssetListModeBigVideos; break;
        default: break;
    }

    ASAssetListViewController *vc = [[ASAssetListViewController alloc] initWithMode:mode];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Layout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat cellW = collectionView.bounds.size.width - 30 * 2;
    CGFloat cellH = 30 + 6 + 150;
    return CGSizeMake(cellW, cellH);
}

#pragma mark - Image Requests (防闪)

- (void)cancelCellRequests:(VideoSubCardCell *)cell {
    if (cell.reqId1 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId1];
        cell.reqId1 = PHInvalidImageRequestID;
    }
    if (cell.reqId2 != PHInvalidImageRequestID) {
        [self.imgMgr cancelImageRequest:cell.reqId2];
        cell.reqId2 = PHInvalidImageRequestID;
    }
}

- (void)requestCoverIfNeededForCell:(VideoSubCardCell *)cell vm:(ASVideoSubCardVM *)vm atIndexPath:(NSIndexPath *)indexPath {

    NSArray<NSString *> *ids = vm.thumbLocalIds ?: @[];
    if (ids.count == 0) return;

    NSString *coverKey = [self coverKeyForVM:vm];
    BOOL sameKey = (cell.appliedCoverKey && [cell.appliedCoverKey isEqualToString:coverKey]);

    if (sameKey) {
        BOOL inFlight = (cell.reqId1 != PHInvalidImageRequestID) || (cell.reqId2 != PHInvalidImageRequestID);
        if (inFlight) return;

        BOOL hasAllFinal = cell.hasFinalThumb1 && (ids.count < 2 || cell.hasFinalThumb2);
        if (hasAllFinal) return;
        // same key 但没最终图：允许补一次（不置 placeholder）
    } else {
        [self cancelCellRequests:cell];
        cell.hasFinalThumb1 = NO;
        cell.hasFinalThumb2 = NO;

        // 只有当当前没图时才放 placeholder，避免闪
        if (!cell.img1.image) cell.img1.image = [UIImage imageNamed:@"ic_placeholder"];
        if (!cell.img2.image) cell.img2.image = [UIImage imageNamed:@"ic_placeholder"];
    }

    cell.appliedCoverKey = coverKey;
    cell.representedLocalIds = ids;

    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    [self loadThumbs:ids intoCell:cell indexPath:indexPath expectedKey:coverKey];
}

- (void)loadThumbs:(NSArray<NSString *> *)ids
          intoCell:(VideoSubCardCell *)cell
         indexPath:(NSIndexPath *)indexPath
       expectedKey:(NSString *)expectedKey {

    [self cancelCellRequests:cell];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;

    CGSize s1 = cell.img1.bounds.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = cell.img1.frame.size;
    if (s1.width <= 1 || s1.height <= 1) s1 = CGSizeMake(120, 120);
    CGSize t1 = CGSizeMake(s1.width * scale, s1.height * scale);

    CGSize s2 = cell.img2.bounds.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = cell.img2.frame.size;
    if (s2.width <= 1 || s2.height <= 1) s2 = CGSizeMake(120, 120);
    CGSize t2 = CGSizeMake(s2.width * scale, s2.height * scale);

    __weak typeof(self) weakSelf = self;

    void (^setImg)(NSInteger, UIImage *, NSDictionary *) = ^(NSInteger idx, UIImage *img, NSDictionary *info) {
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            VideoSubCardCell *nowCell = (VideoSubCardCell *)[weakSelf.cv cellForItemAtIndexPath:indexPath];
            if (!nowCell) return;

            if (!(nowCell.appliedCoverKey && [nowCell.appliedCoverKey isEqualToString:expectedKey])) return;
            if (![nowCell.representedLocalIds isEqualToArray:ids]) return;

            if (idx == 0) {
                if (!degraded || !nowCell.hasFinalThumb1) {
                    nowCell.img1.image = img;
                    if (!degraded) nowCell.hasFinalThumb1 = YES;
                }
            } else {
                if (!degraded || !nowCell.hasFinalThumb2) {
                    nowCell.img2.image = img;
                    if (!degraded) nowCell.hasFinalThumb2 = YES;
                }
            }
        });
    };

    PHAsset *a0 = fr.count > 0 ? [fr objectAtIndex:0] : nil;
    PHAsset *a1 = fr.count > 1 ? [fr objectAtIndex:1] : nil;

    if (a0) {
        cell.reqId1 = [self.imgMgr requestImageForAsset:a0
                                             targetSize:t1
                                            contentMode:PHImageContentModeAspectFill
                                                options:opt
                                          resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(0, result, info ?: @{});
        }];
    }
    if (a1) {
        cell.reqId2 = [self.imgMgr requestImageForAsset:a1
                                             targetSize:t2
                                            contentMode:PHImageContentModeAspectFill
                                                options:opt
                                          resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) setImg(1, result, info ?: @{});
        }];
    } else {
        cell.img2.image = [UIImage imageNamed:@"ic_placeholder"];
    }
}

#pragma mark - Public

- (void)setPageTitle:(NSString *)pageTitle {
    _pageTitle = [pageTitle copy];
}

@end

NS_ASSUME_NONNULL_END
