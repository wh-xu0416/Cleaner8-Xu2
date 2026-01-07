#import "SwipeViewController.h"
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

#import "SwipeManager.h"
#import "Common.h"
#import "SwipeAlbumViewController.h"
#import "ASArchivedFilesViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "ASPrivatePermissionBanner.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}
static inline NSString *SWMonthKeyFromModule(SwipeModule *m) {
    if ([m.moduleID hasPrefix:@"month_"] && m.moduleID.length >= 6) {
        return [m.moduleID substringFromIndex:6]; // "YYYY-MM"
    }
    return m.subtitle ?: @"";
}

static inline UIColor *SWHexRGBA(uint32_t hex) {
    CGFloat r = ((hex >> 24) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat b = ((hex >> 8)  & 0xFF) / 255.0;
    CGFloat a = ( hex        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static inline UIFont *SWFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static inline NSString *SWHumanBytes(uint64_t bytes) {
    static NSByteCountFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSByteCountFormatter new];
        fmt.allowedUnits = NSByteCountFormatterUseAll;
        fmt.countStyle = NSByteCountFormatterCountStyleBinary;
        fmt.includesUnit = YES;
        fmt.includesCount = YES;
        fmt.includesActualByteCount = NO;
    });
    return [fmt stringFromByteCount:(long long)bytes];
}

static inline NSString *SWMonthShort(NSInteger month) {
    static NSArray<NSString *> *arr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arr = @[NSLocalizedString(@"Jan.", nil),NSLocalizedString(@"Feb.", nil),NSLocalizedString(@"Mar.", nil),NSLocalizedString(@"Apr.", nil),NSLocalizedString(@"May.", nil),NSLocalizedString(@"Jun.", nil),NSLocalizedString(@"Jul.", nil),NSLocalizedString(@"Aug.", nil),NSLocalizedString(@"Sep.", nil),NSLocalizedString(@"Oct.", nil),NSLocalizedString(@"Nov.", nil),NSLocalizedString(@"Dec.", nil)];
    });
    if (month < 1 || month > 12) return @"";
    return arr[month-1];
}

static inline void SWParseYearMonth(NSString *yyyyMM, NSInteger *outYear, NSInteger *outMonth) {
    if (outYear) *outYear = 0;
    if (outMonth) *outMonth = 0;
    if (yyyyMM.length < 7) return;

    NSArray<NSString *> *p = [yyyyMM componentsSeparatedByString:@"-"];
    if (p.count != 2) return;

    if (outYear)  *outYear  = p[0].integerValue;
    if (outMonth) *outMonth = p[1].integerValue;
}

static inline NSString *SWRecentTag(NSString *ymd) {
    if (ymd.length < 10) return ymd ?: @"";

    NSInteger y = [[ymd substringWithRange:NSMakeRange(0, 4)] integerValue];
    NSInteger m = [[ymd substringWithRange:NSMakeRange(5, 2)] integerValue];
    NSInteger d = [[ymd substringWithRange:NSMakeRange(8, 2)] integerValue];

    NSDateComponents *c = [NSDateComponents new];
    c.year = y; c.month = m; c.day = d;

    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *date = [cal dateFromComponents:c];
    if (!date) return ymd ?: @"";

    NSDate *today = [NSDate date];
    NSDateComponents *diff = [cal components:NSCalendarUnitDay
                                    fromDate:[cal startOfDayForDate:date]
                                      toDate:[cal startOfDayForDate:today]
                                     options:0];

    if (diff.day == 0) return NSLocalizedString(@"Today", nil);
    if (diff.day == 1) return NSLocalizedString(@"Yesterday", nil);

    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"EEEE";
    });
    return [fmt stringFromDate:date] ?: ymd;
}

@interface SWBottomGradientView : UIView
@end

@implementation SWBottomGradientView

+ (Class)layerClass {
    return [CAGradientLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;

        CAGradientLayer *g = (CAGradientLayer *)self.layer;
        g.colors = @[
            (id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor // #000000FF 50%
        ];
        g.startPoint = CGPointMake(0.5, 0.0);
        g.endPoint   = CGPointMake(0.5, 1.0);
    }
    return self;
}

@end

#pragma mark - Cover Loading Cell Base

@interface SWCoverCellBase : UICollectionViewCell
@property (nonatomic, strong) UIView *coverView;
@property (nonatomic, strong) UIImageView *imgView;

@property (nonatomic, strong) SWBottomGradientView *bottomGradientView;
@property (nonatomic, strong) NSLayoutConstraint *bottomGradientHeightC;

@property (nonatomic, strong) UIImageView *completedIcon;
@property (nonatomic, assign) PHImageRequestID reqId;
@property (nonatomic, copy) NSString *representedAssetId;

- (void)cancelRequestWithManager:(PHCachingImageManager *)mgr;
- (void)setCompletedUI:(BOOL)completed;
- (void)setBottomGradientVisible:(BOOL)visible height:(CGFloat)h;
@end

#pragma mark - No Auth Cell

@interface ASSwipeNoAuthCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *t1;
@property (nonatomic, strong) UILabel *t2;
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation ASSwipeNoAuthCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.image = [UIImage imageNamed:@"ic_photo_permission_not"];
        [self.contentView addSubview:_iconView];

        _t1 = [UILabel new];
        _t1.text = NSLocalizedString(@"Allow Photo Access", nil);
        _t1.textColor = UIColor.blackColor;
        _t1.font = ASFont(20, UIFontWeightMedium);
        _t1.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_t1];

        _t2 = [UILabel new];
        _t2.text = NSLocalizedString(@"To compress photos, videos, and LivePhotos. please allow access to your photo library.", nil);
        _t2.textColor = ASRGB(102, 102, 102);
        _t2.font = ASFont(13, UIFontWeightRegular);
        _t2.numberOfLines = 3;
        _t2.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_t2];

        _btn = [UIButton buttonWithType:UIButtonTypeCustom];
        _btn.backgroundColor = ASBlue();
        _btn.layer.cornerRadius = 35;
        _btn.clipsToBounds = YES;
        [_btn setTitle:NSLocalizedString(@"Go to Settings", nil) forState:UIControlStateNormal];
        [_btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _btn.titleLabel.font = ASFont(20, UIFontWeightRegular);
        _btn.contentEdgeInsets = UIEdgeInsetsMake(18, 0, 18, 0);
        [_btn addTarget:self action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_btn];
    }
    return self;
}

