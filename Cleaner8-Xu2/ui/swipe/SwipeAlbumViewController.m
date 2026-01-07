#import "SwipeAlbumViewController.h"
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

#import "SwipeManager.h"
#import "ASArchivedFilesViewController.h"

#pragma mark - Helpers

static inline BOOL SWParseYMD(NSString *ymd, NSInteger *outY, NSInteger *outM, NSInteger *outD) {
    if (outY) *outY = 0;
    if (outM) *outM = 0;
    if (outD) *outD = 0;
    if (ymd.length < 10) return NO;

    NSInteger y = [[ymd substringWithRange:NSMakeRange(0, 4)] integerValue];
    NSInteger m = [[ymd substringWithRange:NSMakeRange(5, 2)] integerValue];
    NSInteger d = [[ymd substringWithRange:NSMakeRange(8, 2)] integerValue];

    if (y <= 0 || m <= 0 || d <= 0) return NO;

    if (outY) *outY = y;
    if (outM) *outM = m;
    if (outD) *outD = d;
    return YES;
}

static inline NSDate *SWDateFromYMD(NSString *ymd) {
    NSInteger y=0,m=0,d=0;
    if (!SWParseYMD(ymd, &y, &m, &d)) return nil;

    NSDateComponents *c = [NSDateComponents new];
    c.year = y; c.month = m; c.day = d;
    return [NSCalendar.currentCalendar dateFromComponents:c];
}

// 是否在最近 N 天内（含今天），N=7 表示最近 7 天
static inline BOOL SWIsWithinLastNDays(NSString *ymd, NSInteger days) {
    if (days <= 0) return NO;
    NSDate *date = SWDateFromYMD(ymd);
    if (!date) return NO;

    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *today = [NSDate date];

    NSDate *a = [cal startOfDayForDate:date];
    NSDate *b = [cal startOfDayForDate:today];

    NSDateComponents *diff = [cal components:NSCalendarUnitDay fromDate:a toDate:b options:0];
    // diff.day: date -> today 的天数差；0=今天，1=昨天...
    return (diff.day >= 0 && diff.day <= (days - 1));
}

// 给 RecentDay 的 next 按钮一个标题（简单点：用 subtitle 直接显示也行）
static inline NSString *SWNextRecentTitle(NSString *ymd) {
    if (ymd.length >= 10) return [NSString stringWithFormat:@"Next Album > %@", ymd];
    return @"Next Album";
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

static inline NSString *SWDayKeyFromModule(SwipeModule *m) {
    NSString *mid = m.moduleID ?: @"";
    if ([mid hasPrefix:@"day_"] && mid.length >= 14) {
        return [mid substringFromIndex:4]; // "YYYY-MM-DD"
    }
    return nil;
}

static inline NSString *SWMonthKeyFromModule(SwipeModule *m) {
    NSString *mid = m.moduleID ?: @"";
    if ([mid hasPrefix:@"month_"] && mid.length >= 13) {
        return [mid substringFromIndex:6]; // "YYYY-MM"
    }
    return nil;
}

static inline NSString *SWWeekdayFromYMD(NSString *ymd) {
    NSDate *d = SWDateFromYMD(ymd);
    if (!d) return @"";
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"EEEE"; // Friday / Thursday
    });
    return [fmt stringFromDate:d] ?: @"";
}

static inline NSString *SWHumanBytesNoSpace(uint64_t bytes) {
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
    NSString *s = [fmt stringFromByteCount:(long long)bytes] ?: @"0B";
    // "49.5 MB" -> "49.5MB"
    return [[s stringByReplacingOccurrencesOfString:@" " withString:@""] copy];
}

static inline NSString *SWMonthShort(NSInteger month) {
    static NSArray<NSString *> *arr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arr = @[@"Jan.",@"Feb.",@"Mar.",@"Apr.",@"May.",@"Jun.",@"Jul.",@"Aug.",@"Sep.",@"Oct.",@"Nov.",@"Dec."];
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

#pragma mark - Thumb Cell

@interface SwipeThumbCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *checkIcon;

@property (nonatomic, assign) PHImageRequestID reqId;
@property (nonatomic, copy) NSString *representedAssetID;
@end

@implementation SwipeThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 8;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.backgroundColor = UIColor.whiteColor;

        _imageView = [UIImageView new];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _checkIcon = [UIImageView new];
        _checkIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _checkIcon.contentMode = UIViewContentModeScaleAspectFit;
        _checkIcon.image = [UIImage imageNamed:@"ic_select_s"];
        _checkIcon.hidden = YES;
        [self.contentView addSubview:_checkIcon];

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_checkIcon.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_checkIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_checkIcon.widthAnchor constraintEqualToConstant:16],
            [_checkIcon.heightAnchor constraintEqualToConstant:16],
        ]];

        _reqId = PHInvalidImageRequestID;
    }
    return self;
}
@end

#pragma mark - Card View

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

        self.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;

        _imageView.backgroundColor = UIColor.clearColor;

        [self addSubview:_imageView];

        _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hintLabel.font = SWFont(24, UIFontWeightBold);
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
@property (nonatomic, assign) BOOL cardAnimating;
@property (nonatomic, assign) BOOL sw_needsRefreshOnAppear;

@property (nonatomic, strong) SwipeModule *module;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) NSCache<NSString *, PHAsset *> *assetCache;

@property (nonatomic, strong) NSArray<NSString *> *allAssetIDs;
@property (nonatomic, strong) NSMutableArray<NSString *> *unprocessedIDs;
@property (nonatomic, copy, nullable) NSString *focusAssetID;

@property (nonatomic, strong) NSMutableArray<SwipeCardView *> *cards; // 0=top
@property (nonatomic, strong) UIPanGestureRecognizer *topPan;

#pragma mark - UI (Top)
@property (nonatomic, strong) UIView *topGradientView;
@property (nonatomic, strong) UIView *titleBar;

@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIView *progressRight;
@property (nonatomic, strong) UIImageView *hotIcon;
@property (nonatomic, strong) UILabel *percentLabel;

@property (nonatomic, strong) UILabel *filesLabel;

#pragma mark - UI (Card Stack)
@property (nonatomic, strong) UIView *cardArea;    // width 330 height 543
@property (nonatomic, strong) UIView *cardsHost;   // cards placed here

@property (nonatomic, strong) UIButton *archiveBtn;
@property (nonatomic, strong) UIButton *keepBtn;

#pragma mark - UI (Bottom Bar)
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *undoIconBtn;
@property (nonatomic, strong) UIButton *sortIconBtn;
@property (nonatomic, strong) UICollectionView *thumbs;

@property (nonatomic, strong) NSLayoutConstraint *bottomBarHeightC;

#pragma mark - UI (Completed)
@property (nonatomic, strong) UIView *doneCard;          // 330x465
@property (nonatomic, strong) UIImageView *doneIcon;     // ic_hot 80
@property (nonatomic, strong) UILabel *doneTitleLabel;   // Organized 100%
@property (nonatomic, strong) UIView *doneTable;         // 280x100
@property (nonatomic, strong) UILabel *doneArchiveTitle;
@property (nonatomic, strong) UILabel *doneArchiveValue;
@property (nonatomic, strong) UILabel *doneKeepTitle;
@property (nonatomic, strong) UILabel *doneKeepValue;

@property (nonatomic, strong) UIButton *nextAlbumBtn;
@property (nonatomic, strong) UIButton *viewArchivedBtn;

#pragma mark - State / Perf
@property (nonatomic, assign) BOOL reloadScheduled;

@property (nonatomic, assign) BOOL sw_actionLocked;

@property (nonatomic, strong) UIView *sw_sortMask;
@property (nonatomic, strong) UIView *sw_sortPanel;
@property (nonatomic, assign) BOOL sw_sortShowing;
@property (nonatomic, assign) BOOL sw_pendingSortJumpToFirst;

@end

@implementation SwipeAlbumViewController

