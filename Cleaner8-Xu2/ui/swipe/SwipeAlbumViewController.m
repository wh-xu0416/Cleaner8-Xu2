#import "SwipeAlbumViewController.h"
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

#import "SwipeManager.h"
#import "ASArchivedFilesViewController.h"
#import "Common.h"
#import <CoreImage/CoreImage.h>


static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / SWDesignWidth());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}

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

// 给 RecentDay 的 next 按钮标题
static inline NSString *SWNextRecentTitle(NSString *ymd) {
    if (ymd.length >= 10) return [NSString stringWithFormat:NSLocalizedString(@"Next Album > %@", nil), ymd];
    return NSLocalizedString(@"Next Album", nil);
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

@interface UIImage (Blur)

- (UIImage *)applyGaussianBlurWithRadius:(CGFloat)radius;

@end

@implementation UIImage (Blur)

- (UIImage *)applyGaussianBlurWithRadius:(CGFloat)radius {
    if (radius <= 0.01) return self;

    CIImage *input = [[CIImage alloc] initWithImage:self];
    if (!input) return self;

    CGRect extent = input.extent;

    // 防止边缘透明/黑边
    CIFilter *clamp = [CIFilter filterWithName:@"CIAffineClamp"];
    [clamp setValue:input forKey:kCIInputImageKey];
    [clamp setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformIdentity] forKey:@"inputTransform"];
    CIImage *clamped = clamp.outputImage ?: input;

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:clamped forKey:kCIInputImageKey];
    [blur setValue:@(radius) forKey:kCIInputRadiusKey];

    CIImage *blurred = blur.outputImage;
    if (!blurred) return self;

    CIImage *cropped = [blurred imageByCroppingToRect:extent];

    static CIContext *ctx = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ctx = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer : @NO }];
    });

    CGImageRef cg = [ctx createCGImage:cropped fromRect:extent];
    if (!cg) return self;

    UIImage *out = [UIImage imageWithCGImage:cg scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(cg);
    return out;
}

@end

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
        self.contentView.layer.cornerRadius = SW(8);
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
            [_checkIcon.widthAnchor constraintEqualToConstant:SW(16)],
            [_checkIcon.heightAnchor constraintEqualToConstant:SW(16)],
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

@property (nonatomic, assign) PHImageRequestID reqId;
@property (nonatomic, copy) NSString *representedAssetID;
@property (nonatomic, strong) UIImage *rawImage;

@property (nonatomic, assign) BOOL sw_revealWhenReady;
@end

@implementation SwipeCardView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = SW(18);
        self.layer.masksToBounds = YES;

        self.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        _reqId = PHInvalidImageRequestID;

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;

        _imageView.backgroundColor = UIColor.clearColor;

        [self addSubview:_imageView];

        _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hintLabel.textAlignment = NSTextAlignmentCenter;
        _hintLabel.font = SWFontS(34, UIFontWeightBold);
        _hintLabel.textColor = UIColor.blackColor;
        _hintLabel.alpha = 0;
        [self addSubview:_hintLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    _hintLabel.frame = CGRectMake(SW(16), SW(16), self.bounds.size.width - SW(32), SW(40));
}
@end

#pragma mark - SwipeAlbumViewController

@interface SwipeAlbumViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *cardBlurImageCache;
@property (nonatomic, strong) dispatch_queue_t sw_blurQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *sw_blurInFlight;

@property (nonatomic, assign) BOOL sw_hasOperated; // 本页是否做过任何操作
@property (nonatomic, strong) UIView *sw_exitMask;
@property (nonatomic, strong) UIView *sw_exitPopup;

@property (nonatomic, strong) UILabel *sw_exitArchiveValue;
@property (nonatomic, strong) UILabel *sw_exitKeepValue;
@property (nonatomic, strong) UIButton *sw_exitViewArchivedBtn;

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
@property (nonatomic, strong) UIView *doneCard;
@property (nonatomic, strong) UIImageView *doneIcon;
@property (nonatomic, strong) UILabel *doneTitleLabel;
@property (nonatomic, strong) UIView *doneTable;
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
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbImageCache;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *cardImageCache;

@end
static inline NSString *SWImgKey(NSString *prefix, NSString *aid, CGSize px) {
    return [NSString stringWithFormat:@"%@%@_%.0fx%.0f", prefix, aid, px.width, px.height];
}

@implementation SwipeAlbumViewController