- (void)onBtn {
    if (self.onTap) self.onTap();
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.contentView.bounds.size.width;
    CGFloat top = 60;

    self.iconView.frame = CGRectMake((w - 96)/2.0, top, 96, 96);
    self.t1.frame = CGRectMake(30, CGRectGetMaxY(self.iconView.frame) + 20, w - 60, 24);
    CGFloat t2W = w - 90;

    CGSize t2Size = [self.t2 sizeThatFits:CGSizeMake(t2W, CGFLOAT_MAX)];
    CGFloat lineH = self.t2.font.lineHeight;

    CGFloat t2H = MIN(t2Size.height, ceil(lineH * 3.0));

    self.t2.frame = CGRectMake(45, CGRectGetMaxY(self.t1.frame) + 10, t2W, t2H);
    CGFloat btnW = w - 90;
    self.btn.frame = CGRectMake((w - btnW)/2.0,
                                CGRectGetMaxY(self.t2.frame) + 50,
                                btnW,
                                70);
}

@end

@implementation SWCoverCellBase

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.clearColor;

        _coverView = [UIView new];
        _coverView.translatesAutoresizingMaskIntoConstraints = NO;
        _coverView.layer.cornerRadius = 12;
        _coverView.layer.masksToBounds = YES;
        [self.contentView addSubview:_coverView];

        [NSLayoutConstraint activateConstraints:@[
            [_coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_coverView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];

        _imgView = [UIImageView new];
        _imgView.translatesAutoresizingMaskIntoConstraints = NO;
        _imgView.contentMode = UIViewContentModeScaleAspectFill;
        _imgView.clipsToBounds = YES;
        [_coverView addSubview:_imgView];

        [NSLayoutConstraint activateConstraints:@[
            [_imgView.leadingAnchor constraintEqualToAnchor:_coverView.leadingAnchor],
            [_imgView.trailingAnchor constraintEqualToAnchor:_coverView.trailingAnchor],
            [_imgView.topAnchor constraintEqualToAnchor:_coverView.topAnchor],
            [_imgView.bottomAnchor constraintEqualToAnchor:_coverView.bottomAnchor],
        ]];

        _bottomGradientView = [SWBottomGradientView new];
        _bottomGradientView.translatesAutoresizingMaskIntoConstraints = NO;
        _bottomGradientView.userInteractionEnabled = NO;
        _bottomGradientView.hidden = NO;
        [_coverView addSubview:_bottomGradientView];

        self.bottomGradientHeightC = [_bottomGradientView.heightAnchor constraintEqualToConstant:52];
        self.bottomGradientHeightC.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            [_bottomGradientView.leadingAnchor constraintEqualToAnchor:_coverView.leadingAnchor],
            [_bottomGradientView.trailingAnchor constraintEqualToAnchor:_coverView.trailingAnchor],
            [_bottomGradientView.bottomAnchor constraintEqualToAnchor:_coverView.bottomAnchor],
            self.bottomGradientHeightC,
        ]];

        _completedIcon = [UIImageView new];
        _completedIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _completedIcon.contentMode = UIViewContentModeScaleAspectFit;
        _completedIcon.image = [UIImage imageNamed:@"ic_select_s"];
        _completedIcon.hidden = YES;
        [self.contentView addSubview:_completedIcon];

        [NSLayoutConstraint activateConstraints:@[
            [_completedIcon.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_completedIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_completedIcon.widthAnchor constraintEqualToConstant:31],
            [_completedIcon.heightAnchor constraintEqualToConstant:31],
        ]];

        _reqId = PHInvalidImageRequestID;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.imgView.image = nil;
    self.imgView.alpha = 1.0;
    self.completedIcon.hidden = YES;

    self.representedAssetId = nil;
    self.reqId = PHInvalidImageRequestID;
}

- (void)cancelRequestWithManager:(PHCachingImageManager *)mgr {
    if (self.reqId != PHInvalidImageRequestID) {
        [mgr cancelImageRequest:self.reqId];
        self.reqId = PHInvalidImageRequestID;
    }
}

- (void)setCompletedUI:(BOOL)completed {
    self.imgView.alpha = completed ? 0.4 : 1.0;
    self.completedIcon.hidden = !completed;
}

- (void)setBottomGradientVisible:(BOOL)visible height:(CGFloat)h {
    self.bottomGradientView.hidden = !visible;
    self.bottomGradientHeightC.constant = h;

    [self.coverView setNeedsLayout];
    [self.coverView layoutIfNeeded];
}

@end

#pragma mark - Recent Cell

@interface SWRecentCell : SWCoverCellBase
@property (nonatomic, strong) UILabel *tagLabel;
- (void)configTitle:(NSString *)title completed:(BOOL)completed;
@end

@implementation SWRecentCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        _tagLabel = [UILabel new];
        _tagLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _tagLabel.textColor = UIColor.whiteColor;
        _tagLabel.font = SWFont(13, UIFontWeightMedium);

        [self.coverView addSubview:_tagLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_tagLabel.leadingAnchor constraintEqualToAnchor:self.coverView.leadingAnchor constant:10],
            [_tagLabel.bottomAnchor constraintEqualToAnchor:self.coverView.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)configTitle:(NSString *)title completed:(BOOL)completed {
    self.tagLabel.text = title ?: @"";

    [self setBottomGradientVisible:YES height:52];

    [self setCompletedUI:completed];
}

@end

#pragma mark - Month Cell

@interface SWMonthCell : SWCoverCellBase
@property (nonatomic, strong) UILabel *monthLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
- (void)configMonth:(NSString *)month size:(NSString *)size completed:(BOOL)completed;
@end

@implementation SWMonthCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        _monthLabel = [UILabel new];
        _monthLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _monthLabel.textColor = UIColor.whiteColor;
        _monthLabel.font = SWFont(15, UIFontWeightMedium);

        _sizeLabel = [UILabel new];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sizeLabel.textColor = UIColor.whiteColor;
        _sizeLabel.font = SWFont(12, UIFontWeightRegular);

        [self.coverView addSubview:_monthLabel];
        [self.coverView addSubview:_sizeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_sizeLabel.leadingAnchor constraintEqualToAnchor:self.coverView.leadingAnchor constant:10],
            [_sizeLabel.bottomAnchor constraintEqualToAnchor:self.coverView.bottomAnchor constant:-6],

            [_monthLabel.leadingAnchor constraintEqualToAnchor:self.coverView.leadingAnchor constant:10],
            [_monthLabel.bottomAnchor constraintEqualToAnchor:self.sizeLabel.topAnchor constant:-2],
        ]];
    }
    return self;
}