- (instancetype)initWithModule:(SwipeModule *)module {
    if ((self = [super init])) {
        _module = module;
        _imageManager = [PHCachingImageManager new];
        _assetCache = [NSCache new];
        _assetCache.countLimit = 1000;

        _cards = [NSMutableArray array];
        _unprocessedIDs = [NSMutableArray array];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    NSString *top = self.unprocessedIDs.firstObject;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:(top.length ? top : @"")
                                            forModuleID:self.module.moduleID];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SWHexRGBA(0xF6F6F6FF);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleUpdate)
                                                 name:SwipeManagerDidUpdateNotification
                                               object:nil];

    [self buildUI];
    [self sw_prepare3CardsIfNeeded];
    [self reloadFromManagerAndRender:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Navigation helper

- (UINavigationController *)sw_currentNav {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return nil;
    return nav;
}

#pragma mark - UI Build

- (void)buildUI {

    // ===== Top gradient background (307pt) =====
    self.topGradientView = [UIView new];
    self.topGradientView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topGradientView];

    [NSLayoutConstraint activateConstraints:@[
        [self.topGradientView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topGradientView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topGradientView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topGradientView.heightAnchor constraintEqualToConstant:307],
    ]];

    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[
        (id)SWHexRGBA(0xE0E0E0FF).CGColor,
        (id)SWHexRGBA(0x008DFF00).CGColor
    ];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint   = CGPointMake(0.5, 1.0);
    g.frame = CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 307);
    [self.topGradientView.layer insertSublayer:g atIndex:0];

    // ===== Title bar =====
    self.titleBar = [UIView new];
    self.titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.titleBar];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.titleBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
        [self.titleBar.heightAnchor constraintEqualToConstant:44],
    ]];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backBtn setImage:[UIImage imageNamed:@"ic_remove"] forState:UIControlStateNormal];
    self.backBtn.adjustsImageWhenHighlighted = YES;
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:self.backBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.titleBar.leadingAnchor],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:self.titleBar.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:32],
        [self.backBtn.heightAnchor constraintEqualToConstant:32],
    ]];

    self.progressRight = [UIView new];
    self.progressRight.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleBar addSubview:self.progressRight];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressRight.trailingAnchor constraintEqualToAnchor:self.titleBar.trailingAnchor],
        [self.progressRight.centerYAnchor constraintEqualToAnchor:self.titleBar.centerYAnchor],
        [self.progressRight.heightAnchor constraintEqualToConstant:32],
    ]];

    self.hotIcon = [UIImageView new];
    self.hotIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.hotIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.hotIcon.image = [UIImage imageNamed:@"ic_hot"];
    [self.progressRight addSubview:self.hotIcon];

    self.percentLabel = [UILabel new];
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLabel.textColor = UIColor.blackColor;
    self.percentLabel.font = SWFont(20, UIFontWeightSemibold);
    self.percentLabel.text = @"0%";
    [self.progressRight addSubview:self.percentLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.hotIcon.leadingAnchor constraintEqualToAnchor:self.progressRight.leadingAnchor],
        [self.hotIcon.centerYAnchor constraintEqualToAnchor:self.progressRight.centerYAnchor],
        [self.hotIcon.widthAnchor constraintEqualToConstant:32],
        [self.hotIcon.heightAnchor constraintEqualToConstant:32],

        [self.percentLabel.leadingAnchor constraintEqualToAnchor:self.hotIcon.trailingAnchor constant:5],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:self.progressRight.trailingAnchor],
        [self.percentLabel.centerYAnchor constraintEqualToAnchor:self.progressRight.centerYAnchor],
    ]];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.font = SWFont(20, UIFontWeightSemibold);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.titleBar addSubview:self.titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.backBtn.trailingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.progressRight.leadingAnchor constant:-12],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.titleBar.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.titleBar.centerYAnchor],
    ]];

    self.filesLabel = [UILabel new];
    self.filesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.filesLabel.textAlignment = NSTextAlignmentCenter;
    self.filesLabel.numberOfLines = 1;
    [self.view addSubview:self.filesLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.filesLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.filesLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.filesLabel.topAnchor constraintEqualToAnchor:self.titleBar.bottomAnchor constant:0],
        [self.filesLabel.heightAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];

    self.cardArea = [UIView new];
    self.cardArea.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardArea.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.cardArea];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardArea.topAnchor constraintEqualToAnchor:self.filesLabel.bottomAnchor constant:5],
        [self.cardArea.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.cardArea.widthAnchor constraintEqualToConstant:330],
        [self.cardArea.heightAnchor constraintEqualToConstant:543],
    ]];

    self.cardsHost = [UIView new];
    self.cardsHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardsHost.backgroundColor = UIColor.clearColor;
    [self.cardArea addSubview:self.cardsHost];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardsHost.leadingAnchor constraintEqualToAnchor:self.cardArea.leadingAnchor],
        [self.cardsHost.trailingAnchor constraintEqualToAnchor:self.cardArea.trailingAnchor],
        [self.cardsHost.topAnchor constraintEqualToAnchor:self.cardArea.topAnchor],
        [self.cardsHost.bottomAnchor constraintEqualToAnchor:self.cardArea.bottomAnchor],
    ]];

    self.archiveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.archiveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.archiveBtn.backgroundColor = SWHexRGBA(0x024DFFFF);
    self.archiveBtn.layer.cornerRadius = 24;
    self.archiveBtn.titleLabel.font = SWFont(20, UIFontWeightRegular);
    [self.archiveBtn setTitle:@"Archive" forState:UIControlStateNormal];
    [self.archiveBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.archiveBtn addTarget:self action:@selector(onArchiveBtn) forControlEvents:UIControlEventTouchUpInside];
    [self.cardArea addSubview:self.archiveBtn];

    self.keepBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.keepBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.keepBtn.backgroundColor = SWHexRGBA(0x028BFFFF);
    self.keepBtn.layer.cornerRadius = 24;
    self.keepBtn.titleLabel.font = SWFont(20, UIFontWeightRegular);
    [self.keepBtn setTitle:@"Keep" forState:UIControlStateNormal];
    [self.keepBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.keepBtn addTarget:self action:@selector(onKeepBtn) forControlEvents:UIControlEventTouchUpInside];
    [self.cardArea addSubview:self.keepBtn];

    NSLayoutConstraint *centerY = [self.archiveBtn.centerYAnchor constraintEqualToAnchor:self.cardArea.topAnchor constant:529];
    centerY.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.archiveBtn.leadingAnchor constraintEqualToAnchor:self.cardArea.leadingAnchor],
        [self.archiveBtn.widthAnchor constraintEqualToConstant:150],
        [self.archiveBtn.heightAnchor constraintEqualToConstant:48],
        centerY,

        [self.keepBtn.trailingAnchor constraintEqualToAnchor:self.cardArea.trailingAnchor],
        [self.keepBtn.widthAnchor constraintEqualToConstant:150],
        [self.keepBtn.heightAnchor constraintEqualToConstant:48],
        [self.keepBtn.centerYAnchor constraintEqualToAnchor:self.archiveBtn.centerYAnchor],
    ]];

    // ===== Bottom bar (cardArea 下 26pt，圆角16，上白到底部) =====
    self.bottomBar = [UIView new];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = UIColor.whiteColor;
    self.bottomBar.layer.cornerRadius = 16;
    self.bottomBar.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        self.bottomBar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    [self.view addSubview:self.bottomBar];

    self.bottomBarHeightC = [self.bottomBar.heightAnchor constraintEqualToConstant:140];
    self.bottomBarHeightC.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.topAnchor constraintEqualToAnchor:self.cardArea.bottomAnchor constant:26],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], // extend under home indicator
        self.bottomBarHeightC,
    ]];

    self.undoIconBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.undoIconBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.undoIconBtn setImage:[UIImage imageNamed:@"ic_backout"] forState:UIControlStateNormal];
    [self.undoIconBtn addTarget:self action:@selector(undoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.undoIconBtn];

    self.sortIconBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.sortIconBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sortIconBtn setImage:[UIImage imageNamed:@"ic_sort"] forState:UIControlStateNormal];
    [self.sortIconBtn addTarget:self action:@selector(sortTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.sortIconBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.undoIconBtn.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:20],
        [self.undoIconBtn.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12],
        [self.undoIconBtn.widthAnchor constraintEqualToConstant:24],
        [self.undoIconBtn.heightAnchor constraintEqualToConstant:24],

        [self.sortIconBtn.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-20],
        [self.sortIconBtn.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12],
        [self.sortIconBtn.widthAnchor constraintEqualToConstant:24],
        [self.sortIconBtn.heightAnchor constraintEqualToConstant:24],
    ]];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 5;
    layout.itemSize = CGSizeMake(60, 60);
    layout.sectionInset = UIEdgeInsetsMake(0, 20, 0, 20);

    self.thumbs = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.thumbs.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbs.backgroundColor = UIColor.clearColor;
    self.thumbs.dataSource = self;
    self.thumbs.delegate = self;
    self.thumbs.showsHorizontalScrollIndicator = NO;
    [self.thumbs registerClass:SwipeThumbCell.class forCellWithReuseIdentifier:@"SwipeThumbCell"];
    [self.bottomBar addSubview:self.thumbs];

    [NSLayoutConstraint activateConstraints:@[
        [self.thumbs.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
        [self.thumbs.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
        [self.thumbs.topAnchor constraintEqualToAnchor:self.undoIconBtn.bottomAnchor constant:12],
        [self.thumbs.heightAnchor constraintEqualToConstant:60],
    ]];

    // ===== Done Card (hidden by default) =====
    self.doneCard = [UIView new];
    self.doneCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneCard.backgroundColor = UIColor.whiteColor;
    self.doneCard.layer.cornerRadius = 20;
    self.doneCard.hidden = YES;
    [self.cardArea addSubview:self.doneCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.doneCard.centerXAnchor constraintEqualToAnchor:self.cardArea.centerXAnchor],
        [self.doneCard.centerYAnchor constraintEqualToAnchor:self.cardArea.centerYAnchor constant:-10],
        [self.doneCard.widthAnchor constraintEqualToConstant:330],
        [self.doneCard.heightAnchor constraintEqualToConstant:465],
    ]];

    self.doneIcon = [UIImageView new];
    self.doneIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.doneIcon.image = [UIImage imageNamed:@"ic_hot"];
    [self.doneCard addSubview:self.doneIcon];

    self.doneTitleLabel = [UILabel new];
    self.doneTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneTitleLabel.textColor = UIColor.blackColor;
    self.doneTitleLabel.font = SWFont(20, UIFontWeightSemibold);
    self.doneTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.doneTitleLabel.text = @"Organized 100%";
    [self.doneCard addSubview:self.doneTitleLabel];

    self.doneTable = [UIView new];
    self.doneTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneTable.layer.cornerRadius = 16;
    self.doneTable.layer.borderWidth = 2;
    self.doneTable.layer.borderColor = SWHexRGBA(0x024DFFFF).CGColor;
    self.doneTable.backgroundColor = UIColor.clearColor;
    [self.doneCard addSubview:self.doneTable];

    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [SWHexRGBA(0x024DFFFF) colorWithAlphaComponent:0.40];
    [self.doneTable addSubview:divider];

    self.doneArchiveTitle = [UILabel new];
    self.doneArchiveTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneArchiveTitle.text = @"Archive";
    self.doneArchiveTitle.textColor = UIColor.blackColor;
    self.doneArchiveTitle.font = SWFont(17, UIFontWeightRegular);
    self.doneArchiveTitle.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneArchiveTitle];

    self.doneArchiveValue = [UILabel new];
    self.doneArchiveValue.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneArchiveValue.text = @"0";
    self.doneArchiveValue.textColor = UIColor.blackColor;
    self.doneArchiveValue.font = SWFont(40, UIFontWeightSemibold);
    self.doneArchiveValue.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneArchiveValue];

    self.doneKeepTitle = [UILabel new];
    self.doneKeepTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneKeepTitle.text = @"Keep";
    self.doneKeepTitle.textColor = UIColor.blackColor;
    self.doneKeepTitle.font = SWFont(17, UIFontWeightRegular);
    self.doneKeepTitle.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneKeepTitle];

    self.doneKeepValue = [UILabel new];
    self.doneKeepValue.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneKeepValue.text = @"0";
    self.doneKeepValue.textColor = UIColor.blackColor;
    self.doneKeepValue.font = SWFont(40, UIFontWeightSemibold);
    self.doneKeepValue.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneKeepValue];

    self.nextAlbumBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextAlbumBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.nextAlbumBtn.backgroundColor = SWHexRGBA(0x024DFFFF);
    self.nextAlbumBtn.layer.cornerRadius = 16;
    self.nextAlbumBtn.titleLabel.font = SWFont(17, UIFontWeightRegular);
    [self.nextAlbumBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.nextAlbumBtn addTarget:self action:@selector(onNextAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.doneCard addSubview:self.nextAlbumBtn];

    self.viewArchivedBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.viewArchivedBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.viewArchivedBtn.backgroundColor = SWHexRGBA(0xF6F6F6FF);
    self.viewArchivedBtn.layer.cornerRadius = 16;
    self.viewArchivedBtn.titleLabel.font = SWFont(17, UIFontWeightMedium);
    [self.viewArchivedBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [self.viewArchivedBtn addTarget:self action:@selector(onViewArchived) forControlEvents:UIControlEventTouchUpInside];
    [self.doneCard addSubview:self.viewArchivedBtn];

    // doneCard padding: L/R 25, T/B 30
    [NSLayoutConstraint activateConstraints:@[
        [self.doneIcon.topAnchor constraintEqualToAnchor:self.doneCard.topAnchor constant:30],
        [self.doneIcon.centerXAnchor constraintEqualToAnchor:self.doneCard.centerXAnchor],
        [self.doneIcon.widthAnchor constraintEqualToConstant:80],
        [self.doneIcon.heightAnchor constraintEqualToConstant:80],

        [self.doneTitleLabel.topAnchor constraintEqualToAnchor:self.doneIcon.bottomAnchor constant:20],
        [self.doneTitleLabel.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:25],
        [self.doneTitleLabel.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-25],

        [self.doneTable.topAnchor constraintEqualToAnchor:self.doneTitleLabel.bottomAnchor constant:30],
        [self.doneTable.centerXAnchor constraintEqualToAnchor:self.doneCard.centerXAnchor],
        [self.doneTable.widthAnchor constraintEqualToConstant:280],
        [self.doneTable.heightAnchor constraintEqualToConstant:100],

        [divider.centerXAnchor constraintEqualToAnchor:self.doneTable.centerXAnchor],
        [divider.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:12],
        [divider.bottomAnchor constraintEqualToAnchor:self.doneTable.bottomAnchor constant:-12],
        [divider.widthAnchor constraintEqualToConstant:1],

        // Left column
        [self.doneArchiveTitle.centerXAnchor constraintEqualToAnchor:self.doneTable.leadingAnchor constant:70],
        [self.doneArchiveTitle.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:14],
        [self.doneArchiveValue.centerXAnchor constraintEqualToAnchor:self.doneArchiveTitle.centerXAnchor],
        [self.doneArchiveValue.topAnchor constraintEqualToAnchor:self.doneArchiveTitle.bottomAnchor constant:6],

        // Right column
        [self.doneKeepTitle.centerXAnchor constraintEqualToAnchor:self.doneTable.trailingAnchor constant:-70],
        [self.doneKeepTitle.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:14],
        [self.doneKeepValue.centerXAnchor constraintEqualToAnchor:self.doneKeepTitle.centerXAnchor],
        [self.doneKeepValue.topAnchor constraintEqualToAnchor:self.doneKeepTitle.bottomAnchor constant:6],

        [self.nextAlbumBtn.topAnchor constraintEqualToAnchor:self.doneTable.bottomAnchor constant:30],
        [self.nextAlbumBtn.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:25],
        [self.nextAlbumBtn.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-25],
        [self.nextAlbumBtn.heightAnchor constraintEqualToConstant:52],

        [self.viewArchivedBtn.topAnchor constraintEqualToAnchor:self.nextAlbumBtn.bottomAnchor constant:15],
        [self.viewArchivedBtn.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:25],
        [self.viewArchivedBtn.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-25],
        [self.viewArchivedBtn.heightAnchor constraintEqualToConstant:52],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // update gradient frame
    for (CALayer *layer in self.topGradientView.layer.sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class]) {
            layer.frame = self.topGradientView.bounds;
        }
    }

    // bottom bar height includes safeBottom
    if (@available(iOS 11.0, *)) {
        CGFloat safeBottom = self.view.safeAreaInsets.bottom;
        self.bottomBarHeightC.constant = 120 + safeBottom;
    }
}

#pragma mark - Data / Notifications

- (void)handleUpdate {
    if (self.cardAnimating) return;
    if (self.sw_actionLocked) return;

    if (!self.isViewLoaded || self.view.window == nil) {
        self.sw_needsRefreshOnAppear = YES;
        return;
    }

    if (self.reloadScheduled) return;
    self.reloadScheduled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.reloadScheduled = NO;
        if (self.cardAnimating) return;
        if (!self.isViewLoaded || self.view.window == nil) return;
        [self reloadFromManagerAndRender:NO];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.sw_needsRefreshOnAppear) {
        self.sw_needsRefreshOnAppear = NO;
        [self reloadFromManagerAndRender:NO];
    }
}