- (instancetype)initWithModule:(SwipeModule *)module {
    if ((self = [super init])) {
        _module = module;
        _cardBlurImageCache = [NSCache new];
        _cardBlurImageCache.countLimit = 80;

        _sw_blurQueue = dispatch_queue_create("com.xiaoxu.swipe8.blur", DISPATCH_QUEUE_CONCURRENT);
        _sw_blurInFlight = [NSMutableSet set];

        _imageManager = [PHCachingImageManager new];
        _assetCache = [NSCache new];
        _assetCache.countLimit = 1000;

        _thumbImageCache = [NSCache new];
        _thumbImageCache.countLimit = 800;

        _cardImageCache = [NSCache new];
        _cardImageCache.countLimit = 80;

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
        [self.topGradientView.heightAnchor constraintEqualToConstant:SW(307)],
    ]];

    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[
        (id)SWHexRGBA(0xE0E0E0FF).CGColor,
        (id)SWHexRGBA(0x008DFF00).CGColor
    ];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint   = CGPointMake(0.5, 1.0);
    g.frame = CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, SW(307));
    [self.topGradientView.layer insertSublayer:g atIndex:0];

    // ===== Title bar =====
    self.titleBar = [UIView new];
    self.titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.titleBar];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(20)],
        [self.titleBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(20)],
        [self.titleBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
        [self.titleBar.heightAnchor constraintEqualToConstant:SW(44)],
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
        [self.backBtn.widthAnchor constraintEqualToConstant:SW(32)],
        [self.backBtn.heightAnchor constraintEqualToConstant:SW(32)],
    ]];

    self.progressRight = [UIView new];
    self.progressRight.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleBar addSubview:self.progressRight];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressRight.trailingAnchor constraintEqualToAnchor:self.titleBar.trailingAnchor],
        [self.progressRight.centerYAnchor constraintEqualToAnchor:self.titleBar.centerYAnchor],
        [self.progressRight.heightAnchor constraintEqualToConstant:SW(32)],
    ]];

    self.hotIcon = [UIImageView new];
    self.hotIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.hotIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.hotIcon.image = [UIImage imageNamed:@"ic_hot"];
    [self.progressRight addSubview:self.hotIcon];

    self.percentLabel = [UILabel new];
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLabel.textColor = UIColor.blackColor;
    self.percentLabel.font = SWFontS(20, UIFontWeightSemibold);
    self.percentLabel.text = @"0%";
    [self.progressRight addSubview:self.percentLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.hotIcon.leadingAnchor constraintEqualToAnchor:self.progressRight.leadingAnchor],
        [self.hotIcon.centerYAnchor constraintEqualToAnchor:self.progressRight.centerYAnchor],
   
        [self.hotIcon.widthAnchor constraintEqualToConstant:SW(32)],
        [self.hotIcon.heightAnchor constraintEqualToConstant:SW(32)],

        [self.percentLabel.leadingAnchor constraintEqualToAnchor:self.hotIcon.trailingAnchor constant:SW(5)],
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
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.backBtn.trailingAnchor constant:SW(12)],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.progressRight.leadingAnchor constant:-SW(12)],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.titleBar.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.titleBar.centerYAnchor],
    ]];

    self.filesLabel = [UILabel new];
    self.filesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.filesLabel.textAlignment = NSTextAlignmentCenter;
    self.filesLabel.numberOfLines = 1;
    [self.view addSubview:self.filesLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.filesLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(20)],
        [self.filesLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(20)],
        [self.filesLabel.topAnchor constraintEqualToAnchor:self.titleBar.bottomAnchor constant:0],
        [self.filesLabel.heightAnchor constraintGreaterThanOrEqualToConstant:SW(18)],
    ]];

    self.cardArea = [UIView new];
    self.cardArea.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardArea.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.cardArea];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardArea.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.cardArea.topAnchor constraintEqualToAnchor:self.filesLabel.bottomAnchor constant:SW(5)],
        [self.cardArea.widthAnchor constraintEqualToConstant:SW(330)],
        [self.cardArea.heightAnchor constraintEqualToConstant:SW(543)],
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
    self.archiveBtn.layer.cornerRadius = SW(24);
    self.archiveBtn.titleLabel.font = SWFont(20, UIFontWeightRegular);
    [self.archiveBtn setTitle:NSLocalizedString(@"Archive", nil) forState:UIControlStateNormal];
    [self.archiveBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.archiveBtn addTarget:self action:@selector(onArchiveBtn) forControlEvents:UIControlEventTouchUpInside];
    [self.cardArea addSubview:self.archiveBtn];

    self.keepBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.keepBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.keepBtn.backgroundColor = SWHexRGBA(0x028BFFFF);
    self.keepBtn.layer.cornerRadius = SW(24);
    self.keepBtn.titleLabel.font = SWFontS(20, UIFontWeightRegular);
    [self.keepBtn setTitle:NSLocalizedString(@"Keep", nil) forState:UIControlStateNormal];
    [self.keepBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.keepBtn addTarget:self action:@selector(onKeepBtn) forControlEvents:UIControlEventTouchUpInside];
    [self.cardArea addSubview:self.keepBtn];

    NSLayoutConstraint *centerY = [self.archiveBtn.centerYAnchor constraintEqualToAnchor:self.cardArea.topAnchor constant:SW(529)];
    centerY.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.archiveBtn.leadingAnchor constraintEqualToAnchor:self.cardArea.leadingAnchor],
        [self.archiveBtn.widthAnchor constraintEqualToConstant:SW(150)],
        [self.archiveBtn.heightAnchor constraintEqualToConstant:SW(48)],
        centerY,

        [self.keepBtn.trailingAnchor constraintEqualToAnchor:self.cardArea.trailingAnchor],
        [self.keepBtn.widthAnchor constraintEqualToConstant:SW(150)],
        [self.keepBtn.heightAnchor constraintEqualToConstant:SW(48)],
        [self.keepBtn.centerYAnchor constraintEqualToAnchor:self.archiveBtn.centerYAnchor],
    ]];

    // ===== Bottom bar (cardArea 下 26pt，圆角16，上白到底部) =====
    self.bottomBar = [UIView new];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = UIColor.whiteColor;
    self.bottomBar.layer.cornerRadius = SW(16);
    self.bottomBar.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        self.bottomBar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    [self.view addSubview:self.bottomBar];

    self.bottomBarHeightC = [self.bottomBar.heightAnchor constraintEqualToConstant:SW(140)];
    self.bottomBarHeightC.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.topAnchor constraintEqualToAnchor:self.cardArea.bottomAnchor constant:SW(26)],
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
        [self.undoIconBtn.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:SW(20)],
        [self.undoIconBtn.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:SW(12)],
        [self.undoIconBtn.widthAnchor constraintEqualToConstant:SW(24)],
        [self.undoIconBtn.heightAnchor constraintEqualToConstant:SW(24)],

        [self.sortIconBtn.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-SW(20)],
        [self.sortIconBtn.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:SW(12)],
        [self.sortIconBtn.widthAnchor constraintEqualToConstant:SW(24)],
        [self.sortIconBtn.heightAnchor constraintEqualToConstant:SW(24)],
    ]];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = SW(5);
    layout.itemSize = CGSizeMake(SW(60), SW(60));
    layout.sectionInset = UIEdgeInsetsMake(0, SW(20), 0, SW(20));

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
        [self.thumbs.topAnchor constraintEqualToAnchor:self.undoIconBtn.bottomAnchor constant:SW(12)],
        [self.thumbs.heightAnchor constraintEqualToConstant:SW(60)],
    ]];

    // ===== Done Card (hidden by default) =====
    self.doneCard = [UIView new];
    self.doneCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneCard.backgroundColor = UIColor.whiteColor;
    self.doneCard.layer.cornerRadius = SW(20);
    self.doneCard.hidden = YES;
    [self.cardArea addSubview:self.doneCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.doneCard.centerXAnchor constraintEqualToAnchor:self.cardArea.centerXAnchor],
        [self.doneCard.centerYAnchor constraintEqualToAnchor:self.cardArea.centerYAnchor constant:-SW(10)],
        [self.doneCard.widthAnchor constraintEqualToConstant:SW(330)],
        [self.doneCard.heightAnchor constraintEqualToConstant:SW(465)],
    ]];

    self.doneIcon = [UIImageView new];
    self.doneIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.doneIcon.image = [UIImage imageNamed:@"ic_hot"];
    [self.doneCard addSubview:self.doneIcon];

    self.doneTitleLabel = [UILabel new];
    self.doneTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneTitleLabel.textColor = UIColor.blackColor;
    self.doneTitleLabel.font = SWFontS(20, UIFontWeightSemibold);
    self.doneTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.doneTitleLabel.text = NSLocalizedString(@"Organized 100%", nil);
    [self.doneCard addSubview:self.doneTitleLabel];

    self.doneTable = [UIView new];
    self.doneTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneTable.layer.cornerRadius = SW(16);
    self.doneTable.layer.borderWidth = SW(2);
    self.doneTable.layer.borderColor = SWHexRGBA(0x024DFFFF).CGColor;
    self.doneTable.backgroundColor = UIColor.clearColor;
    [self.doneCard addSubview:self.doneTable];

    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [SWHexRGBA(0x024DFFFF) colorWithAlphaComponent:0.40];
    [self.doneTable addSubview:divider];

    self.doneArchiveTitle = [UILabel new];
    self.doneArchiveTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneArchiveTitle.text = NSLocalizedString(@"Archive", nil);
    self.doneArchiveTitle.textColor = UIColor.blackColor;
    self.doneArchiveTitle.font = SWFontS(17, UIFontWeightRegular);
    self.doneArchiveTitle.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneArchiveTitle];

    self.doneArchiveValue = [UILabel new];
    self.doneArchiveValue.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneArchiveValue.text = @"0";
    self.doneArchiveValue.textColor = UIColor.blackColor;
    self.doneArchiveValue.font = SWFontS(40, UIFontWeightSemibold);
    self.doneArchiveValue.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneArchiveValue];

    self.doneKeepTitle = [UILabel new];
    self.doneKeepTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneKeepTitle.text = NSLocalizedString(@"Keep", nil);
    self.doneKeepTitle.textColor = UIColor.blackColor;
    self.doneKeepTitle.font = SWFontS(17, UIFontWeightRegular);
    self.doneKeepTitle.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneKeepTitle];

    self.doneKeepValue = [UILabel new];
    self.doneKeepValue.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneKeepValue.text = @"0";
    self.doneKeepValue.textColor = UIColor.blackColor;
    self.doneKeepValue.font = SWFontS(40, UIFontWeightSemibold);
    self.doneKeepValue.textAlignment = NSTextAlignmentCenter;
    [self.doneTable addSubview:self.doneKeepValue];

    self.nextAlbumBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextAlbumBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.nextAlbumBtn.backgroundColor = SWHexRGBA(0x024DFFFF);
    self.nextAlbumBtn.layer.cornerRadius = SW(25);
    self.nextAlbumBtn.titleLabel.font = SWFontS(17, UIFontWeightRegular);
    [self.nextAlbumBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.nextAlbumBtn addTarget:self action:@selector(onNextAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.doneCard addSubview:self.nextAlbumBtn];

    self.viewArchivedBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.viewArchivedBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.viewArchivedBtn.backgroundColor = SWHexRGBA(0xF6F6F6FF);
    self.viewArchivedBtn.layer.cornerRadius = SW(25);
    self.viewArchivedBtn.titleLabel.font = SWFontS(17, UIFontWeightMedium);
    [self.viewArchivedBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [self.viewArchivedBtn addTarget:self action:@selector(onViewArchived) forControlEvents:UIControlEventTouchUpInside];
    [self.doneCard addSubview:self.viewArchivedBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.doneIcon.topAnchor constraintEqualToAnchor:self.doneCard.topAnchor constant:SW(30)],
        [self.doneIcon.centerXAnchor constraintEqualToAnchor:self.doneCard.centerXAnchor],
        [self.doneIcon.widthAnchor constraintEqualToConstant:SW(80)],
        [self.doneIcon.heightAnchor constraintEqualToConstant:SW(80)],

        [self.doneTitleLabel.topAnchor constraintEqualToAnchor:self.doneIcon.bottomAnchor constant:SW(20)],
        [self.doneTitleLabel.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:SW(25)],
        [self.doneTitleLabel.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-SW(25)],

        [self.doneTable.topAnchor constraintEqualToAnchor:self.doneTitleLabel.bottomAnchor constant:SW(30)],
        [self.doneTable.centerXAnchor constraintEqualToAnchor:self.doneCard.centerXAnchor],
        [self.doneTable.widthAnchor constraintEqualToConstant:SW(280)],
        [self.doneTable.heightAnchor constraintEqualToConstant:SW(100)],

        [divider.centerXAnchor constraintEqualToAnchor:self.doneTable.centerXAnchor],
        [divider.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:SW(12)],
        [divider.bottomAnchor constraintEqualToAnchor:self.doneTable.bottomAnchor constant:-SW(12)],
        [divider.widthAnchor constraintEqualToConstant:SW(1)],

        [self.doneArchiveTitle.centerXAnchor constraintEqualToAnchor:self.doneTable.leadingAnchor constant:SW(70)],
        [self.doneArchiveTitle.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:SW(14)],
        [self.doneArchiveValue.centerXAnchor constraintEqualToAnchor:self.doneArchiveTitle.centerXAnchor],
        [self.doneArchiveValue.topAnchor constraintEqualToAnchor:self.doneArchiveTitle.bottomAnchor constant:SW(6)],

        // Right column
        [self.doneKeepTitle.centerXAnchor constraintEqualToAnchor:self.doneTable.trailingAnchor constant:-SW(70)],
        [self.doneKeepTitle.topAnchor constraintEqualToAnchor:self.doneTable.topAnchor constant:SW(14)],
        [self.doneKeepValue.centerXAnchor constraintEqualToAnchor:self.doneKeepTitle.centerXAnchor],
        [self.doneKeepValue.topAnchor constraintEqualToAnchor:self.doneKeepTitle.bottomAnchor constant:SW(6)],

        [self.nextAlbumBtn.topAnchor constraintEqualToAnchor:self.doneTable.bottomAnchor constant:SW(30)],
        [self.nextAlbumBtn.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:SW(25)],
        [self.nextAlbumBtn.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-SW(25)],
        [self.nextAlbumBtn.heightAnchor constraintEqualToConstant:SW(52)],

        [self.viewArchivedBtn.topAnchor constraintEqualToAnchor:self.nextAlbumBtn.bottomAnchor constant:SW(15)],
        [self.viewArchivedBtn.leadingAnchor constraintEqualToAnchor:self.doneCard.leadingAnchor constant:SW(25)],
        [self.viewArchivedBtn.trailingAnchor constraintEqualToAnchor:self.doneCard.trailingAnchor constant:-SW(25)],
        [self.viewArchivedBtn.heightAnchor constraintEqualToConstant:SW(52)],
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
        self.bottomBarHeightC.constant = SW(120) + safeBottom;
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

- (BOOL)sw_isDoneShowing {
    // 数据为空或 doneCard 正在显示，都视为完成态
    if (self.unprocessedIDs.count == 0) return YES;
    if (self.doneCard && !self.doneCard.hidden) return YES;
    return NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 拦截系统左滑返回
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
    
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

    self.titleLabel.text = self.module.title ?: NSLocalizedString(@"Album", nil);
    
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
        NSFontAttributeName: SWFontS(15, UIFontWeightRegular)
    };
    NSDictionary *kNum = @{
        NSForegroundColorAttributeName: UIColor.blackColor,
        NSFontAttributeName: SWFontS(15, UIFontWeightMedium)
    };

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"Files: ", nil) attributes:kFiles]];
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu", (unsigned long)total] attributes:kNum]];

    uint64_t bytes = [mgr archivedBytesInModule:self.module];

    NSDictionary *kFree = @{
        NSForegroundColorAttributeName: UIColor.blackColor,
        NSFontAttributeName: SWFontS(15, UIFontWeightRegular)
    };

    NSDictionary *kBytes = @{
        NSForegroundColorAttributeName: done ? SWHexRGBA(0x024DFFFF) : SWHexRGBA(0x024DFFFF),
        NSFontAttributeName: SWFontS(15, UIFontWeightMedium)
    };

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@" Can free up ", nil) attributes:kFree]];
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:SWHumanBytesNoSpace(bytes) attributes:kBytes]];

    self.filesLabel.attributedText = att;
}