- (void)configMonth:(NSString *)month size:(NSString *)size completed:(BOOL)completed {
    self.monthLabel.text = month ?: @"";
    self.sizeLabel.text = size ?: @"";

    [self setBottomGradientVisible:YES height:58];

    [self setCompletedUI:completed];
}

@end

#pragma mark - Others Cell

@interface SWOtherCell : SWCoverCellBase
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configTitle:(NSString *)title completed:(BOOL)completed;
@end

@implementation SWOtherCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        _bottomBar = [UIView new];
        _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
        _bottomBar.backgroundColor = UIColor.whiteColor;
        _bottomBar.layer.cornerRadius = 12;
        _bottomBar.layer.masksToBounds = YES;
        if (@available(iOS 11.0, *)) {
            _bottomBar.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        }
        [self.contentView addSubview:_bottomBar];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.textColor = SWHexRGBA(0x000000FF);
        _titleLabel.font = SWFont(15, UIFontWeightSemibold);
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [_bottomBar addSubview:_titleLabel];

        NSLayoutConstraint *barH = [_bottomBar.heightAnchor constraintGreaterThanOrEqualToConstant:40];
        barH.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            [_bottomBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_bottomBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_bottomBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            barH,

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor constant:-10],
            [_titleLabel.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:10],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:_bottomBar.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configTitle:(NSString *)title completed:(BOOL)completed {
    self.bottomBar.hidden = NO;
    self.titleLabel.text = title ?: @"";
    [self setBottomGradientVisible:NO height:0];
    [self setCompletedUI:completed];
}
@end

#pragma mark - SwipeViewController

@interface SwipeViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate>
@property (nonatomic, assign) BOOL sw_hasPhotoAccess;
@property (nonatomic, assign) BOOL sw_isLimitedAuth;

@property (nonatomic, strong) ASPrivatePermissionBanner *permissionBanner;
@property (nonatomic, strong) NSLayoutConstraint *permissionBannerHeightC;

@property (nonatomic, strong) UIView *noAuthPlaceholder;

@property (nonatomic, assign) BOOL sw_needsReloadOnAppear;
@property (nonatomic, assign) BOOL sw_reloadScheduled;

@property (nonatomic, strong) NSCache<NSString *, PHAsset *> *assetCache;

@property (nonatomic, strong) NSLayoutConstraint *cardsTopC;
@property (nonatomic, strong) NSLayoutConstraint *contentBottomC;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UIView *cardsContainer;
@property (nonatomic, strong) UIView *categorizedCard;
@property (nonatomic, strong) UIView *archiveCard;

@property (nonatomic, strong) UIImageView *categorizedIcon;
@property (nonatomic, strong) UILabel *categorizedLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIImageView *speedIcon;

@property (nonatomic, strong) NSLayoutConstraint *progressFillWidthC;
@property (nonatomic, strong) NSLayoutConstraint *speedCenterXC;

@property (nonatomic, assign) CGFloat categorizedProgress;

@property (nonatomic, strong) UIImageView *archiveIcon;
@property (nonatomic, strong) UILabel *archiveTitleLabel;
@property (nonatomic, strong) UILabel *archiveDetailLabel;

@property (nonatomic, strong) UILabel *recentTitleLabel;
@property (nonatomic, strong) UICollectionView *recentCV;

@property (nonatomic, strong) UILabel *yearTitleLabel;
@property (nonatomic, strong) UIButton *yearMoreBtn;
@property (nonatomic, strong) UICollectionView *monthCV;

@property (nonatomic, strong) UILabel *othersTitleLabel;
@property (nonatomic, strong) UIButton *othersMoreBtn;
@property (nonatomic, strong) UICollectionView *othersCV;

@property (nonatomic, strong) NSArray<SwipeModule *> *recentModules;
@property (nonatomic, strong) NSArray<SwipeModule *> *monthModules;
@property (nonatomic, strong) NSArray<SwipeModule *> *otherModules;
@property (nonatomic, assign) BOOL sw_didFirstRender;

@property (nonatomic, strong) PHCachingImageManager *imageMgr;
@property (nonatomic, assign) uint64_t cachedArchivedBytes;
@property (nonatomic, assign) CGFloat cachedCategorizedProgress;
@property (nonatomic, strong) CAGradientLayer *topGradient;

@end

@implementation SwipeViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;

    [self sw_updatePermissionUI];
    [self sw_refreshTopCardsFast];

    if (self.sw_needsReloadOnAppear) {
        self.sw_needsReloadOnAppear = NO;
        [self sw_scheduleReload];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = SWHexRGBA(0xEAF2FFFF);
    self.cachedArchivedBytes = UINT64_MAX;

    self.assetCache = [NSCache new];
    self.assetCache.countLimit = 800;

    self.imageMgr = [PHCachingImageManager new];

    [self buildUI];
    [self sw_updatePermissionUI];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onManagerUpdate)
                                                 name:SwipeManagerDidUpdateNotification
                                               object:nil];

    __weak typeof(self) ws = self;
    [[SwipeManager shared] requestAuthorizationAndLoadIfNeeded:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) return;
            [self sw_updatePermissionUI];
            if (granted) [self reloadAllFromManager];
        });
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (PHAuthorizationStatus)sw_currentPHAuthStatus {
    if (@available(iOS 14.0, *)) {
        return [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [PHPhotoLibrary authorizationStatus];
#pragma clang diagnostic pop
    }
}

- (BOOL)sw_hasAccessForStatus:(PHAuthorizationStatus)st {
    return (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited);
}

#pragma mark - Data

- (void)onManagerUpdate {
    if (!self.isViewLoaded || self.view.window == nil) {
        self.sw_needsReloadOnAppear = YES;
        return;
    }
    [self sw_scheduleReload];
}

- (void)sw_scheduleReload {
    if (self.sw_reloadScheduled) return;
    self.sw_reloadScheduled = YES;

    NSTimeInterval delay = self.sw_didFirstRender ? 0.0 : 0.0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.sw_reloadScheduled = NO;
        if (!self.isViewLoaded || self.view.window == nil) {
            self.sw_needsReloadOnAppear = YES;
            return;
        }
        [self reloadAllFromManager];
        self.sw_didFirstRender = YES;
    });
}