- (void)sw_refreshVisibleThumbCells {
    NSArray<NSIndexPath *> *ips = self.thumbs.indexPathsForVisibleItems;
    for (NSIndexPath *ip in ips) {
        if (ip.item < 0 || ip.item >= (NSInteger)self.allAssetIDs.count) continue;
        SwipeThumbCell *cell = (SwipeThumbCell *)[self.thumbs cellForItemAtIndexPath:ip];
        if (!cell) continue;

        NSString *aid = self.allAssetIDs[ip.item];
        SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
        BOOL processed = (st != SwipeAssetStatusUnknown);

        cell.imageView.alpha = processed ? 0.2 : 1.0;
        cell.checkIcon.hidden = !processed;
    }
}

- (void)reloadFromManagerAndRender:(BOOL)firstTime {
    SwipeManager *mgr = [SwipeManager shared];

    SwipeModule *latest = nil;
    for (SwipeModule *m in mgr.modules) {
        if ([m.moduleID isEqualToString:self.module.moduleID]) { latest = m; break; }
    }
    if (latest) self.module = latest;

    self.titleLabel.text = self.module.title ?: @"Album";
    
    NSArray<NSString *> *newAll = self.module.assetIDs ?: @[];
    BOOL idsChanged = (self.allAssetIDs == nil) || ![self.allAssetIDs isEqualToArray:newAll];

    self.allAssetIDs = newAll;

    if (idsChanged) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self.thumbs reloadData];
            [self.thumbs layoutIfNeeded];
            [CATransaction commit];
        }];
    }

    [self.unprocessedIDs removeAllObjects];
    for (NSString *aid in self.allAssetIDs) {
        if ([mgr statusForAssetID:aid] == SwipeAssetStatusUnknown) {
            [self.unprocessedIDs addObject:aid];
        }
    }
    
    if (!self.sw_pendingSortJumpToFirst) {
        NSString *cursor = [mgr currentUnprocessedAssetIDForModuleID:self.module.moduleID];
        if (cursor.length > 0) {
            NSUInteger idx = [self.unprocessedIDs indexOfObject:cursor];
            if (idx != NSNotFound && idx != 0) {
                NSString *target = self.unprocessedIDs[idx];
                [self.unprocessedIDs removeObjectAtIndex:idx];
                [self.unprocessedIDs insertObject:target atIndex:0];
            }
        }
    }

    if (!self.sw_pendingSortJumpToFirst && self.focusAssetID.length > 0) {
        NSUInteger idx = [self.unprocessedIDs indexOfObject:self.focusAssetID];
        if (idx != NSNotFound && idx != 0) {
            NSString *target = self.unprocessedIDs[idx];
            [self.unprocessedIDs removeObjectAtIndex:idx];
            [self.unprocessedIDs insertObject:target atIndex:0];
        }
        [mgr setCurrentUnprocessedAssetID:self.focusAssetID forModuleID:self.module.moduleID];
        self.focusAssetID = nil;
    }
    
    NSString *topID = self.unprocessedIDs.firstObject;
    [mgr setCurrentUnprocessedAssetID:(topID.length ? topID : @"")
                          forModuleID:self.module.moduleID];

    if (self.sw_pendingSortJumpToFirst) {
        self.sw_pendingSortJumpToFirst = NO;
        [self scrollThumbsToTopIfNeededAnimated:NO];
    }

    [self updateTopUIFromManager];

    [self sw_refreshVisibleThumbCells];

    BOOL done = (self.unprocessedIDs.count == 0);
    [self showDoneState:done];

    if (done) {
        for (SwipeCardView *c in self.cards) {
            c.userInteractionEnabled = NO;
            c.hidden = YES;
        }
        return;
    }
    [self sw_applyTop3CardsAnimated:!firstTime];
}