static inline NSAttributedString *SWNextAlbumAttributedTitle(NSString *leftText,
                                                            NSString *rightText,
                                                            UIFont *font,
                                                            UIColor *textColor) {
    if (leftText.length == 0) leftText = @"";
    if (rightText.length == 0) rightText = @"";

    NSMutableAttributedString *att = [NSMutableAttributedString new];

    NSDictionary *attrs = @{
        NSFontAttributeName: font ?: SWFontS(17, UIFontWeightRegular),
        NSForegroundColorAttributeName: textColor ?: UIColor.whiteColor
    };

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:leftText attributes:attrs]];

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attrs]];
    [att addAttribute:NSKernAttributeName value:@(5.0) range:NSMakeRange(att.length-1, 1)];

    UIImage *img = [UIImage imageNamed:@"ic_more"];
    if (img) {
        NSTextAttachment *ta = [NSTextAttachment new];
        ta.image = img;

        CGFloat imgW = SW(16), imgH = SW(16);
        ta.bounds = CGRectMake(0, (font.capHeight - imgH) * 0.5, imgW, imgH);

        NSAttributedString *imgStr = [NSAttributedString attributedStringWithAttachment:ta];
        [att appendAttributedString:imgStr];
    } else {
        [att appendAttributedString:[[NSAttributedString alloc] initWithString:@">" attributes:attrs]];
    }

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attrs]];
    [att addAttribute:NSKernAttributeName value:@(5.0) range:NSMakeRange(att.length-1, 1)];

    [att appendAttributedString:[[NSAttributedString alloc] initWithString:rightText attributes:attrs]];

    return att;
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

        NSString *right = @"";
        if (next.type == SwipeModuleTypeMonth) {
            right = (next.title.length ? next.title : NSLocalizedString(@"Next", nil));
        } else if (next.type == SwipeModuleTypeRecentDay) {
            NSString *ymd = SWDayKeyFromModule(next) ?: @"";
            NSString *wk = SWWeekdayFromYMD(ymd);
            right = (wk.length ? wk : (next.title.length ? next.title : NSLocalizedString(@"Next", nil)));
        } else {
            right = (next.title.length ? next.title : NSLocalizedString(@"Next", nil));
        }

        NSString *left = NSLocalizedString(@"Next Album", nil);

        NSAttributedString *attTitle =
            SWNextAlbumAttributedTitle(left,
                                      right,
                                      SWFontS(17, UIFontWeightRegular),
                                      UIColor.whiteColor);

        [self.nextAlbumBtn setAttributedTitle:attTitle forState:UIControlStateNormal];
        self.nextAlbumBtn.hidden = NO;

    } else {
        self.nextAlbumBtn.hidden = YES;
    }

    // Total archived bytes
    uint64_t totalBytes = (uint64_t)[[SwipeManager shared] totalArchivedBytesCached];
    NSString *btnTitle = [NSString stringWithFormat:NSLocalizedString(@"View Archived Files(%@)", nil), SWHumanBytesNoSpace(totalBytes)];
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

- (CGFloat)sw_blurRadiusForCardIndex:(NSInteger)idx {
    if (idx == 1) return SW(16); // middle
    if (idx == 2) return SW(22); // bottom
    return 0;
}

- (NSString *)sw_blurKeyForAssetID:(NSString *)aid px:(CGSize)px radius:(CGFloat)r {
    return [NSString stringWithFormat:@"cardblur_%@_%.0fx%.0f_r%.2f", aid ?: @"", px.width, px.height, r];
}

- (void)sw_revealCardIfNeeded:(SwipeCardView *)card {
    if (!card.sw_revealWhenReady) return;
    if (!card.hidden) { card.sw_revealWhenReady = NO; return; }

    card.hidden = NO;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        card.alpha = 1.0;
    } completion:nil];
    card.sw_revealWhenReady = NO;
}