- (void)sw_refreshTopCardsFast {
    SwipeManager *mgr = [SwipeManager shared];

    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        NSUInteger total = [mgr totalAssetCount];
        NSUInteger processed = [mgr totalProcessedCount];
        CGFloat p = (total > 0) ? ((CGFloat)processed / (CGFloat)total) : 0;

        uint64_t bytes = (uint64_t)[mgr totalArchivedBytesCached];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) return;

            self.cachedCategorizedProgress = MAX(0, MIN(1, p));
            NSInteger pct = (NSInteger)llround(self.cachedCategorizedProgress * 100.0);
            self.categorizedLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Categorized %ld%%", nil), (long)pct];

            self.cachedArchivedBytes = bytes;
            [self sw_updateArchiveCardText];
            [self applyCategorizedProgress:self.cachedCategorizedProgress];
        });
    });

    if (self.cachedArchivedBytes == UINT64_MAX) {
        __weak typeof(self) ws = self;
        [[SwipeManager shared] refreshArchivedBytesIfNeeded:^(unsigned long long bytes) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) self = ws;
                if (!self) return;
                if (!self.isViewLoaded || self.view.window == nil) return;
                self.cachedArchivedBytes = (uint64_t)bytes;
                [self sw_updateArchiveCardText];
            });
        }];
    }
}

- (void)reloadAllFromManager {
    SwipeManager *mgr = [SwipeManager shared];

    [self sw_refreshTopCardsFast];

    NSMutableArray *recent = [NSMutableArray array];
    NSMutableArray *months = [NSMutableArray array];
    NSMutableArray *others = [NSMutableArray array];

    for (SwipeModule *m in mgr.modules) {
        if (m.type == SwipeModuleTypeRecentDay) [recent addObject:m];
        else if (m.type == SwipeModuleTypeMonth) [months addObject:m];
        else if (m.type == SwipeModuleTypeRandom20 || m.type == SwipeModuleTypeSelfie) [others addObject:m];
    }

    self.recentModules = recent.copy;
    self.monthModules  = months.copy;

    SwipeModule *rand = nil, *selfie = nil;
    for (SwipeModule *m in others) {
        if (m.type == SwipeModuleTypeRandom20) rand = m;
        if (m.type == SwipeModuleTypeSelfie) selfie = m;
    }
    NSMutableArray *orderedOthers = [NSMutableArray array];

    // Random 永远有
    if (!rand) {
        rand = [SwipeModule new];
        rand.type = SwipeModuleTypeRandom20;
        rand.assetIDs = @[];      // 确保为空
        rand.title = @"";         // 走默认 NSLocalizedString(@"Random", nil)
    }
    // Selfie 永远有
    if (!selfie) {
        selfie = [SwipeModule new];
        selfie.type = SwipeModuleTypeSelfie;
        selfie.assetIDs = @[];
        selfie.title = @"";
    }

    [orderedOthers addObject:rand];
    [orderedOthers addObject:selfie];
    self.otherModules = orderedOthers.copy;

    if (self.monthModules.count > 0) {
        SwipeModule *first = self.monthModules.firstObject;
        NSInteger y = 0, mm = 0;
        NSString *ym = SWMonthKeyFromModule(first);
        SWParseYearMonth(ym, &y, &mm);
        self.yearTitleLabel.text = (y > 0) ? [NSString stringWithFormat:@"%ld", (long)y] : @"";
    }

    [self.recentCV reloadData];
    [self.monthCV reloadData];
    [self.othersCV reloadData];
}

#pragma mark - UI

- (UIView *)buildCardView {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.whiteColor;
    v.layer.cornerRadius = 14;
    v.layer.masksToBounds = NO;
    v.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.06].CGColor;
    v.layer.shadowOpacity = 1;
    v.layer.shadowOffset = CGSizeMake(0, 6);
    v.layer.shadowRadius = 14;
    return v;
}