- (void)updateTopUIFromManager {
    SwipeManager *mgr = [SwipeManager shared];

    NSUInteger total = [mgr totalCountInModule:self.module];
    NSUInteger processed = [mgr processedCountInModule:self.module];

    double percent = (total > 0) ? ((double)processed / (double)total) : 0;
    NSInteger pct = (NSInteger)llround(percent * 100.0);
    self.percentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

    BOOL done = (processed >= total && total > 0);

    // Files 富文本
    NSMutableAttributedString *att = [NSMutableAttributedString new];

    NSDictionary *kFiles = @{
        NSForegroundColorAttributeName: UIColor.blackColor,
        NSFontAttributeName: SWFont(15, UIFontWeightRegular)
    };
    NSDictionary *kNum = @{
        NSForegroundColorAttributeName: UIColor.blackColor,
        NSFontAttributeName: SWFont(15, UIFontWeightMedium)
    };

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:@"Files: " attributes:kFiles]];
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu", (unsigned long)total] attributes:kNum]];

    if (done) {
        uint64_t bytes = [mgr archivedBytesInModule:self.module];

        NSDictionary *kFree = @{
            NSForegroundColorAttributeName: UIColor.blackColor,
            NSFontAttributeName: SWFont(15, UIFontWeightRegular)
        };
        NSDictionary *kBytes = @{
            NSForegroundColorAttributeName: SWHexRGBA(0x024DFFFF),
            NSFontAttributeName: SWFont(15, UIFontWeightMedium)
        };

        [att appendAttributedString:[[NSAttributedString alloc] initWithString:@" Can free up " attributes:kFree]];
        [att appendAttributedString:[[NSAttributedString alloc] initWithString:SWHumanBytesNoSpace(bytes) attributes:kBytes]];
    }

    self.filesLabel.attributedText = att;
}

#pragma mark - Done State

- (void)showDoneState:(BOOL)done {
    self.doneCard.hidden = !done;
    self.cardsHost.hidden = done;
    self.archiveBtn.hidden = done;
    self.keepBtn.hidden = done;

    if (!done) return;

    SwipeManager *mgr = [SwipeManager shared];

    NSUInteger archived = [mgr archivedCountInModule:self.module];
    NSUInteger kept = 0;
    // 如果 manager 有 keptCountInModule: 用它，否则用 processed-archived 兜底
    SEL sel = NSSelectorFromString(@"keptCountInModule:");
    if ([mgr respondsToSelector:sel]) {
        NSUInteger (*func)(id, SEL, id) = (void *)[mgr methodForSelector:sel];
        kept = func(mgr, sel, self.module);
    } else {
        NSUInteger total = [mgr totalCountInModule:self.module];
        NSUInteger processed = [mgr processedCountInModule:self.module];
        NSUInteger archived2 = [mgr archivedCountInModule:self.module];
        kept = (processed >= archived2) ? (processed - archived2) : 0;
    }

    self.doneArchiveValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)archived];
    self.doneKeepValue.text    = [NSString stringWithFormat:@"%lu", (unsigned long)kept];

    // Next album text
    SwipeModule *next = nil;

    if (self.module.type == SwipeModuleTypeMonth) {
        next = [self nextMonthModuleAfterCurrentMonthModuleIfPossible];
    } else if (self.module.type == SwipeModuleTypeRecentDay) {

        NSString *curYMD = SWDayKeyFromModule(self.module) ?: @"";
        if (SWIsWithinLastNDays(curYMD, 7)) {
            next = [self nextRecentDayModuleWithinLast7DaysAfterCurrentIfPossible];
        } else {
            next = nil;
        }
    }

    if (next) {
        if (next.type == SwipeModuleTypeMonth) {
            NSString *t = [NSString stringWithFormat:@"Next Album > %@", (next.title.length ? next.title : @"Next")];
            [self.nextAlbumBtn setTitle:t forState:UIControlStateNormal];
        } else if (next.type == SwipeModuleTypeRecentDay) {
            NSString *ymd = SWDayKeyFromModule(next) ?: @"";
            NSString *wk = SWWeekdayFromYMD(ymd);
            if (wk.length == 0) wk = (next.title.length ? next.title : @"Next");
            NSString *t = [NSString stringWithFormat:@"Next Album > %@", wk];
            [self.nextAlbumBtn setTitle:t forState:UIControlStateNormal];
        } else {
            [self.nextAlbumBtn setTitle:@"Next Album" forState:UIControlStateNormal];
        }
        self.nextAlbumBtn.hidden = NO;
    } else {
        self.nextAlbumBtn.hidden = YES;
    }


    // Total archived bytes
    uint64_t totalBytes = (uint64_t)[[SwipeManager shared] totalArchivedBytesCached];
    NSString *btnTitle = [NSString stringWithFormat:@"View Archived Files(%@)", SWHumanBytesNoSpace(totalBytes)];
    [self.viewArchivedBtn setTitle:btnTitle forState:UIControlStateNormal];
}

- (SwipeModule *)nextMonthModuleAfterCurrentMonthModuleIfPossible {
    // 只在“当前模块是月份模块”时给 next（否则隐藏）
    if (self.module.type != SwipeModuleTypeMonth) return nil;

    NSArray *all = [SwipeManager shared].modules ?: @[];
    NSMutableArray<SwipeModule *> *months = [NSMutableArray array];
    for (SwipeModule *m in all) {
        if (m.type == SwipeModuleTypeMonth) [months addObject:m];
    }
    if (months.count == 0) return nil;

    // subtitle "YYYY-MM" 倒序（最新->最旧）
    [months sortUsingComparator:^NSComparisonResult(SwipeModule * _Nonnull a, SwipeModule * _Nonnull b) {
        NSString *ka = SWMonthKeyFromModule(a) ?: @"";
        NSString *kb = SWMonthKeyFromModule(b) ?: @"";
        return [kb compare:ka options:NSNumericSearch]; // 最新 -> 最旧
    }];

    NSInteger idx = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)months.count; i++) {
        if ([months[i].moduleID isEqualToString:self.module.moduleID]) { idx = i; break; }
    }
    if (idx == NSNotFound) return nil;

    NSInteger nextIdx = idx + 1; // 下一个更旧的月份
    if (nextIdx >= (NSInteger)months.count) return nil;

    return months[nextIdx];
}