- (void)sw_applyVisualForCard:(SwipeCardView *)card {
    if (!card || card.hidden) return;

    NSInteger idx = [self.cards indexOfObject:card];
    if (idx == NSNotFound) return;

    UIImage *raw = card.rawImage ?: card.imageView.image;
    if (!raw) return;

    // ✅ 顶卡永远清晰
    if (idx == 0) {
        card.imageView.image = raw;
        [self sw_revealCardIfNeeded:card];
        return;
    }

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize px = CGSizeMake(card.bounds.size.width * scale, card.bounds.size.height * scale);
    CGFloat radius = [self sw_blurRadiusForCardIndex:idx];

    NSString *blurKey = [self sw_blurKeyForAssetID:card.assetID px:px radius:radius];
    UIImage *cachedBlur = [self.cardBlurImageCache objectForKey:blurKey];
    if (cachedBlur) {
        card.imageView.image = cachedBlur;
        [self sw_revealCardIfNeeded:card];
        return;
    }

    // 缓存未命中：为了不出现空白，非 showWhenReady 的卡先用 raw 顶一下
    if (!card.sw_revealWhenReady && !card.imageView.image) {
        card.imageView.image = raw;
    }

    // 防止重复算同一张
    @synchronized (self.sw_blurInFlight) {
        if ([self.sw_blurInFlight containsObject:blurKey]) return;
        [self.sw_blurInFlight addObject:blurKey];
    }

    NSString *aid = card.assetID ?: @"";
    __weak typeof(self) ws = self;
    __weak typeof(card) wcard = card;

    dispatch_async(self.sw_blurQueue, ^{
        UIImage *b = [raw applyGaussianBlurWithRadius:radius];
        if (b) {
            [ws.cardBlurImageCache setObject:b forKey:blurKey];
        }
        @synchronized (ws.sw_blurInFlight) {
            [ws.sw_blurInFlight removeObject:blurKey];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            SwipeCardView *scard = wcard;
            if (!self || !scard) return;

            // asset 复用校验 + 位置校验（防止轮转/撤回后错贴）
            if (![scard.assetID isEqualToString:aid]) return;

            NSInteger curIdx = [self.cards indexOfObject:scard];
            if (curIdx == NSNotFound) return;

            // 如果此刻它已经变成顶卡了，就别贴模糊
            if (curIdx == 0) {
                scard.imageView.image = scard.rawImage ?: scard.imageView.image;
                [self sw_revealCardIfNeeded:scard];
                return;
            }

            // 仍是非顶卡 -> 应用模糊
            UIImage *finalBlur = [self.cardBlurImageCache objectForKey:blurKey];
            if (finalBlur) {
                scard.imageView.image = finalBlur;
                [self sw_revealCardIfNeeded:scard];
            }
        });
    });
}

- (void)sw_updateCardBlurAppearance {
    for (SwipeCardView *c in self.cards) {
        [self sw_applyVisualForCard:c];
    }
}

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

    // 轮转：mid->top, bottom->mid
    self.cards[0] = oldMid;
    self.cards[1] = oldBottom;
    self.cards[2] = oldTop;

    for (SwipeCardView *c in self.cards) {
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:c];
        c.transform = CGAffineTransformIdentity;
        c.hintLabel.alpha = 0;
        c.alpha = 1.0;
    }

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
            if (newBottomAid.length) {
                if (![self.cards[2].assetID isEqualToString:newBottomAid]) {
                    // 这是复用卡，showWhenReady:YES，避免底部卡片闪一下
                    [self sw_setCard:self.cards[2]
                             assetID:newBottomAid
                          targetSize:SWCardFrameForIndex(2).size
                       showWhenReady:YES];
                }
            }

          }
    }

    // zOrder
    [self.cardsHost bringSubviewToFront:self.cards[2]]; // bottom
    [self.cardsHost bringSubviewToFront:self.cards[1]]; // mid
    [self.cardsHost bringSubviewToFront:self.cards[0]]; // top

    void (^applyFrames)(void) = ^{
        self.cards[0].frame = SWCardFrameForIndex(0); // oldMid -> top
        self.cards[1].frame = SWCardFrameForIndex(1); // oldBottom -> mid
        self.cards[2].frame = SWCardFrameForIndex(2); // oldTop 已经在底部了（无可见移动）
    };

    void (^finish)(void) = ^{
        [self sw_updateStackVisibility];
        [self updateTopUIFromManager];
        [self scrollThumbsToTopIfNeededAnimated:animated];

    
        [self attachPanToTopCard];
        if (completion) completion();
    };

    if (!animated) {
        applyFrames();
        finish();
        return;
    }

    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        applyFrames();
    } completion:^(__unused BOOL finished) {
        finish();
        [self sw_updateCardBlurAppearance];
    }];
}

static inline CGRect SWCardFrameForIndex(NSInteger idx) {
    if (idx == 0) { // top
        return CGRectMake(0, SW(23), SW(330), SW(520));
    } else if (idx == 1) { // middle
        return CGRectMake((SW(330) - SW(320))/2.0, SW(12), SW(320), SW(520));
    } else { // bottom
        return CGRectMake((SW(330) - SW(256))/2.0, 0, SW(256), SW(416));
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

    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
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

- (CGAffineTransform)sw_pendulumTransformForX:(CGFloat)x
                                           y:(CGFloat)y
                                       width:(CGFloat)w
                               clampProgress:(BOOL)clampProgress {
    w = MAX(1.0, w);
    CGFloat denom = w * 0.55;
    CGFloat p = (denom > 1.0) ? (fabs(x) / denom) : 0.0;

    if (clampProgress) p = MIN(1.0, p);

    CGFloat tx = x * 0.35;
    CGFloat ty = (y * 0.08) - p * 18.0;

    CGFloat maxAngle = (CGFloat)(M_PI / 10.0);
    CGFloat rot = -(x / w) * maxAngle;

    CGAffineTransform tr = CGAffineTransformIdentity;
    tr = CGAffineTransformTranslate(tr, tx, ty);
    tr = CGAffineTransformRotate(tr, rot);
    return tr;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.cardAnimating) return;

    SwipeCardView *card = (SwipeCardView *)pan.view;
    if (!card) return;

    CGPoint t = [pan translationInView:self.cardsHost];
    CGPoint v = [pan velocityInView:self.cardsHost];

    CGFloat w = MAX(1.0, self.cardArea.bounds.size.width);
    CGFloat x = t.x;

    card.transform = [self sw_pendulumTransformForX:x y:t.y width:w clampProgress:YES];

    // hint
    if (x > 25) {
        card.hintLabel.text = @"Keep";
        card.hintLabel.textAlignment = NSTextAlignmentCenter;
        card.hintLabel.alpha = MIN(1.0, x / SW(120.0));
    } else if (x < -25) {
        card.hintLabel.text = @"Archive";
        card.hintLabel.textAlignment = NSTextAlignmentCenter;
        card.hintLabel.alpha = MIN(1.0, -x / SW(120.0));
    } else {
        card.hintLabel.alpha = 0;
    }

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {

        CGFloat vx = v.x;
        CGFloat vy = v.y;

        CGFloat w = MAX(1.0, self.cardArea.bounds.size.width);
        CGFloat absX = fabs(x);

        CGFloat verticalGuard = 1.35;
        BOOL mostlyHorizontal = (fabs(vx) > fabs(vy) * verticalGuard);

        CGFloat vxFling        = SW(520);   // 强甩速度
        CGFloat vxDragMin      = SW(180);   // 软阈值提交：松手至少要有点速度
        CGFloat dragThreshold  = w * 0.22;  // 软距离阈值
        CGFloat hardThreshold  = w * 0.30;  // 硬距离阈值：够远就该出去（但要允许“快速回拉取消”）

        CGFloat vxReturnCancel = SW(260);   // 反向回拉速度阈值（可以 220~320 调）
        BOOL sameDirection = ((x >= 0 && vx >= 0) || (x <= 0 && vx <= 0));
        BOOL returningFast = (mostlyHorizontal && !sameDirection && fabs(vx) >= vxReturnCancel);

        if (returningFast) {
            [UIView animateWithDuration:0.12
                                  delay:0
                 usingSpringWithDamping:0.9
                  initialSpringVelocity:0.6
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                card.transform = CGAffineTransformIdentity;
                card.hintLabel.alpha = 0;
            } completion:^(__unused BOOL finished) {
                [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:card];
                [self layoutCardsAnimated:YES];
            }];
            return;
        }

        BOOL shouldCommit = NO;
        BOOL commitArchive = (x < 0);

        if (mostlyHorizontal && absX >= hardThreshold) {
            shouldCommit = YES;
            commitArchive = (x < 0);
        }
        else {
            CGFloat flingMinDist = w * 0.10;
            if (mostlyHorizontal && fabs(vx) >= vxFling && absX >= flingMinDist && sameDirection) {
                shouldCommit = YES;
                commitArchive = (vx < 0);
            }
            else if (mostlyHorizontal && absX >= dragThreshold && fabs(vx) >= vxDragMin && sameDirection) {
                shouldCommit = YES;
                commitArchive = (x < 0);
            }
        }

        if (shouldCommit) {
            [self commitTopCardArchived:commitArchive velocity:v translation:t];
            return;
        }

        // 不提交：回弹（不要再 commit）
        [UIView animateWithDuration:0.12
                              delay:0
             usingSpringWithDamping:0.9
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            card.transform = CGAffineTransformIdentity;
            card.hintLabel.alpha = 0;
        } completion:^(__unused BOOL finished) {
            [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:card];
            [self layoutCardsAnimated:YES];
        }];
    }

}