- (void)buildUI {
    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];

    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0];
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0];

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    // Scroll
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    self.cardsContainer = [UIView new];
    self.cardsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.cardsContainer];

    self.cardsTopC = [self.cardsContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:40];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardsContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.cardsContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        self.cardsTopC,
        [self.cardsContainer.heightAnchor constraintEqualToConstant:97]
    ]];

    self.categorizedCard = [self buildCardView];
    self.archiveCard = [self buildCardView];
    self.categorizedCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.archiveCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.archiveCard.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapArchiveCard)];
    [self.archiveCard addGestureRecognizer:tap];

    [self.cardsContainer addSubview:self.categorizedCard];
    [self.cardsContainer addSubview:self.archiveCard];

    NSLayoutConstraint *ratio =
    [self.categorizedCard.widthAnchor constraintEqualToAnchor:self.archiveCard.widthAnchor multiplier:(220.0/130.0)];
    ratio.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.categorizedCard.leadingAnchor constraintEqualToAnchor:self.cardsContainer.leadingAnchor],
        [self.categorizedCard.topAnchor constraintEqualToAnchor:self.cardsContainer.topAnchor],
        [self.categorizedCard.bottomAnchor constraintEqualToAnchor:self.cardsContainer.bottomAnchor],

        [self.archiveCard.trailingAnchor constraintEqualToAnchor:self.cardsContainer.trailingAnchor],
        [self.archiveCard.topAnchor constraintEqualToAnchor:self.cardsContainer.topAnchor],
        [self.archiveCard.bottomAnchor constraintEqualToAnchor:self.cardsContainer.bottomAnchor],

        [self.archiveCard.leadingAnchor constraintEqualToAnchor:self.categorizedCard.trailingAnchor constant:10],
        ratio
    ]];

    self.permissionBanner = [[ASPrivatePermissionBanner alloc] initWithFrame:CGRectZero];
    self.permissionBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.permissionBanner.hidden = YES;
    [self.contentView addSubview:self.permissionBanner];

    self.permissionBannerHeightC = [self.permissionBanner.heightAnchor constraintEqualToConstant:150];
    self.permissionBannerHeightC.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.permissionBanner.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.permissionBanner.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.permissionBanner.topAnchor constraintEqualToAnchor:self.cardsContainer.bottomAnchor constant:12],
        self.permissionBannerHeightC,
    ]];

    ASSwipeNoAuthCell *noAuth = [ASSwipeNoAuthCell new];
    noAuth.translatesAutoresizingMaskIntoConstraints = NO;
    noAuth.hidden = YES;
    __weak typeof(self) ws = self;
    noAuth.onTap = ^{
        __strong typeof(ws) self = ws;
        if (!self) return;
        [self sw_onTapPermissionGate];
    };
    [self.contentView addSubview:noAuth];
    self.noAuthPlaceholder = noAuth;

    NSLayoutConstraint *noAuthH = [noAuth.heightAnchor constraintGreaterThanOrEqualToConstant:520];
    noAuthH.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [noAuth.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [noAuth.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [noAuth.topAnchor constraintEqualToAnchor:self.permissionBanner.bottomAnchor constant:0],
        noAuthH,
    ]];

    self.categorizedIcon = [UIImageView new];
    self.categorizedIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.categorizedIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.categorizedIcon.image = [UIImage imageNamed:@"ic_category"];
    [self.categorizedCard addSubview:self.categorizedIcon];

    self.categorizedLabel = [UILabel new];
    self.categorizedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.categorizedLabel.textColor = SWHexRGBA(0x000000FF);
    self.categorizedLabel.font = SWFont(15, UIFontWeightMedium);
    self.categorizedLabel.text = NSLocalizedString(@"Categorized 0%", nil);
    [self.categorizedCard addSubview:self.categorizedLabel];

    self.progressTrack = [UIView new];
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTrack.backgroundColor = SWHexRGBA(0x7676803D);
    self.progressTrack.layer.cornerRadius = 4;
    self.progressTrack.layer.masksToBounds = NO;
    self.progressTrack.clipsToBounds = NO;
    [self.categorizedCard addSubview:self.progressTrack];

    self.progressFill = [UIView new];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFill.backgroundColor = SWHexRGBA(0x024DFFFF);
    self.progressFill.layer.cornerRadius = 4;
    self.progressFill.layer.masksToBounds = YES;
    [self.progressTrack addSubview:self.progressFill];

    self.speedIcon = [UIImageView new];
    self.speedIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.speedIcon.image = [UIImage imageNamed:@"ic_speed"];
    [self.progressTrack addSubview:self.speedIcon];

    [NSLayoutConstraint activateConstraints:@[
        [self.categorizedIcon.leadingAnchor constraintEqualToAnchor:self.categorizedCard.leadingAnchor constant:20],
        [self.categorizedIcon.topAnchor constraintEqualToAnchor:self.categorizedCard.topAnchor constant:-22],
        [self.categorizedIcon.widthAnchor constraintEqualToConstant:48],
        [self.categorizedIcon.heightAnchor constraintEqualToConstant:48],

        [self.categorizedLabel.leadingAnchor constraintEqualToAnchor:self.categorizedCard.leadingAnchor constant:20],
        [self.categorizedLabel.trailingAnchor constraintEqualToAnchor:self.categorizedCard.trailingAnchor constant:-20],
        [self.categorizedLabel.topAnchor constraintEqualToAnchor:self.categorizedIcon.bottomAnchor constant:7],

        [self.progressTrack.leadingAnchor constraintEqualToAnchor:self.categorizedCard.leadingAnchor constant:20],
        [self.progressTrack.trailingAnchor constraintEqualToAnchor:self.categorizedCard.trailingAnchor constant:-20],
        [self.progressTrack.topAnchor constraintEqualToAnchor:self.categorizedLabel.bottomAnchor constant:11],
        [self.progressTrack.heightAnchor constraintEqualToConstant:8],
    ]];

    self.progressFillWidthC = [self.progressFill.widthAnchor constraintEqualToConstant:0];
    self.progressFillWidthC.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],
        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.bottomAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor],
        self.progressFillWidthC,
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.speedIcon.widthAnchor constraintEqualToConstant:24],
        [self.speedIcon.heightAnchor constraintEqualToConstant:20],
        [self.speedIcon.centerYAnchor constraintEqualToAnchor:self.progressTrack.centerYAnchor],
    ]];
    self.speedCenterXC = [self.speedIcon.centerXAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor constant:0];
    self.speedCenterXC.priority = UILayoutPriorityRequired;
    self.speedCenterXC.active = YES;

    self.archiveIcon = [UIImageView new];
    self.archiveIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.archiveIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.archiveIcon.image = [UIImage imageNamed:@"ic_delete_home"];
    [self.archiveCard addSubview:self.archiveIcon];

    self.archiveTitleLabel = [UILabel new];
    self.archiveTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.archiveTitleLabel.textColor = SWHexRGBA(0x000000FF);
    self.archiveTitleLabel.font = SWFont(15, UIFontWeightMedium);
    self.archiveTitleLabel.text = NSLocalizedString(@"Archive Files", nil);
    [self.archiveCard addSubview:self.archiveTitleLabel];

    self.archiveDetailLabel = [UILabel new];
    self.archiveDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.archiveDetailLabel.textColor = SWHexRGBA(0x666666FF);
    self.archiveDetailLabel.font = SWFont(12, UIFontWeightMedium);
    self.archiveDetailLabel.text = NSLocalizedString(@"Files:0MB", nil);
    [self.archiveCard addSubview:self.archiveDetailLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.archiveIcon.leadingAnchor constraintEqualToAnchor:self.archiveCard.leadingAnchor constant:20],
        [self.archiveIcon.topAnchor constraintEqualToAnchor:self.archiveCard.topAnchor constant:-22],
        [self.archiveIcon.widthAnchor constraintEqualToConstant:48],
        [self.archiveIcon.heightAnchor constraintEqualToConstant:48],

        [self.archiveTitleLabel.leadingAnchor constraintEqualToAnchor:self.archiveCard.leadingAnchor constant:20],
        [self.archiveTitleLabel.trailingAnchor constraintEqualToAnchor:self.archiveCard.trailingAnchor constant:-20],
        [self.archiveTitleLabel.topAnchor constraintEqualToAnchor:self.archiveIcon.bottomAnchor constant:7],

        [self.archiveDetailLabel.leadingAnchor constraintEqualToAnchor:self.archiveCard.leadingAnchor constant:20],
        [self.archiveDetailLabel.trailingAnchor constraintEqualToAnchor:self.archiveCard.trailingAnchor constant:-20],
        [self.archiveDetailLabel.topAnchor constraintEqualToAnchor:self.archiveTitleLabel.bottomAnchor constant:5],
    ]];

    self.recentTitleLabel = [UILabel new];
    self.recentTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentTitleLabel.textColor = SWHexRGBA(0x000000FF);
    self.recentTitleLabel.font = SWFont(20, UIFontWeightSemibold);
    self.recentTitleLabel.text = NSLocalizedString(@"Recent", nil);
    [self.contentView addSubview:self.recentTitleLabel];

    UICollectionViewFlowLayout *recentLayout = [UICollectionViewFlowLayout new];
    recentLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    recentLayout.minimumLineSpacing = 10;
    recentLayout.itemSize = CGSizeMake(108, 144);
    recentLayout.sectionInset = UIEdgeInsetsMake(0, 15, 0, 15);

    self.recentCV = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:recentLayout];
    self.recentCV.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentCV.backgroundColor = UIColor.clearColor;
    self.recentCV.showsHorizontalScrollIndicator = NO;
    self.recentCV.dataSource = self;
    self.recentCV.delegate = self;
    [self.recentCV registerClass:SWRecentCell.class forCellWithReuseIdentifier:@"SWRecentCell"];
    [self.contentView addSubview:self.recentCV];

    [NSLayoutConstraint activateConstraints:@[
        [self.recentTitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.recentTitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.recentTitleLabel.topAnchor constraintEqualToAnchor:self.permissionBanner.bottomAnchor constant:18],

        [self.recentCV.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.recentCV.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.recentCV.topAnchor constraintEqualToAnchor:self.recentTitleLabel.bottomAnchor constant:10],
        [self.recentCV.heightAnchor constraintEqualToConstant:144],
    ]];

    self.yearTitleLabel = [UILabel new];
    self.yearTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.yearTitleLabel.textColor = SWHexRGBA(0x000000FF);
    self.yearTitleLabel.font = SWFont(20, UIFontWeightSemibold);
    self.yearTitleLabel.text = @"";
    [self.contentView addSubview:self.yearTitleLabel];

    self.yearMoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.yearMoreBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.yearMoreBtn setImage:[UIImage imageNamed:@"ic_todo_small"] forState:UIControlStateNormal];
    [self.contentView addSubview:self.yearMoreBtn];

    UICollectionViewFlowLayout *monthLayout = [UICollectionViewFlowLayout new];
    monthLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    monthLayout.minimumLineSpacing = 10;
    monthLayout.itemSize = CGSizeMake(108, 144);
    monthLayout.sectionInset = UIEdgeInsetsMake(0, 15, 0, 15);

    self.monthCV = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:monthLayout];
    self.monthCV.translatesAutoresizingMaskIntoConstraints = NO;
    self.monthCV.backgroundColor = UIColor.clearColor;
    self.monthCV.showsHorizontalScrollIndicator = NO;
    self.monthCV.dataSource = self;
    self.monthCV.delegate = self;
    [self.monthCV registerClass:SWMonthCell.class forCellWithReuseIdentifier:@"SWMonthCell"];
    [self.contentView addSubview:self.monthCV];

    [NSLayoutConstraint activateConstraints:@[
        [self.yearTitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.yearTitleLabel.topAnchor constraintEqualToAnchor:self.recentCV.bottomAnchor constant:30],

        [self.yearMoreBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.yearMoreBtn.centerYAnchor constraintEqualToAnchor:self.yearTitleLabel.centerYAnchor],
        [self.yearMoreBtn.widthAnchor constraintEqualToConstant:40],
        [self.yearMoreBtn.heightAnchor constraintEqualToConstant:24],

        [self.monthCV.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.monthCV.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.monthCV.topAnchor constraintEqualToAnchor:self.yearTitleLabel.bottomAnchor constant:10],
        [self.monthCV.heightAnchor constraintEqualToConstant:144],
    ]];

    self.othersTitleLabel = [UILabel new];
    self.othersTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.othersTitleLabel.textColor = SWHexRGBA(0x000000FF);
    self.othersTitleLabel.font = SWFont(20, UIFontWeightSemibold);
    self.othersTitleLabel.text = NSLocalizedString(@"Others", nil);
    [self.contentView addSubview:self.othersTitleLabel];

    self.othersMoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.othersMoreBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.othersMoreBtn setImage:[UIImage imageNamed:@"ic_todo_small"] forState:UIControlStateNormal];
    [self.contentView addSubview:self.othersMoreBtn];

    UICollectionViewFlowLayout *otherLayout = [UICollectionViewFlowLayout new];
    otherLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    otherLayout.minimumLineSpacing = 10;
    otherLayout.itemSize = CGSizeMake(108, 144);
    otherLayout.sectionInset = UIEdgeInsetsMake(0, 15, 0, 15);

    self.othersCV = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:otherLayout];
    self.othersCV.translatesAutoresizingMaskIntoConstraints = NO;
    self.othersCV.backgroundColor = UIColor.clearColor;
    self.othersCV.showsHorizontalScrollIndicator = NO;
    self.othersCV.dataSource = self;
    self.othersCV.delegate = self;
    [self.othersCV registerClass:SWOtherCell.class forCellWithReuseIdentifier:@"SWOtherCell"];
    [self.contentView addSubview:self.othersCV];

    self.contentBottomC = [self.othersCV.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-100];
    [NSLayoutConstraint activateConstraints:@[
        [self.othersTitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.othersTitleLabel.topAnchor constraintEqualToAnchor:self.monthCV.bottomAnchor constant:30],

        [self.othersMoreBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.othersMoreBtn.centerYAnchor constraintEqualToAnchor:self.othersTitleLabel.centerYAnchor],
        [self.othersMoreBtn.widthAnchor constraintEqualToConstant:40],
        [self.othersMoreBtn.heightAnchor constraintEqualToConstant:24],

        [self.othersCV.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.othersCV.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.othersCV.topAnchor constraintEqualToAnchor:self.othersTitleLabel.bottomAnchor constant:10],
        [self.othersCV.heightAnchor constraintEqualToConstant:144],
        self.contentBottomC,
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat gradientH = safeTop + 402.0;
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);

    [self applyCategorizedProgress:self.cachedCategorizedProgress];

    if (@available(iOS 11.0, *)) {
        CGFloat safeTop = self.view.safeAreaInsets.top;
        CGFloat safeBottom = self.view.safeAreaInsets.bottom;

        self.cardsTopC.constant = safeTop + 40.0;
        self.contentBottomC.constant = -(safeBottom + 80.0);

        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(safeTop, 0, safeBottom, 0);
    }
}