- (SwipeModule *)nextRecentDayModuleWithinLast7DaysAfterCurrentIfPossible {
    if (self.module.type != SwipeModuleTypeRecentDay) return nil;

    NSArray *all = [SwipeManager shared].modules ?: @[];
    NSMutableArray<SwipeModule *> *recent = [NSMutableArray array];

    // 只保留 RecentDay 且 subtitle(YYYY-MM-DD) 在最近 7 天内
    for (SwipeModule *m in all) {
        if (m.type != SwipeModuleTypeRecentDay) continue;
        NSString *ymd = SWDayKeyFromModule(m) ?: @"";
        if (SWIsWithinLastNDays(ymd, 7)) {
            [recent addObject:m];
        }
    }
    if (recent.count == 0) return nil;

    // 按日期倒序：最新 -> 最旧（subtitle 是 YYYY-MM-DD）
    [recent sortUsingComparator:^NSComparisonResult(SwipeModule * _Nonnull a, SwipeModule * _Nonnull b) {
        NSString *ka = SWDayKeyFromModule(a) ?: @"";
        NSString *kb = SWDayKeyFromModule(b) ?: @"";
        return [kb compare:ka options:NSNumericSearch]; // 最新 -> 最旧
    }];

    NSInteger idx = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)recent.count; i++) {
        if ([recent[i].moduleID isEqualToString:self.module.moduleID]) { idx = i; break; }
    }
    if (idx == NSNotFound) return nil;

    NSInteger nextIdx = idx + 1; // “下一个”取更旧那天（与 Month 的逻辑一致）
    if (nextIdx >= (NSInteger)recent.count) return nil;

    return recent[nextIdx];
}

#pragma mark - Card Stack

- (void)sw_refreshCardStackAfterRemovingTopAnimated:(BOOL)animated completion:(void(^)(void))completion {

    if (self.unprocessedIDs.count == 0) {
        [self updateTopUIFromManager];
        [self showDoneState:YES];
        if (completion) completion();
        return;
    }
    [self showDoneState:NO];

    if (self.cards.count < 3) {
        [self sw_applyTop3CardsAnimated:NO];
        [self updateTopUIFromManager];
        [self scrollThumbsToTopIfNeededAnimated:animated];
        if (completion) completion();
        return;
    }

    SwipeCardView *oldTop    = self.cards[0];
    SwipeCardView *oldMid    = self.cards[1];
    SwipeCardView *oldBottom = self.cards[2];

    // 轮转：mid->top, bottom->mid, oldTop->bottom(复用)
    self.cards[0] = oldMid;
    self.cards[1] = oldBottom;
    self.cards[2] = oldTop;

    // ✅把所有卡状态先清干净
    for (SwipeCardView *c in self.cards) {
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:c];
        c.transform = CGAffineTransformIdentity;
        c.hintLabel.alpha = 0;
        c.alpha = 1.0;
    }

    // ✅关键：oldTop 刚刚飞出屏幕 —— 复用它做 bottom 时，必须“瞬移到栈底并隐藏”，不能参与动画回归
    oldTop.hidden = YES;
    oldTop.alpha = 0.0;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        oldTop.frame = SWCardFrameForIndex(2);
        [CATransaction commit];
    }];

    // newBottom = unprocessed[2]
    NSString *newBottomAid = (self.unprocessedIDs.count >= 3) ? self.unprocessedIDs[2] : nil;
    if (newBottomAid.length) {
        if (![self.cards[2].assetID isEqualToString:newBottomAid]) {
              self.cards[2].assetID = newBottomAid;
              self.cards[2].imageView.image = nil;
              [self loadImageForAssetID:newBottomAid
                          intoImageView:self.cards[2].imageView
                             targetSize:SWCardFrameForIndex(2).size];
          }
    }

    // zOrder
    [self.cardsHost bringSubviewToFront:self.cards[2]]; // bottom
    [self.cardsHost bringSubviewToFront:self.cards[1]]; // mid
    [self.cardsHost bringSubviewToFront:self.cards[0]]; // top

    // ✅只动画“剩下的两张上移”，bottom 复用卡不做从屏外回来的动画
    void (^applyFrames)(void) = ^{
        self.cards[0].frame = SWCardFrameForIndex(0); // oldMid -> top
        self.cards[1].frame = SWCardFrameForIndex(1); // oldBottom -> mid
        self.cards[2].frame = SWCardFrameForIndex(2); // oldTop 已经在底部了（无可见移动）
    };

    void (^finish)(void) = ^{
        [self sw_updateStackVisibility];
        [self updateTopUIFromManager];
        [self scrollThumbsToTopIfNeededAnimated:animated];

        // ✅新 bottom（复用的 oldTop）最后再淡入出现
        if (newBottomAid.length) {
            oldTop.hidden = NO;
            [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                oldTop.alpha = 1.0;
            } completion:nil];
        } else {
            oldTop.hidden = YES;
            oldTop.alpha = 0.0;
        }

        [self attachPanToTopCard];
        if (completion) completion();
    };

    if (!animated) {
        applyFrames();
        finish();
        return;
    }

    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        applyFrames();
    } completion:^(__unused BOOL finished) {
        finish();
    }];
}

static inline CGRect SWCardFrameForIndex(NSInteger idx) {
    // cardArea: 330x543
    // bottom: 256x416 at y=0
    // middle: 320x520 at y=12
    // top:    330x520 at y=23
    if (idx == 0) { // top
        return CGRectMake(0, 23, 330, 520);
    } else if (idx == 1) { // middle
        return CGRectMake((330 - 320)/2.0, 12, 320, 520);
    } else { // bottom
        return CGRectMake((330 - 256)/2.0, 0, 256, 416);
    }
}

- (void)rebuildCardStackIfNeeded:(BOOL)firstTime {
    // 清空 cardsHost
    for (UIView *v in self.cardsHost.subviews) [v removeFromSuperview];
    [self.cards removeAllObjects];

    NSInteger count = MIN(3, (NSInteger)self.unprocessedIDs.count);
    for (NSInteger i = count - 1; i >= 0; i--) {
        NSString *aid = self.unprocessedIDs[i];

        CGRect f = SWCardFrameForIndex(i);
        SwipeCardView *card = [[SwipeCardView alloc] initWithFrame:f];
        card.assetID = aid;
        [self.cardsHost addSubview:card];
        [self.cards addObject:card];

        [self loadImageForAssetID:aid intoImageView:card.imageView targetSize:f.size];

        card.userInteractionEnabled = NO;
    }

    // cards 数组现在是 [bottom, middle, top]? 我们希望 0=top
    // 上面 add 的顺序是 i=count-1..0，最后加入的是 top，cards 内顺序是 [bottom, middle, top]
    // 调整为 0=top
    self.cards = [[[self.cards reverseObjectEnumerator] allObjects] mutableCopy];

    [self attachPanToTopCard];
    [self layoutCardsAnimated:NO];
}

- (void)attachPanToTopCard {
    for (SwipeCardView *c in self.cards) {
        c.userInteractionEnabled = NO;
        for (UIGestureRecognizer *gr in c.gestureRecognizers.copy) {
            [c removeGestureRecognizer:gr];
        }
    }
    SwipeCardView *top = self.cards.firstObject;
    if (!top) return;

    top.userInteractionEnabled = YES;
    self.topPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [top addGestureRecognizer:self.topPan];
}

- (void)layoutCardsAnimated:(BOOL)animated {
    void (^applyFrames)(void) = ^{
        for (NSInteger i = 0; i < self.cards.count; i++) {
            SwipeCardView *card = self.cards[i];
            CGRect f = SWCardFrameForIndex(i);
            card.transform = CGAffineTransformIdentity;
            card.frame = f;
            card.hintLabel.alpha = 0;
        }
    };

    if (!animated) {
        applyFrames();
        return;
    }

    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        applyFrames();
    } completion:nil];
}

#pragma mark - Gesture & Actions