- (void)sw_animateAdvanceStackWithOutgoingTop:(SwipeCardView *)outTop
                                     archived:(BOOL)archived
                                     velocity:(CGPoint)velocity
                                  translation:(CGPoint)translation
                                   completion:(void(^)(void))completion {

    SwipeCardView *mid    = self.cards.count > 1 ? self.cards[1] : nil;
    SwipeCardView *bottom = self.cards.count > 2 ? self.cards[2] : nil;

    NSTimeInterval dur = 0.30;

    for (SwipeCardView *c in @[mid ?: [NSNull null], bottom ?: [NSNull null]]) {
        if ((id)c == [NSNull null]) continue;
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:(UIView *)c];
        ((SwipeCardView *)c).transform = CGAffineTransformIdentity;
        ((SwipeCardView *)c).hintLabel.alpha = 0;
        ((SwipeCardView *)c).alpha = 1.0;
    }

    [self sw_setAnchorPoint:CGPointMake(0.5, 0.0) forView:outTop];

    [self.cardsHost bringSubviewToFront:outTop];

    CGRect fTop    = SWCardFrameForIndex(0);
    CGRect fMid    = SWCardFrameForIndex(1);
    CGRect fBottom = SWCardFrameForIndex(2);

    CGFloat dir = archived ? -1.0 : 1.0;
    CGFloat w = MAX(1.0, self.cardArea.bounds.size.width);

    CGFloat x0 = translation.x;
    CGFloat y0 = translation.y;

    CGFloat xEnd = dir * (w * 5.0) + velocity.x * 0.25;
    if (dir > 0) xEnd = MAX(xEnd,  w * 4.5);
    else         xEnd = MIN(xEnd, -w * 4.5);

    outTop.transform = [self sw_pendulumTransformForX:x0 y:y0 width:w clampProgress:YES];

    [UIView animateKeyframesWithDuration:dur
                                   delay:0
                                 options:UIViewKeyframeAnimationOptionCalculationModeCubicPaced | UIViewAnimationOptionCurveEaseIn
                              animations:^{

        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:1.0 animations:^{
            if (mid && !mid.hidden)    mid.frame    = fTop;
            if (bottom && !bottom.hidden) bottom.frame = fMid;
        }];

        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.60 animations:^{
            CGFloat x1 = x0 + (xEnd - x0) * 0.60;
            CGFloat y1 = y0;
            outTop.transform = [self sw_pendulumTransformForX:x1 y:y1 width:w clampProgress:NO];
            outTop.alpha = 0.75;
            outTop.hintLabel.alpha = 0;
        }];

        [UIView addKeyframeWithRelativeStartTime:0.60 relativeDuration:0.40 animations:^{
            outTop.transform = [self sw_pendulumTransformForX:xEnd y:0 width:w clampProgress:NO];
            outTop.alpha = 0.0;
        }];

    } completion:^(__unused BOOL finished) {

        outTop.hidden = YES;
        outTop.alpha = 1.0;
        outTop.transform = CGAffineTransformIdentity;
        [self sw_setAnchorPoint:CGPointMake(0.5, 0.5) forView:outTop];

        if (self.cards.count >= 3) {
            self.cards[0] = mid;
            self.cards[1] = bottom;
            self.cards[2] = outTop;
        }

        outTop.frame = fBottom;

        NSString *newBottomAid = (self.unprocessedIDs.count >= 3) ? self.unprocessedIDs[2] : nil;
        if (newBottomAid.length) {
            [self sw_setCard:outTop assetID:newBottomAid targetSize:fBottom.size showWhenReady:YES];
        } else {
            outTop.hidden = YES;
        }

        if (self.cards.count >= 3) {
            [self.cardsHost bringSubviewToFront:self.cards[2]];
            [self.cardsHost bringSubviewToFront:self.cards[1]];
            [self.cardsHost bringSubviewToFront:self.cards[0]];
        }

        [self sw_updateStackVisibility];
        [self attachPanToTopCard];
        [self sw_refreshVisibleThumbCells];
        [self scrollThumbsToTopIfNeededAnimated:YES];

        if (completion) completion();
        [self sw_updateCardBlurAppearance];
    }];
}

- (void)onArchiveBtn { [self commitTopCardArchived:YES velocity:CGPointZero translation:CGPointZero]; }
- (void)onKeepBtn    { [self commitTopCardArchived:NO  velocity:CGPointZero translation:CGPointZero]; }

- (void)commitTopCardArchived:(BOOL)archived velocity:(CGPoint)velocity translation:(CGPoint)translation {
    if (self.cardAnimating) return;
    self.sw_hasOperated = YES;

    SwipeCardView *top = self.cards.firstObject;
    if (!top) return;

    self.cardAnimating = YES;

    top.userInteractionEnabled = NO;
    self.archiveBtn.userInteractionEnabled = NO;
    self.keepBtn.userInteractionEnabled = NO;

    NSString *aid = top.assetID ?: @"";

    SwipeAssetStatus st = archived ? SwipeAssetStatusArchived : SwipeAssetStatusKept;
    [[SwipeManager shared] setStatus:st forAssetID:aid sourceModule:self.module.moduleID recordUndo:YES];
    [self sw_updateThumbForAssetIDNoFlicker:aid];

    if (self.unprocessedIDs.count > 0 && [self.unprocessedIDs.firstObject isEqualToString:aid]) {
        [self.unprocessedIDs removeObjectAtIndex:0];
    } else {
        [self.unprocessedIDs removeObject:aid];
    }

    NSString *topID = self.unprocessedIDs.firstObject;
    [[SwipeManager shared] setCurrentUnprocessedAssetID:(topID.length ? topID : @"")
                                            forModuleID:self.module.moduleID];
    [self scrollThumbsToTopIfNeededAnimated:YES];

    __weak typeof(self) ws = self;
    [self sw_animateAdvanceStackWithOutgoingTop:top
                                       archived:archived
                                       velocity:velocity
                                    translation:translation
                                     completion:^{
        __strong typeof(ws) self = ws;
        if (!self) return;

        [self updateTopUIFromManager];

        BOOL done = (self.unprocessedIDs.count == 0);
        [self showDoneState:done];

        self.archiveBtn.userInteractionEnabled = YES;
        self.keepBtn.userInteractionEnabled = YES;
        self.cardAnimating = NO;
    }];
}


- (void)sw_prefetchCardImageForAssetID:(NSString *)assetID targetSize:(CGSize)targetSize {
    if (assetID.length == 0) return;

    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize ts = CGSizeMake(targetSize.width * scale, targetSize.height * scale);

    if ([self.imageManager isKindOfClass:PHCachingImageManager.class]) {
        [(PHCachingImageManager *)self.imageManager startCachingImagesForAssets:@[asset]
                                                                    targetSize:ts
                                                                   contentMode:PHImageContentModeAspectFill
                                                                       options:nil];
        return;
    }

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
    }];
}

- (void)sw_updateThumbForAssetIDNoFlicker:(NSString *)aid {
    if (aid.length == 0) return;

    NSUInteger idx = [self.allAssetIDs indexOfObject:aid];
    if (idx == NSNotFound) return;

    NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];
    SwipeThumbCell *cell = (SwipeThumbCell *)[self.thumbs cellForItemAtIndexPath:ip];
    
    if (!cell) {
        [self.thumbs reloadItemsAtIndexPaths:@[ip]];
        return;
    }
    
    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    BOOL processed = (st != SwipeAssetStatusUnknown);

    if (cell) {
        cell.imageView.alpha = processed ? 0.2 : 1.0;
        cell.checkIcon.hidden = !processed;
        return;
    }

    [self sw_reloadThumbForAssetIDNoFlicker:aid];
    
    NSString *key = SWImgKey(@"thumb_", aid, CGSizeMake(SW(140), SW(140)));
    UIImage *cached = [self.thumbImageCache objectForKey:key];
    if (!cached) {
        [self loadImageForAssetID:aid intoImageView:cell.imageView targetSize:CGSizeMake(SW(140), SW(140))];
    }
}