- (void)sw_updatePermissionUI {
    PHAuthorizationStatus st = [self sw_currentPHAuthStatus];

    self.sw_hasPhotoAccess = [self sw_hasAccessForStatus:st];
    self.sw_isLimitedAuth = (@available(iOS 14.0, *) && st == PHAuthorizationStatusLimited);

    self.permissionBanner.hidden = !self.sw_isLimitedAuth;

    __weak typeof(self) ws = self;
    self.permissionBanner.onGoSettings = ^{
        __strong typeof(ws) self = ws;
        if (!self) return;
        [self sw_onTapPermissionGate];
    };

    BOOL showNoAuth = !self.sw_hasPhotoAccess;
    self.noAuthPlaceholder.hidden = !showNoAuth;

    BOOL showSections = self.sw_hasPhotoAccess;

    self.recentTitleLabel.hidden = !showSections;
    self.recentCV.hidden = !showSections;

    self.yearTitleLabel.hidden = !showSections;
    self.yearMoreBtn.hidden = !showSections;
    self.monthCV.hidden = !showSections;

    self.othersTitleLabel.hidden = !showSections;
    self.othersMoreBtn.hidden = !showSections;
    self.othersCV.hidden = !showSections;

    self.permissionBannerHeightC.constant = self.sw_isLimitedAuth ? 150.0 : 0.0;
}