- (void)sw_setAnchorPoint:(CGPoint)anchor forView:(UIView *)view {
    CGPoint oldOrigin = view.frame.origin;
    view.layer.anchorPoint = anchor;
    CGPoint newOrigin = view.frame.origin;

    CGPoint transition;
    transition.x = newOrigin.x - oldOrigin.x;
    transition.y = newOrigin.y - oldOrigin.y;

    view.center = CGPointMake(view.center.x - transition.x, view.center.y - transition.y);
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.cardAnimating) return;

    SwipeCardView *card = (SwipeCardView *)pan.view;
    if (!card) return;

    CGPoint t = [pan translationInView:self.cardsHost];
    CGPoint v = [pan velocityInView:self.cardsHost];

    CGFloat w = MAX(1.0, self.cardArea.bounds.size.width);
    CGFloat x = t.x;

    // 摆动“灵敏度”：更容易触发摆动
    CGFloat progress = MIN(1.0, fabs(x) / (w * 0.55));

    if (pan.state == UIGestureRecognizerStateBegan) {
        // ✅ 顶部中心支点：底部摆动更明显
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.0) forView:card];
    }

    // ✅ 顶部也要“轻微位移”：不要 1:1 跟手，做弱位移更像钟摆
    CGFloat tx = x * 0.35;                 // 顶部轻微跟随左右
    CGFloat ty = (t.y * 0.08) - progress*18; // 轻微上下 + 摆动带一点上提

    // ✅ 方向修正：右滑要顺时针 => rotation 为负
    CGFloat maxAngle = (CGFloat)(M_PI / 10.0); // 18°
    CGFloat rot = -(x / w) * maxAngle;

    CGAffineTransform tr = CGAffineTransformIdentity;
    tr = CGAffineTransformTranslate(tr, tx, ty);
    tr = CGAffineTransformRotate(tr, rot);
    card.transform = tr;

    // hint
    if (x > 25) {
        card.hintLabel.text = @"Keep";
        card.hintLabel.alpha = MIN(1.0, x / 120.0);
    } else if (x < -25) {
        card.hintLabel.text = @"Archive";
        card.hintLabel.alpha = MIN(1.0, -x / 120.0);
    } else {
        card.hintLabel.alpha = 0;
    }

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {

        // ✅ 先判断“快速甩动”，快速滑动也要适配
        CGFloat vx = v.x;

        BOOL flingRight = (vx > 900);
        BOOL flingLeft  = (vx < -900);

        // ✅ 再判断“位移阈值”，灵敏度稍微高一点
        CGFloat threshold = w * 0.35;

        if (flingRight || x > threshold) {
            [self commitTopCardArchived:NO velocity:v];
            return;
        }
        if (flingLeft || x < -threshold) {
            [self commitTopCardArchived:YES velocity:v];
            return;
        }

        // ✅ 回弹：先把 transform 回到 identity（保持顶部支点）
        [UIView animateWithDuration:0.22
                              delay:0
             usingSpringWithDamping:0.9
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            card.transform = CGAffineTransformIdentity;
            card.hintLabel.alpha = 0;
        } completion:^(__unused BOOL finished) {

            // ✅ 回弹结束再把支点复位到中心，避免“中途改 anchor 抖一下”
            [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:card];
            [self layoutCardsAnimated:YES];
        }];
    }
}

- (void)onArchiveBtn { [self commitTopCardArchived:YES velocity:CGPointZero]; }
- (void)onKeepBtn    { [self commitTopCardArchived:NO  velocity:CGPointZero]; }

- (void)commitTopCardArchived:(BOOL)archived velocity:(CGPoint)velocity {
    if (self.cardAnimating) return; // ✅ 防连点 / 防重复
    SwipeCardView *top = self.cards.firstObject;
    if (!top) return;

    self.cardAnimating = YES;

    // ✅ 如果手势结束时支点已复位，这里确保是顶部中心（钟摆飞出一致）
    [self sw_setAnchorPoint:CGPointMake(0.5, 0.0) forView:top];

    // 预取下一张（更稳）
    NSString *prefetchAid = (self.unprocessedIDs.count >= 4) ? self.unprocessedIDs[3] : nil;
    if (prefetchAid.length) {
        [self sw_prefetchCardImageForAssetID:prefetchAid targetSize:SWCardFrameForIndex(2).size];
    }

    top.userInteractionEnabled = NO;
    self.archiveBtn.userInteractionEnabled = NO;
    self.keepBtn.userInteractionEnabled = NO;

    CGFloat dir = archived ? -1.0 : 1.0;

    // ✅ 飞出：x 方向更大，y 给一点“向下/斜飞”的趋势（更像从顶部甩出去）
    CGFloat viewW = self.view.bounds.size.width;
    CGFloat offX = dir * (viewW * 1.35) + velocity.x * 0.22; // 甩得快飞更远
    CGFloat offY = velocity.y * 0.01;

    // ✅ 额外旋转：右滑顺时针（负角度）
    CGFloat extraRot = -dir * (CGFloat)(M_PI / 8.5);

    [UIView animateWithDuration:0.28
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        top.center = CGPointMake(top.center.x + offX, top.center.y + offY);
        top.transform = CGAffineTransformRotate(top.transform, extraRot);
        top.alpha = 0.0;
    } completion:^(__unused BOOL finished) {

        NSString *aid = top.assetID ?: @"";

        // ✅ 飞出后立刻隐藏+清图，避免复用时“像回到底部”
        top.hidden = YES;
        top.imageView.image = nil;
        top.alpha = 1.0;
        top.transform = CGAffineTransformIdentity;
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:top];

        SwipeAssetStatus st = archived ? SwipeAssetStatusArchived : SwipeAssetStatusKept;
        [[SwipeManager shared] setStatus:st forAssetID:aid sourceModule:self.module.moduleID recordUndo:YES];

        [self sw_updateThumbForAssetIDNoFlicker:aid];

        // 更新本地队列
        if (self.unprocessedIDs.count > 0 && [self.unprocessedIDs.firstObject isEqualToString:aid]) {
            [self.unprocessedIDs removeObjectAtIndex:0];
        } else {
            [self.unprocessedIDs removeObject:aid];
        }

        NSString *topID = self.unprocessedIDs.firstObject;
        [[SwipeManager shared] setCurrentUnprocessedAssetID:(topID.length ? topID : @"")
                                                forModuleID:self.module.moduleID];

        // ✅ 刷新卡堆（轮转复用）
        [self sw_refreshCardStackAfterRemovingTopAnimated:YES completion:^{
            self.archiveBtn.userInteractionEnabled = YES;
            self.keepBtn.userInteractionEnabled = YES;
            self.cardAnimating = NO; // ✅ 动画真正结束才解锁
        }];
    }];
}

- (void)sw_prefetchCardImageForAssetID:(NSString *)assetID targetSize:(CGSize)targetSize {
    if (assetID.length == 0) return;

    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize ts = CGSizeMake(targetSize.width * scale, targetSize.height * scale);

    // 如果你的 imageManager 是 PHCachingImageManager，直接走缓存接口最好
    if ([self.imageManager isKindOfClass:PHCachingImageManager.class]) {
        [(PHCachingImageManager *)self.imageManager startCachingImagesForAssets:@[asset]
                                                                    targetSize:ts
                                                                   contentMode:PHImageContentModeAspectFill
                                                                       options:nil];
        return;
    }

    // 否则退化为“预请求一次”来暖缓存（回调不用管）
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;

    [self.imageManager requestImageForAsset:asset
                                 targetSize:ts
                                contentMode:PHImageContentModeAspectFill
                                    options:opt
                              resultHandler:^(__unused UIImage * _Nullable result,
                                              __unused NSDictionary * _Nullable info) {
        // no-op: 只为预热缓存
    }];
}

- (void)sw_updateThumbForAssetIDNoFlicker:(NSString *)aid {
    if (aid.length == 0) return;

    NSUInteger idx = [self.allAssetIDs indexOfObject:aid];
    if (idx == NSNotFound) return;

    NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];
    SwipeThumbCell *cell = (SwipeThumbCell *)[self.thumbs cellForItemAtIndexPath:ip];

    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    BOOL processed = (st != SwipeAssetStatusUnknown);

    if (cell) {
        cell.imageView.alpha = processed ? 0.2 : 1.0;
        cell.checkIcon.hidden = !processed;
        return;
    }

    [self sw_reloadThumbForAssetIDNoFlicker:aid];
}

#pragma mark - Buttons (Undo / Sort / Nav)

- (void)onBack {
    UINavigationController *nav = [self sw_currentNav];
    if (!nav) return;
    [nav popViewControllerAnimated:YES];
}

- (void)undoTapped {
    if (self.cardAnimating) return;
    if (self.sw_actionLocked) return;

    NSString *undoneAid = [[SwipeManager shared] undoLastActionAssetIDInModuleID:self.module.moduleID];
    if (undoneAid.length == 0) return;

    // ✅ 撤回后：强制按 manager 最新应处理顺序刷新，并把 undone 置顶（用户感知更强）
    [self sw_forceRebuildFromManagerAnimated:YES keepFocusTop:undoneAid];
}

- (UIView *)sw_sortRowWithTitle:(NSString *)title selected:(BOOL)selected action:(SEL)action {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.clearColor;

    UILabel *lab = [UILabel new];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.text = title;
    lab.textColor = UIColor.whiteColor;
    lab.font = SWFont(18, UIFontWeightSemibold);
    [row addSubview:lab];

    UIImageView *check = [UIImageView new];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.contentMode = UIViewContentModeScaleAspectFit;
    check.image = [UIImage imageNamed:@"ic_j"];
    check.hidden = !selected;
    [row addSubview:check];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:18],
        [check.heightAnchor constraintEqualToConstant:18],

        [btn.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [btn.topAnchor constraintEqualToAnchor:row.topAnchor],
        [btn.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];

    return row;
}