#pragma mark - Exit Popup

- (void)sw_showExitPopup {
    if (self.sw_exitPopup) return;

    [self sw_lockAction];

    UIView *mask = [UIView new];
    mask.translatesAutoresizingMaskIntoConstraints = NO;
    mask.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    mask.alpha = 0.0;
    [self.view addSubview:mask];
    [NSLayoutConstraint activateConstraints:@[
        [mask.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mask.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mask.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mask.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.sw_exitMask = mask;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sw_exitMaskTapped)];
    tap.cancelsTouchesInView = YES;
    tap.delegate = self;
    [mask addGestureRecognizer:tap];

    UIView *popup = [UIView new];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.backgroundColor = UIColor.whiteColor;
    popup.layer.cornerRadius = SW(20);
    popup.layer.masksToBounds = YES;
    popup.alpha = 0.0;
    popup.transform = CGAffineTransformMakeScale(0.98, 0.98);
    [mask addSubview:popup];
    self.sw_exitPopup = popup;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [popup.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SW(36)],
        [popup.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SW(36)],
        [popup.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [popup.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:SW(20)],
        [popup.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-SW(20)],
    ]];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = NSLocalizedString(@"View Archived Files", nil);
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.blackColor;
    title.font = SWFontS(20, UIFontWeightSemibold);
    [popup addSubview:title];

    UILabel *msg = [UILabel new];
    msg.translatesAutoresizingMaskIntoConstraints = NO;
    msg.textAlignment = NSTextAlignmentCenter;
    msg.numberOfLines = 0;
    msg.textColor = UIColor.blackColor;
    msg.font = SWFontS(15, UIFontWeightRegular);
    msg.text = NSLocalizedString(@"You can perform this action now to free up space, or do it at any convenient time", nil);
    [popup addSubview:msg];

    UIView *table = [UIView new];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.layer.cornerRadius = SW(16);
    table.layer.borderWidth = SW(2);
    table.layer.borderColor = SWHexRGBA(0x024DFFFF).CGColor;
    table.backgroundColor = UIColor.clearColor;
    [popup addSubview:table];

    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [SWHexRGBA(0x024DFFFF) colorWithAlphaComponent:0.40];
    [table addSubview:divider];

    UIView *leftCol = [UIView new];
    leftCol.translatesAutoresizingMaskIntoConstraints = NO;
    [table addSubview:leftCol];

    UIView *rightCol = [UIView new];
    rightCol.translatesAutoresizingMaskIntoConstraints = NO;
    [table addSubview:rightCol];

    UILabel *aTitle = [UILabel new];
    aTitle.translatesAutoresizingMaskIntoConstraints = NO;
    aTitle.text = NSLocalizedString(@"Archive", nil);
    aTitle.textColor = UIColor.blackColor;
    aTitle.font = SWFontS(17, UIFontWeightRegular);
    aTitle.textAlignment = NSTextAlignmentCenter;
    [leftCol addSubview:aTitle];

    UILabel *aValue = [UILabel new];
    aValue.translatesAutoresizingMaskIntoConstraints = NO;
    aValue.textColor = UIColor.blackColor;
    aValue.font = SWFontS(40, UIFontWeightSemibold);
    aValue.textAlignment = NSTextAlignmentCenter;
    aValue.text = @"0";
    [leftCol addSubview:aValue];
    self.sw_exitArchiveValue = aValue;

    UILabel *kTitle = [UILabel new];
    kTitle.translatesAutoresizingMaskIntoConstraints = NO;
    kTitle.text = NSLocalizedString(@"Keep", nil);
    kTitle.textColor = UIColor.blackColor;
    kTitle.font = SWFont(17, UIFontWeightRegular);
    kTitle.textAlignment = NSTextAlignmentCenter;
    [rightCol addSubview:kTitle];

    UILabel *kValue = [UILabel new];
    kValue.translatesAutoresizingMaskIntoConstraints = NO;
    kValue.textColor = UIColor.blackColor;
    kValue.font = SWFontS(40, UIFontWeightSemibold);
    kValue.textAlignment = NSTextAlignmentCenter;
    kValue.text = @"0";
    [rightCol addSubview:kValue];
    self.sw_exitKeepValue = kValue;

    UIButton *viewBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    viewBtn.translatesAutoresizingMaskIntoConstraints = NO;
    viewBtn.backgroundColor = SWHexRGBA(0x024DFFFF);
    viewBtn.layer.cornerRadius = SW(16);
    viewBtn.titleLabel.font = SWFontS(17, UIFontWeightRegular);
    [viewBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [viewBtn addTarget:self action:@selector(sw_exitViewArchivedTapped) forControlEvents:UIControlEventTouchUpInside];
    [popup addSubview:viewBtn];
    self.sw_exitViewArchivedBtn = viewBtn;

    UIButton *laterBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    laterBtn.translatesAutoresizingMaskIntoConstraints = NO;
    laterBtn.backgroundColor = SWHexRGBA(0xF6F6F6FF);
    laterBtn.layer.cornerRadius = SW(16);
    laterBtn.titleLabel.font = SWFontS(17, UIFontWeightMedium);
    [laterBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [laterBtn setTitle:NSLocalizedString(@"Later", nil) forState:UIControlStateNormal];
    [laterBtn addTarget:self action:@selector(sw_exitLaterTapped) forControlEvents:UIControlEventTouchUpInside];
    [popup addSubview:laterBtn];

    // layout
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:popup.topAnchor constant:SW(40)],
        [title.leadingAnchor constraintEqualToAnchor:popup.leadingAnchor constant:SW(25)],
        [title.trailingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:-SW(25)],

        [msg.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:SW(10)],
        [msg.leadingAnchor constraintEqualToAnchor:popup.leadingAnchor constant:SW(25)],
        [msg.trailingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:-SW(25)],

        [table.topAnchor constraintEqualToAnchor:msg.bottomAnchor constant:SW(30)],
        [table.leadingAnchor constraintEqualToAnchor:popup.leadingAnchor constant:SW(25)],
        [table.trailingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:-SW(25)],
        [table.heightAnchor constraintEqualToConstant:SW(100)],

        [divider.centerXAnchor constraintEqualToAnchor:table.centerXAnchor],
        [divider.topAnchor constraintEqualToAnchor:table.topAnchor constant:SW(12)],
        [divider.bottomAnchor constraintEqualToAnchor:table.bottomAnchor constant:-SW(12)],
        [divider.widthAnchor constraintEqualToConstant:SW(1)],

        [leftCol.leadingAnchor constraintEqualToAnchor:table.leadingAnchor],
        [leftCol.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],
        [leftCol.topAnchor constraintEqualToAnchor:table.topAnchor],
        [leftCol.bottomAnchor constraintEqualToAnchor:table.bottomAnchor],

        [rightCol.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [rightCol.trailingAnchor constraintEqualToAnchor:table.trailingAnchor],
        [rightCol.topAnchor constraintEqualToAnchor:table.topAnchor],
        [rightCol.bottomAnchor constraintEqualToAnchor:table.bottomAnchor],

        [aTitle.topAnchor constraintEqualToAnchor:leftCol.topAnchor constant:SW(14)],
        [aTitle.centerXAnchor constraintEqualToAnchor:leftCol.centerXAnchor],
        [aValue.topAnchor constraintEqualToAnchor:aTitle.bottomAnchor constant:SW(6)],
        [aValue.centerXAnchor constraintEqualToAnchor:leftCol.centerXAnchor],

        [kTitle.topAnchor constraintEqualToAnchor:rightCol.topAnchor constant:SW(14)],
        [kTitle.centerXAnchor constraintEqualToAnchor:rightCol.centerXAnchor],
        [kValue.topAnchor constraintEqualToAnchor:kTitle.bottomAnchor constant:SW(6)],
        [kValue.centerXAnchor constraintEqualToAnchor:rightCol.centerXAnchor],

        [viewBtn.topAnchor constraintEqualToAnchor:table.bottomAnchor constant:SW(30)],
        [viewBtn.leadingAnchor constraintEqualToAnchor:popup.leadingAnchor constant:SW(25)],
        [viewBtn.trailingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:-SW(25)],
        [viewBtn.heightAnchor constraintEqualToConstant:SW(52)],

        [laterBtn.topAnchor constraintEqualToAnchor:viewBtn.bottomAnchor constant:SW(15)],
        [laterBtn.leadingAnchor constraintEqualToAnchor:popup.leadingAnchor constant:SW(25)],
        [laterBtn.trailingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:-SW(25)],
        [laterBtn.heightAnchor constraintEqualToConstant:SW(52)],

        [laterBtn.bottomAnchor constraintEqualToAnchor:popup.bottomAnchor constant:-SW(30)],
    ]];

    [self sw_updateExitPopupNumbers];

    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 1.0;
        popup.alpha = 1.0;
        popup.transform = CGAffineTransformIdentity;
    }];
}