- (void)sw_onTapPermissionGate {
    PHAuthorizationStatus st = [self sw_currentPHAuthStatus];

    if (st == PHAuthorizationStatusNotDetermined) {
        __weak typeof(self) ws = self;
        [[SwipeManager shared] requestAuthorizationAndLoadIfNeeded:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) self = ws;
                if (!self) return;
                [self sw_updatePermissionUI];
                if (granted) [self reloadAllFromManager];
            });
        }];
        return;
    }

    if (@available(iOS 14.0, *)) {
        if (st == PHAuthorizationStatusLimited) {
            [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:self];
            return;
        }
    }

    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)onTapArchiveCard {
    UINavigationController *nav = [self sw_currentNav];
    if (!nav) return;

    ASArchivedFilesViewController *vc = [ASArchivedFilesViewController new];
    [nav pushViewController:vc animated:YES];
}

#pragma mark - Progress UI

- (void)applyCategorizedProgress:(CGFloat)progress {
    self.categorizedProgress = MAX(0, MIN(1, progress));

    CGFloat trackW = self.progressTrack.bounds.size.width;
    if (trackW <= 0.01) return;

    CGFloat fillW  = trackW * self.categorizedProgress;
    self.progressFillWidthC.constant = fillW;

    CGFloat centerX = fillW;
    centerX = MAX(12, MIN(trackW - 12, centerX));
    self.speedCenterXC.constant = centerX;

    self.speedIcon.hidden = (self.categorizedProgress <= 0.001);
}

- (void)sw_updateArchiveCardText {
    self.archiveDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Files:%@", nil),
                                    SWHumanBytes(self.cachedArchivedBytes)];
}

#pragma mark - Cover helpers

- (NSString *)latestAssetIDForModule:(SwipeModule *)m {
    if (m.assetIDs.count == 0) return @"";
    return m.sortAscending ? (m.assetIDs.lastObject ?: @"") : (m.assetIDs.firstObject ?: @"");
}

- (void)requestCoverForAssetId:(NSString * _Nullable)assetId
                     intoCell:(SWCoverCellBase *)cell
                   targetSize:(CGSize)targetSize {

    [cell cancelRequestWithManager:self.imageMgr];
    cell.representedAssetId = assetId;

    if (assetId.length == 0) {
        cell.imgView.image = [UIImage imageNamed:@"placeholder"];
        return;
    }

    PHAsset *asset = [self.assetCache objectForKey:assetId];
    if (!asset) {
        PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:nil];
        asset = r.firstObject;
        if (asset) [self.assetCache setObject:asset forKey:assetId];
    }

    if (!asset) {
        cell.imgView.image = [UIImage imageNamed:@"placeholder"];
        return;
    }

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize ts = CGSizeMake(targetSize.width * scale, targetSize.height * scale);

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    __weak typeof(cell) wcell = cell;
    cell.reqId = [self.imageMgr requestImageForAsset:asset
                                          targetSize:ts
                                         contentMode:PHImageContentModeAspectFill
                                             options:opt
                                       resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {

        __strong typeof(wcell) scell = wcell;
        if (!scell) return;

        BOOL cancelled = [info[PHImageCancelledKey] boolValue];
        NSError *err = info[PHImageErrorKey];
        if (cancelled || err) return;

        if (![scell.representedAssetId isEqualToString:assetId]) return;

        void (^apply)(void) = ^{
            if (![scell.representedAssetId isEqualToString:assetId]) return;
            scell.imgView.image = result ?: [UIImage imageNamed:@"placeholder"];
        };

        if ([NSThread isMainThread]) apply();
        else dispatch_async(dispatch_get_main_queue(), apply);
    }];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView == self.recentCV) return MAX(self.recentModules.count, 1);
    if (collectionView == self.monthCV)  return MAX(self.monthModules.count, 1);
    if (collectionView == self.othersCV) return self.otherModules.count;
    return 0;
}