- (void)sw_hideSortPopup {
    if (!self.sw_sortShowing) return;
    self.sw_sortShowing = NO;

    [UIView animateWithDuration:0.18 animations:^{
        self.sw_sortMask.alpha = 0.0;
        self.sw_sortPanel.alpha = 0.0;
        self.sw_sortPanel.transform = CGAffineTransformMakeTranslation(0, 6);
    } completion:^(__unused BOOL finished) {
        [self.sw_sortPanel removeFromSuperview];
        [self.sw_sortMask removeFromSuperview];
        self.sw_sortPanel = nil;
        self.sw_sortMask = nil;
    }];
}

- (void)sw_showSortPopup {
    if (self.sw_sortShowing) { [self sw_hideSortPopup]; return; }
    self.sw_sortShowing = YES;

    [self.view layoutIfNeeded];

    // mask
    UIView *mask = [UIView new];
    mask.translatesAutoresizingMaskIntoConstraints = NO;
    mask.backgroundColor = UIColor.clearColor;
    mask.alpha = 0.0;
    [self.view addSubview:mask];
    [NSLayoutConstraint activateConstraints:@[
        [mask.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mask.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mask.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mask.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.sw_sortMask = mask;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sw_hideSortPopup)];
    [mask addGestureRecognizer:tap];

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = YES;
    panel.backgroundColor = SWHexRGBA(0x8E8E8EFF);
    panel.layer.cornerRadius = 12;
    panel.layer.masksToBounds = YES;
    panel.alpha = 0.0;
    panel.transform = CGAffineTransformMakeTranslation(0, 6);
    [self.view addSubview:panel];
    self.sw_sortPanel = panel;

    // header
    UILabel *hdr = [UILabel new];
    hdr.translatesAutoresizingMaskIntoConstraints = NO;
    hdr.text = @"Sort by";
    hdr.font = SWFont(16, UIFontWeightRegular);
    hdr.textColor = SWHexRGBA(0xEBEBF599);
    [panel addSubview:hdr];

    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.15];
    [panel addSubview:line];

    BOOL asc = self.module.sortAscending;
    UIView *rowLatest = [self sw_sortRowWithTitle:@"Latest" selected:(!asc) action:@selector(sw_sortPickLatest)];
    UIView *rowOldest = [self sw_sortRowWithTitle:@"Oldest" selected:(asc)  action:@selector(sw_sortPickOldest)];
    [panel addSubview:rowLatest];
    [panel addSubview:rowOldest];

    // ✅ 先算 panel frame（锚点：sortIconBtn 上方）
    CGRect anchor = [self.sortIconBtn convertRect:self.sortIconBtn.bounds toView:self.view];
    CGFloat panelW = 220;
    CGFloat panelH = 44 + 52 + 52;

    CGFloat x = CGRectGetMaxX(anchor) - panelW;                 // 右对齐 sort 图标
    x = MIN(MAX(12, x), self.view.bounds.size.width - panelW - 12);

    CGFloat y = CGRectGetMinY(anchor) - panelH - 8;
    y = MAX(12, y);

    panel.frame = CGRectMake(x, y, panelW, panelH);

    // panel 内部约束
    [NSLayoutConstraint activateConstraints:@[
        [hdr.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [hdr.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],

        [line.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [line.topAnchor constraintEqualToAnchor:panel.topAnchor constant:44],
        [line.heightAnchor constraintEqualToConstant:1],

        [rowLatest.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [rowLatest.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [rowLatest.topAnchor constraintEqualToAnchor:panel.topAnchor constant:44],
        [rowLatest.heightAnchor constraintEqualToConstant:52],

        [rowOldest.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [rowOldest.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [rowOldest.topAnchor constraintEqualToAnchor:rowLatest.bottomAnchor],
        [rowOldest.heightAnchor constraintEqualToConstant:52],
    ]];

    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 1.0;
        panel.alpha = 1.0;
        panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)sw_forceRebuildFromManagerAnimated:(BOOL)animated keepFocusTop:(NSString *)focusIDOrNil {
    SwipeManager *mgr = [SwipeManager shared];

    // 1) 取最新 module
    SwipeModule *latest = nil;
    for (SwipeModule *m in mgr.modules) {
        if ([m.moduleID isEqualToString:self.module.moduleID]) { latest = m; break; }
    }
    if (latest) self.module = latest;

    // 2) 重新拿“排序后的展示数组”
    // ⚠️ 关键：不要依赖 idsChanged；排序后也要强制用 manager/module 的最新顺序覆盖 allAssetIDs
    NSArray<NSString *> *newAll = self.module.assetIDs ?: @[];
    self.allAssetIDs = newAll;

    // 3) 重算 unprocessedIDs（按照 allAssetIDs 的顺序筛 Unknown）
    [self.unprocessedIDs removeAllObjects];
    for (NSString *aid in self.allAssetIDs) {
        if ([mgr statusForAssetID:aid] == SwipeAssetStatusUnknown) {
            [self.unprocessedIDs addObject:aid];
        }
    }

    // 4) 若传入 focus，则把 focus 提到最前（用于撤回/点缩略图）
    if (focusIDOrNil.length > 0) {
        NSUInteger idx = [self.unprocessedIDs indexOfObject:focusIDOrNil];
        if (idx != NSNotFound && idx != 0) {
            NSString *target = self.unprocessedIDs[idx];
            [self.unprocessedIDs removeObjectAtIndex:idx];
            [self.unprocessedIDs insertObject:target atIndex:0];
        }
        [mgr setCurrentUnprocessedAssetID:focusIDOrNil forModuleID:self.module.moduleID];
    } else {
        // 否则按游标把当前未处理放在最前（保持用户进度）
        NSString *cursor = [mgr currentUnprocessedAssetIDForModuleID:self.module.moduleID];
        if (cursor.length > 0) {
            NSUInteger idx = [self.unprocessedIDs indexOfObject:cursor];
            if (idx != NSNotFound && idx != 0) {
                NSString *target = self.unprocessedIDs[idx];
                [self.unprocessedIDs removeObjectAtIndex:idx];
                [self.unprocessedIDs insertObject:target atIndex:0];
            }
        }
    }

    // 写回游标
    NSString *topID = self.unprocessedIDs.firstObject;
    [mgr setCurrentUnprocessedAssetID:(topID.length ? topID : @"") forModuleID:self.module.moduleID];

    // 顶部 UI
    [self updateTopUIFromManager];

    // Done
    BOOL done = (self.unprocessedIDs.count == 0);
    [self showDoneState:done];
    if (done) {
        for (SwipeCardView *c in self.cards) { c.hidden = YES; c.userInteractionEnabled = NO; }
    }

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        [self.thumbs reloadData];
        [self.thumbs performBatchUpdates:^{} completion:^(__unused BOOL finished) {
            [self scrollThumbsToTopIfNeededAnimated:animated];
        }];

        [CATransaction commit];
    }];

}

- (void)sortTapped {
    if (self.cardAnimating) return;
    if (self.sw_actionLocked) return;
    [self sw_showSortPopup];
}

- (void)sw_sortPickLatest {
    [self sw_hideSortPopup];

    self.sw_pendingSortJumpToFirst = YES;
    self.focusAssetID = nil;

    [[SwipeManager shared] setSortAscending:NO forModuleID:self.module.moduleID];
    // 不要立刻 rebuild，等 SwipeManagerDidUpdateNotification -> handleUpdate -> reloadFromManagerAndRender
}

- (void)sw_sortPickOldest {
    [self sw_hideSortPopup];

    self.sw_pendingSortJumpToFirst = YES;
    self.focusAssetID = nil;

    [[SwipeManager shared] setSortAscending:YES forModuleID:self.module.moduleID];
}

- (void)onNextAlbum {

    SwipeModule *next = nil;

    if (self.module.type == SwipeModuleTypeMonth) {
        next = [self nextMonthModuleAfterCurrentMonthModuleIfPossible];
    } else if (self.module.type == SwipeModuleTypeRecentDay) {
        NSString *curYMD = self.module.subtitle ?: @"";
        if (SWIsWithinLastNDays(curYMD, 7)) {
            next = [self nextRecentDayModuleWithinLast7DaysAfterCurrentIfPossible];
        }
    }

    if (!next) return;

    UINavigationController *nav = [self sw_currentNav];
    if (!nav) return;

    SwipeAlbumViewController *vc = [[SwipeAlbumViewController alloc] initWithModule:next];

    NSMutableArray<UIViewController *> *stack = nav.viewControllers.mutableCopy;
    if (stack.count > 0) {
        [stack removeLastObject];
    }
    [stack addObject:vc];
    [nav setViewControllers:stack animated:YES];
}

- (void)onViewArchived {
    UINavigationController *nav = [self sw_currentNav];
    if (!nav) return;

    ASArchivedFilesViewController *vc = [ASArchivedFilesViewController new];
    [nav pushViewController:vc animated:YES];
}

#pragma mark - Thumbs

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.allAssetIDs.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SwipeThumbCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"SwipeThumbCell" forIndexPath:indexPath];
    NSString *aid = self.allAssetIDs[indexPath.item];

    // cancel old request
    if (cell.reqId != PHInvalidImageRequestID) {
        [self.imageManager cancelImageRequest:cell.reqId];
        cell.reqId = PHInvalidImageRequestID;
    }
    cell.representedAssetID = aid;
    cell.imageView.image = nil;
    cell.imageView.alpha = 1.0;

    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    BOOL processed = (st != SwipeAssetStatusUnknown);

    cell.imageView.alpha = processed ? 0.2 : 1.0;

    cell.checkIcon.hidden = !processed;

    PHAsset *asset = [self assetForID:aid];
    if (!asset) return cell;

    CGSize target = CGSizeMake(140, 140);
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.networkAccessAllowed = YES;

    __weak typeof(cell) wcell = cell;
    cell.reqId = [self.imageManager requestImageForAsset:asset
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        __strong typeof(wcell) scell = wcell;
        if (!scell) return;

        BOOL cancelled = [info[PHImageCancelledKey] boolValue];
        NSError *err = info[PHImageErrorKey];
        if (cancelled || err) return;

        if (![scell.representedAssetID isEqualToString:aid]) return;
        if (!result) return;

        void (^apply)(void) = ^{
            if (![scell.representedAssetID isEqualToString:aid]) return;
            scell.imageView.image = result;
        };
        if ([NSThread isMainThread]) apply();
        else dispatch_async(dispatch_get_main_queue(), apply);
    }];

    return cell;
}

- (void)sw_reloadThumbForAssetIDNoFlicker:(NSString *)aid {
    if (aid.length == 0) return;
    NSUInteger idx = [self.allAssetIDs indexOfObject:aid];
    if (idx == NSNotFound) return;

    NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self.thumbs performBatchUpdates:^{
            [self.thumbs reloadItemsAtIndexPaths:@[ip]];
        } completion:nil];
        [CATransaction commit];
    }];
}