- (void)sw_updateExitPopupNumbers {
    SwipeManager *mgr = [SwipeManager shared];

    NSUInteger archived = [mgr archivedCountInModule:self.module];

    NSUInteger kept = 0;
    SEL sel = NSSelectorFromString(@"keptCountInModule:");
    if ([mgr respondsToSelector:sel]) {
        NSUInteger (*func)(id, SEL, id) = (void *)[mgr methodForSelector:sel];
        kept = func(mgr, sel, self.module);
    } else {
        NSUInteger processed = [mgr processedCountInModule:self.module];
        kept = (processed >= archived) ? (processed - archived) : 0;
    }

    self.sw_exitArchiveValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)archived];
    self.sw_exitKeepValue.text    = [NSString stringWithFormat:@"%lu", (unsigned long)kept];

    uint64_t totalBytes = (uint64_t)[[SwipeManager shared] totalArchivedBytesCached];
    NSString *sizeStr = SWHumanBytesNoSpace(totalBytes);
    NSString *btnTitle = [NSString stringWithFormat:@"%@ (%@)", NSLocalizedString(@"View Archived Files", nil), sizeStr];
    [self.sw_exitViewArchivedBtn setTitle:btnTitle forState:UIControlStateNormal];
}

- (void)sw_exitMaskTapped {
    // 只关闭弹窗，不返回（避免误触就退出）
    [self sw_dismissExitPopupThen:nil];
}

- (void)sw_exitViewArchivedTapped {
    __weak typeof(self) ws = self;
    [self sw_dismissExitPopupThen:^{
        __strong typeof(ws) self = ws;
        if (!self) return;
        UINavigationController *nav = self.navigationController ?: [self sw_currentNav];
        if (!nav) return;
        ASArchivedFilesViewController *vc = [ASArchivedFilesViewController new];
        [nav pushViewController:vc animated:YES];
    }];
}

- (void)sw_exitLaterTapped {
    __weak typeof(self) ws = self;
    [self sw_dismissExitPopupThen:^{
        __strong typeof(ws) self = ws;
        if (!self) return;
        UINavigationController *nav = self.navigationController ?: [self sw_currentNav];
        if (!nav) return;
        [nav popViewControllerAnimated:YES];
    }];
}

- (void)sw_dismissExitPopupThen:(void(^)(void))completion {
    if (!self.sw_exitPopup) { if (completion) completion(); return; }

    UIView *mask = self.sw_exitMask;
    UIView *popup = self.sw_exitPopup;

    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 0.0;
        popup.alpha = 0.0;
        popup.transform = CGAffineTransformMakeScale(0.98, 0.98);
    } completion:^(__unused BOOL finished) {
        [popup removeFromSuperview];
        [mask removeFromSuperview];
        self.sw_exitPopup = nil;
        self.sw_exitMask = nil;
        self.sw_exitArchiveValue = nil;
        self.sw_exitKeepValue = nil;
        self.sw_exitViewArchivedBtn = nil;

        [self sw_unlockAction];

        if (completion) completion();
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer.view == self.sw_exitMask && self.sw_exitPopup) {
        CGPoint p = [touch locationInView:self.sw_exitMask];
        if (CGRectContainsPoint(self.sw_exitPopup.frame, p)) return NO;
    }
    return YES;
}

#pragma mark - Buttons (Undo / Sort / Nav)

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        if (self.cardAnimating) return NO;

        if (self.sw_hasOperated && ![self sw_isDoneShowing]) {
            [self sw_showExitPopup];
            return NO;
        }
    }
    return YES;
}

- (void)onBack {
    if (self.cardAnimating) return;

    if (self.sw_hasOperated && ![self sw_isDoneShowing]) {
        [self sw_showExitPopup];
        return;
    }

    UINavigationController *nav = self.navigationController ?: [self sw_currentNav];
    if (!nav) return;
    [nav popViewControllerAnimated:YES];
}