- (UINavigationController *)sw_currentNav {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return nil;
    return nav;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    SwipeManager *mgr = [SwipeManager shared];

    if (collectionView == self.recentCV) {
        SWRecentCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"SWRecentCell"
                                                                       forIndexPath:indexPath];
        if (self.recentModules.count == 0) {
            // 占位模块
            [cell cancelRequestWithManager:self.imageMgr];
            cell.coverView.backgroundColor = UIColor.clearColor;
            cell.imgView.backgroundColor = ASRGB(240, 242, 247);
            cell.imgView.contentMode = UIViewContentModeScaleAspectFit;
            cell.imgView.image = [UIImage imageNamed:@"ic_placeholder"];
            cell.tagLabel.text = @"";
            [cell setBottomGradientVisible:NO height:0];
            [cell setCompletedUI:NO];
            cell.userInteractionEnabled = NO;
            return cell;
        }

        cell.userInteractionEnabled = YES;
        cell.coverView.backgroundColor = UIColor.clearColor;
        cell.imgView.backgroundColor = UIColor.clearColor;
        cell.imgView.contentMode = UIViewContentModeScaleAspectFill;

        SwipeModule *m = self.recentModules[indexPath.item];

        BOOL completed = [mgr isModuleCompleted:m];
        NSString *tag = (m.title.length > 0) ? m.title : SWRecentTag(m.subtitle);
        [cell configTitle:tag completed:completed];

        [self requestCoverForAssetId:[self latestAssetIDForModule:m]
                           intoCell:cell
                         targetSize:CGSizeMake(108, 144)];
        return cell;
    }

    if (collectionView == self.monthCV) {
        SWMonthCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"SWMonthCell"
                                                                      forIndexPath:indexPath];
        
        if (self.monthModules.count == 0) {
            [cell cancelRequestWithManager:self.imageMgr];
            cell.coverView.backgroundColor = UIColor.clearColor;
            cell.imgView.backgroundColor = ASRGB(240, 242, 247);
            cell.imgView.contentMode = UIViewContentModeScaleAspectFit;
            cell.imgView.image = [UIImage imageNamed:@"ic_placeholder"];
            cell.monthLabel.text = @"";
            cell.sizeLabel.text = @"";
            [cell setBottomGradientVisible:NO height:0];
            [cell setCompletedUI:NO];
            cell.userInteractionEnabled = NO;
            return cell;
        }

        cell.userInteractionEnabled = YES;
        cell.coverView.backgroundColor = UIColor.clearColor;
        cell.imgView.backgroundColor = UIColor.clearColor;
        cell.imgView.contentMode = UIViewContentModeScaleAspectFill;

        SwipeModule *m = self.monthModules[indexPath.item];

        NSInteger y = 0, mm = 0;
        NSString *ym = SWMonthKeyFromModule(m);
        SWParseYearMonth(ym, &y, &mm);

        NSString *mText = (m.title.length > 0) ? m.title : SWMonthShort(mm); // Dec.
        NSString *sText = [NSString stringWithFormat:@"%lu", (unsigned long)m.assetIDs.count];

        BOOL completed = [mgr isModuleCompleted:m];
        [cell configMonth:mText size:sText completed:completed];
        [self requestCoverForAssetId:[self latestAssetIDForModule:m]
                           intoCell:cell
                         targetSize:CGSizeMake(108, 144)];
        return cell;
    }

    SWOtherCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"SWOtherCell"
                                                                  forIndexPath:indexPath];
    SwipeModule *m = self.otherModules[indexPath.item];

    NSString *title = (m.type == SwipeModuleTypeRandom20) ? NSLocalizedString(@"Random", nil) : NSLocalizedString(@"Selfies", nil);

    BOOL noData = (m.assetIDs.count == 0);

    if (noData) {
        [cell cancelRequestWithManager:self.imageMgr];

        cell.coverView.backgroundColor = UIColor.clearColor;
        cell.imgView.backgroundColor = ASRGB(240, 242, 247);
        cell.imgView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imgView.image = [UIImage imageNamed:@"ic_placeholder"];

        [cell configTitle:title completed:NO];

        // 你这类卡片底部白条会盖图一部分，没数据时也可以不盖图：
        // 如果你想保留标题条就不要 hidden；想全图占位就 hidden
        // 这里按“保留标题条”来：
        cell.bottomBar.hidden = NO;

        cell.userInteractionEnabled = NO;
        return cell;
    }

    // 有数据：正常逻辑
    cell.userInteractionEnabled = YES;
    cell.coverView.backgroundColor = UIColor.clearColor;
    cell.imgView.backgroundColor = UIColor.clearColor;
    cell.imgView.contentMode = UIViewContentModeScaleAspectFill;

    BOOL completed = [mgr isModuleCompleted:m];
    [cell configTitle:title completed:completed];

    [self requestCoverForAssetId:[self latestAssetIDForModule:m]
                       intoCell:cell
                     targetSize:CGSizeMake(108, 144)];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.sw_hasPhotoAccess) {
        [self sw_onTapPermissionGate];
        return;
    }
    
    if (collectionView == self.recentCV && self.recentModules.count == 0) return;
    if (collectionView == self.monthCV  && self.monthModules.count  == 0) return;
    if (collectionView == self.othersCV && self.otherModules.count  == 0) return;
        
    SwipeModule *m = nil;
    if (collectionView == self.recentCV) m = self.recentModules[indexPath.item];
    else if (collectionView == self.monthCV) m = self.monthModules[indexPath.item];
    else if (collectionView == self.othersCV) m = self.otherModules[indexPath.item];

    if (!m) return;

    if (collectionView == self.othersCV) {
        SwipeModule *m = self.otherModules[indexPath.item];
        if (m.assetIDs.count == 0) return;
    }
    
    UINavigationController *nav = [self sw_currentNav];
    if (!nav) return;

    SwipeAlbumViewController *vc = [[SwipeAlbumViewController alloc] initWithModule:m];
    [nav pushViewController:vc animated:YES];
}

#pragma mark - Month Year Title 联动

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.monthCV) return;

    NSArray<NSIndexPath *> *visible = [self.monthCV indexPathsForVisibleItems];
    NSIndexPath *best = nil;
    CGFloat bestMinX = CGFLOAT_MAX;

    for (NSIndexPath *ip in visible) {
        UICollectionViewLayoutAttributes *attr = [self.monthCV layoutAttributesForItemAtIndexPath:ip];
        if (!attr) continue;
        CGFloat minXOnScreen = CGRectGetMinX(attr.frame) - scrollView.contentOffset.x;
        if (minXOnScreen < bestMinX) {
            bestMinX = minXOnScreen;
            best = ip;
        }
    }

    if (best && best.item < self.monthModules.count) {
        SwipeModule *m = self.monthModules[best.item];
        NSInteger y = 0, mm = 0;
        NSString *ym = SWMonthKeyFromModule(m);
        SWParseYearMonth(ym, &y, &mm);
        if (y > 0) {
            NSString *yt = [NSString stringWithFormat:@"%ld", (long)y];
            if (![self.yearTitleLabel.text isEqualToString:yt]) {
                self.yearTitleLabel.text = yt;
            }
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView
didEndDisplayingCell:(UICollectionViewCell *)cell
forItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:SWCoverCellBase.class]) {
        [(SWCoverCellBase *)cell cancelRequestWithManager:self.imageMgr];
    }
}

@end

NS_ASSUME_NONNULL_END