- (void)sw_updateStackVisibility {
    NSInteger n = (NSInteger)self.unprocessedIDs.count;
    if (self.cards.count < 3) return;

    // 默认全隐藏（保险）
    self.cards[0].hidden = YES; // top
    self.cards[1].hidden = YES; // mid
    self.cards[2].hidden = YES; // bottom

    if (n <= 0) return;

    // 至少 1 张：显示 top
    self.cards[0].hidden = NO;

    // 至少 2 张：显示 mid
    if (n >= 2) self.cards[1].hidden = NO;

    // 至少 3 张：显示 bottom
    if (n >= 3) self.cards[2].hidden = NO;
}

- (BOOL)sw_lockAction {
    if (self.sw_actionLocked) return NO;
    self.sw_actionLocked = YES;

    self.archiveBtn.userInteractionEnabled = NO;
    self.keepBtn.userInteractionEnabled = NO;
    self.undoIconBtn.userInteractionEnabled = NO;
    self.sortIconBtn.userInteractionEnabled = NO;

    // 也可以顺手禁掉 top 卡的交互，避免 pan 继续改 transform
    SwipeCardView *top = self.cards.firstObject;
    top.userInteractionEnabled = NO;

    return YES;
}

- (void)sw_unlockAction {
    self.sw_actionLocked = NO;

    self.archiveBtn.userInteractionEnabled = YES;
    self.keepBtn.userInteractionEnabled = YES;
    self.undoIconBtn.userInteractionEnabled = YES;
    self.sortIconBtn.userInteractionEnabled = YES;

    [self attachPanToTopCard];
}

- (void)sw_applyTop3CardsAnimated:(BOOL)animated {
    [self sw_prepare3CardsIfNeeded];

    NSArray<NSString *> *ids = (self.unprocessedIDs.count > 0)
    ? [self.unprocessedIDs subarrayWithRange:NSMakeRange(0, MIN(3, self.unprocessedIDs.count))]
    : @[];

    for (NSInteger i = 0; i < 3; i++) {
        SwipeCardView *card = self.cards[i];
        NSString *aid = (i < (NSInteger)ids.count) ? ids[i] : nil;

        if (aid.length == 0) {
            card.hidden = YES;
            continue;
        }
        card.hidden = NO;

        if (![card.assetID isEqualToString:aid]) {
            card.assetID = aid;
            card.imageView.image = nil;
            [self loadImageForAssetID:aid intoImageView:card.imageView targetSize:card.bounds.size];
        }

        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:card];
        card.alpha = 1.0;
        card.transform = CGAffineTransformIdentity;
        card.hintLabel.alpha = 0;
    }

    void (^layoutBlock)(void) = ^{
        self.cards[0].frame = SWCardFrameForIndex(0);
        self.cards[1].frame = SWCardFrameForIndex(1);
        self.cards[2].frame = SWCardFrameForIndex(2);
    };

    void (^zOrder)(void) = ^{
        [self.cardsHost bringSubviewToFront:self.cards[2]]; // bottom
        [self.cardsHost bringSubviewToFront:self.cards[1]]; // mid
        [self.cardsHost bringSubviewToFront:self.cards[0]]; // top
    };

    void (^finish)(void) = ^{
        zOrder();
        [self sw_updateStackVisibility];
        [self attachPanToTopCard];
    };

    if (!animated) {
        layoutBlock();
        finish();
        return;
    }

    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        layoutBlock();
    } completion:^(__unused BOOL finished) {
        finish();
    }];
}

- (void)sw_prepare3CardsIfNeeded {
    if (self.cards.count == 3) return;

    // 先清理（仅首次或你之前已重建过）
    for (UIView *v in self.cardsHost.subviews) [v removeFromSuperview];
    [self.cards removeAllObjects];

    // 添加顺序：bottom -> mid -> top（z 叠放正确）
    SwipeCardView *bottom = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(2)];
    SwipeCardView *mid    = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(1)];
    SwipeCardView *top    = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(0)];

    bottom.hidden = YES; mid.hidden = YES; top.hidden = YES;

    [self.cardsHost addSubview:bottom];
    [self.cardsHost addSubview:mid];
    [self.cardsHost addSubview:top];

    // 固定数组语义：0=top, 1=mid, 2=bottom
    [self.cards addObject:top];
    [self.cards addObject:mid];
    [self.cards addObject:bottom];

    [self attachPanToTopCard];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(60, 60);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *aid = self.allAssetIDs[indexPath.item];
    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    if (st != SwipeAssetStatusUnknown) return; // 只允许跳到未处理

    self.focusAssetID = aid;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:aid forModuleID:self.module.moduleID];
    [self reloadFromManagerAndRender:NO];
}

- (void)scrollThumbsToTopIfNeededAnimated:(BOOL)animated {
    NSString *topAid = self.unprocessedIDs.firstObject;
    if (topAid.length == 0) return;

    NSUInteger idx = [self.allAssetIDs indexOfObject:topAid];
    if (idx == NSNotFound) return;

    NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];

    // 关键：确保 reload/layout 完成后再滚
    [self.thumbs layoutIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger items = [self.thumbs numberOfItemsInSection:0];
        if (ip.item < 0 || ip.item >= items) return;
        [self.thumbs scrollToItemAtIndexPath:ip
                            atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                    animated:animated];
    });
}

#pragma mark - Image loading

- (PHAsset *)assetForID:(NSString *)assetID {
    if (assetID.length == 0) return nil;

    PHAsset *a = [self.assetCache objectForKey:assetID];
    if (a) return a;

    // 优先用 manager 的缓存（你已有）
    if ([[SwipeManager shared] respondsToSelector:@selector(assetForID:)]) {
        a = [[SwipeManager shared] assetForID:assetID];
        if (a) {
            [self.assetCache setObject:a forKey:assetID];
            return a;
        }
    }

    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetID] options:nil];
    a = r.firstObject;
    if (a) [self.assetCache setObject:a forKey:assetID];
    return a;
}

- (void)loadImageForAssetID:(NSString *)assetID intoImageView:(UIImageView *)iv targetSize:(CGSize)size {
    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return;

    NSString *expected = [assetID copy];

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(size.width * scale, size.height * scale);

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.networkAccessAllowed = YES;

    __weak UIImageView *wiv = iv;

    [self.imageManager requestImageForAsset:asset
                                 targetSize:target
                                contentMode:PHImageContentModeAspectFill
                                    options:opt
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;

        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIImageView *siv = wiv;
            if (!siv) return;

            if ([siv.superview isKindOfClass:SwipeCardView.class]) {
                SwipeCardView *card = (SwipeCardView *)siv.superview;
                if (![card.assetID isEqualToString:expected]) return;
            }

            if (degraded) {
                if (!siv.image) siv.image = result;
                return;
            }
            siv.image = result;
        });
    }];
}


@end