- (void)undoTapped {
    if (self.cardAnimating) return;
    if (self.sw_actionLocked) return;
    self.sw_hasOperated = YES;

    NSString *undoneAid = [[SwipeManager shared] undoLastActionAssetIDInModuleID:self.module.moduleID];
    if (undoneAid.length == 0) return;

    // 撤回后：强制按 manager 最新应处理顺序刷新，并把 undone 置顶
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
    lab.font = SWFontS(17, UIFontWeightSemibold);
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
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:SW(16)],
        [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-SW(14)],
        [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:SW(18)],
        [check.heightAnchor constraintEqualToConstant:SW(18)],

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
    panel.backgroundColor = SWHexRGBA(0x8e8e8eFF);
    panel.layer.cornerRadius = SW(12);
    panel.layer.masksToBounds = YES;
    panel.alpha = 0.0;
    panel.transform = CGAffineTransformMakeTranslation(0, 6);
    [self.view addSubview:panel];
    self.sw_sortPanel = panel;

    UILabel *hdr = [UILabel new];
    hdr.translatesAutoresizingMaskIntoConstraints = NO;
    hdr.text = NSLocalizedString(@"Sort by", nil);
    hdr.font = SWFontS(12, UIFontWeightRegular);
    hdr.textColor = SWHexRGBA(0xEBEBF599);
    [panel addSubview:hdr];

    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.15];
    [panel addSubview:line];

    BOOL asc = self.module.sortAscending;
    UIView *rowLatest = [self sw_sortRowWithTitle:NSLocalizedString(@"Latest", nil)
                                        selected:(!asc)
                                          action:@selector(sw_sortPickLatest)];
    UIView *rowOldest = [self sw_sortRowWithTitle:NSLocalizedString(@"Oldest", nil)
                                        selected:(asc)
                                          action:@selector(sw_sortPickOldest)];
    [panel addSubview:rowLatest];
    [panel addSubview:rowOldest];

    UIView *sep = [UIView new];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.15];
    [panel addSubview:sep];

    CGRect anchor = [self.sortIconBtn convertRect:self.sortIconBtn.bounds toView:self.view];
    CGFloat panelW = SW(220);
    CGFloat panelH = SW(44) + SW(52) + SW(52);

    CGFloat x = CGRectGetMaxX(anchor) - panelW;
    x = MIN(MAX(SW(12), x), self.view.bounds.size.width - panelW - SW(12));

    CGFloat y = CGRectGetMinY(anchor) - panelH - SW(8);
    y = MAX(SW(12), y);

    panel.frame = CGRectMake(x, y, panelW, panelH);

    [NSLayoutConstraint activateConstraints:@[
        [hdr.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:SW(16)],
        [hdr.topAnchor constraintEqualToAnchor:panel.topAnchor constant:SW(12)],

        [line.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [line.topAnchor constraintEqualToAnchor:panel.topAnchor constant:SW(44)],
        [line.heightAnchor constraintEqualToConstant:SW(1)],

        [rowLatest.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [rowLatest.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [rowLatest.topAnchor constraintEqualToAnchor:panel.topAnchor constant:SW(44)],
        [rowLatest.heightAnchor constraintEqualToConstant:SW(52)],

        [sep.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [sep.topAnchor constraintEqualToAnchor:rowLatest.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:SW(1)],

        [rowOldest.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [rowOldest.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [rowOldest.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
        [rowOldest.heightAnchor constraintEqualToConstant:SW(52)],
    ]];

    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 1.0;
        panel.alpha = 1.0;
        panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)sw_forceRebuildFromManagerAnimated:(BOOL)animated keepFocusTop:(NSString *)focusIDOrNil {
    SwipeManager *mgr = [SwipeManager shared];

    SwipeModule *latest = nil;
    for (SwipeModule *m in mgr.modules) {
        if ([m.moduleID isEqualToString:self.module.moduleID]) { latest = m; break; }
    }
    if (latest) self.module = latest;

    NSArray<NSString *> *newAll = self.module.assetIDs ?: @[];
    self.allAssetIDs = newAll;

    [self.unprocessedIDs removeAllObjects];
    for (NSString *aid in self.allAssetIDs) {
        if ([mgr statusForAssetID:aid] == SwipeAssetStatusUnknown) {
            [self.unprocessedIDs addObject:aid];
        }
    }

    if (focusIDOrNil.length > 0) {
        NSUInteger idx = [self.unprocessedIDs indexOfObject:focusIDOrNil];
        if (idx != NSNotFound && idx != 0) {
            NSString *target = self.unprocessedIDs[idx];
            [self.unprocessedIDs removeObjectAtIndex:idx];
            [self.unprocessedIDs insertObject:target atIndex:0];
        }
        [mgr setCurrentUnprocessedAssetID:focusIDOrNil forModuleID:self.module.moduleID];
    } else {
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

    BOOL done = (self.unprocessedIDs.count == 0);
    [self showDoneState:done];

    if (done) {
        for (SwipeCardView *c in self.cards) { c.hidden = YES; c.userInteractionEnabled = NO; }
    } else {
        [self sw_prepare3CardsIfNeeded];

        [self.view layoutIfNeeded];

        [self sw_applyTop3CardsAnimated:NO];
        [self sw_updateCardBlurAppearance];
        [self sw_refreshVisibleThumbCells];
        [self scrollThumbsToTopIfNeededAnimated:animated];
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

    if (cell.reqId != PHInvalidImageRequestID) {
        [self.imageManager cancelImageRequest:cell.reqId];
        cell.reqId = PHInvalidImageRequestID;
    }
    cell.representedAssetID = aid;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize targetPt = CGSizeMake(SW(140), SW(140));
    CGSize targetPx = CGSizeMake(targetPt.width * scale, targetPt.height * scale);
    NSString *key = SWImgKey(@"thumb_", aid, targetPx);

    UIImage *cached = [self.thumbImageCache objectForKey:key];
    if (cached) {
        cell.imageView.image = cached;
    } else {
        cell.imageView.image = [UIImage imageNamed:@"placeholder"];
    }

    cell.imageView.alpha = 1.0;
    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    BOOL processed = (st != SwipeAssetStatusUnknown);
    cell.imageView.alpha = processed ? 0.2 : 1.0;
    cell.checkIcon.hidden = !processed;

    PHAsset *asset = [self assetForID:aid];
    if (!asset) return cell;

    CGSize target = CGSizeMake(SW(140), SW(140));
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
        
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        
        if (!degraded) {
            [self.thumbImageCache setObject:result forKey:key];
        }

        if (![scell.representedAssetID isEqualToString:aid]) return;
        if (!result) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![scell.representedAssetID isEqualToString:aid]) return;
            scell.imageView.image = result;
        });
    }];
    return cell;
}

- (void)sw_reloadThumbForAssetIDNoFlicker:(NSString *)aid {
    if (aid.length == 0) return;

    NSUInteger idx = [self.allAssetIDs indexOfObject:aid];
    if (idx == NSNotFound) return;

    NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];
    SwipeThumbCell *cell = (SwipeThumbCell *)[self.thumbs cellForItemAtIndexPath:ip];

    NSString *key = SWImgKey(@"thumb_", aid, CGSizeMake(SW(140), SW(140)));
    UIImage *cachedImage = [self.thumbImageCache objectForKey:key];
    
    if (!cachedImage) {
        [self loadImageForAssetID:aid intoImageView:cell.imageView targetSize:CGSizeMake(SW(140), SW(140))];
    } else {
        cell.imageView.image = cachedImage;
    }
}


- (void)sw_updateStackVisibility {
    NSInteger n = (NSInteger)self.unprocessedIDs.count;
    if (self.cards.count < 3) return;

    self.cards[0].hidden = YES; // top
    self.cards[1].hidden = YES; // mid
    self.cards[2].hidden = YES; // bottom

    if (n <= 0) return;

    self.cards[0].hidden = NO;

    if (n >= 2) self.cards[1].hidden = NO;

    if (n >= 3) self.cards[2].hidden = NO;
}

- (BOOL)sw_lockAction {
    if (self.sw_actionLocked) return NO;
    self.sw_actionLocked = YES;

    self.archiveBtn.userInteractionEnabled = NO;
    self.keepBtn.userInteractionEnabled = NO;
    self.undoIconBtn.userInteractionEnabled = NO;
    self.sortIconBtn.userInteractionEnabled = NO;

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

        if (![card.assetID isEqualToString:aid] || card.imageView.image == nil) {
            BOOL reuseFlashRisk = (i == 2); // 底卡最明显
            [self sw_setCard:card
                     assetID:aid
                  targetSize:card.bounds.size
               showWhenReady:reuseFlashRisk];
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

    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        layoutBlock();
    } completion:^(__unused BOOL finished) {
        finish();
        [self sw_updateCardBlurAppearance];
    }];
}

- (void)sw_prepare3CardsIfNeeded {
    if (self.cards.count == 3) return;

    for (UIView *v in self.cardsHost.subviews) [v removeFromSuperview];
    [self.cards removeAllObjects];

    SwipeCardView *bottom = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(2)];
    SwipeCardView *mid    = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(1)];
    SwipeCardView *top    = [[SwipeCardView alloc] initWithFrame:SWCardFrameForIndex(0)];

    bottom.hidden = YES; mid.hidden = YES; top.hidden = YES;

    [self.cardsHost addSubview:bottom];
    [self.cardsHost addSubview:mid];
    [self.cardsHost addSubview:top];

    [self.cards addObject:top];
    [self.cards addObject:mid];
    [self.cards addObject:bottom];

    [self attachPanToTopCard];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(SW(60), SW(60));
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *aid = self.allAssetIDs[indexPath.item];
    SwipeAssetStatus st = [[SwipeManager shared] statusForAssetID:aid];
    if (st != SwipeAssetStatusUnknown) return;

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

- (void)sw_setCard:(SwipeCardView *)card
           assetID:(NSString *)assetID
        targetSize:(CGSize)sizeInPoints
     showWhenReady:(BOOL)showWhenReady {

    if (assetID.length == 0 || !card) return;

    if (card.reqId != PHInvalidImageRequestID) {
        [self.imageManager cancelImageRequest:card.reqId];
        card.reqId = PHInvalidImageRequestID;
    }

    card.assetID = assetID;
    card.representedAssetID = assetID;

    // ✅ 复用时先清掉旧图，避免错图闪现
    card.rawImage = nil;
    card.imageView.image = nil;

    card.sw_revealWhenReady = showWhenReady;
    if (showWhenReady) {
        card.hidden = YES;
        card.alpha = 0.0;
    } else {
        card.hidden = NO;
        card.alpha = 1.0;
    }

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize targetPx = CGSizeMake(sizeInPoints.width * scale, sizeInPoints.height * scale);

    NSString *sharpKey = SWImgKey(@"card_", assetID, targetPx);
    UIImage *sharpCached = [self.cardImageCache objectForKey:sharpKey];
    if (sharpCached) {
        card.rawImage = sharpCached;
        [self sw_applyVisualForCard:card];
        return;
    }

    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    __weak typeof(self) ws = self;
    __weak typeof(card) wcard = card;

    card.reqId = [self.imageManager requestImageForAsset:asset
                                              targetSize:targetPx
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;

        BOOL cancelled = [info[PHImageCancelledKey] boolValue];
        NSError *err = info[PHImageErrorKey];
        if (cancelled || err) return;

        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            SwipeCardView *scard = wcard;
            if (!self || !scard) return;
            if (![scard.representedAssetID isEqualToString:assetID]) return;

            // ✅ rawImage：先用低清顶住，高清到来再覆盖
            if (!scard.rawImage || !degraded) {
                scard.rawImage = result;
            }

            // ✅ 高清才进清晰缓存
            if (!degraded) {
                [self.cardImageCache setObject:result forKey:sharpKey];
            }

            // ✅ 不直接把 result 塞给 imageView（否则非顶卡会变清晰）
            [self sw_applyVisualForCard:scard];
        });
    }];
}

- (PHAsset *)assetForID:(NSString *)assetID {
    if (assetID.length == 0) return nil;

    PHAsset *a = [self.assetCache objectForKey:assetID];
    if (a) return a;

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
