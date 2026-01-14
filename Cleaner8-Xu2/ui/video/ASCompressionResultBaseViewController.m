#import "ASCompressionResultBaseViewController.h"
#import "ASMyStudioViewController.h"
#import "ASMediaPreviewViewController.h"
#import <Photos/Photos.h>

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat ASScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

#pragma mark - Helpers

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline UIColor *ASGrayBG(void){ return [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0]; }
static inline UIColor *ASE5EDFF(void){ return [UIColor colorWithRed:229/255.0 green:237/255.0 blue:255/255.0 alpha:1.0]; }

static NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

#pragma mark - Bottom Sheet

typedef void(^ASDeleteSheetBlock)(void);

@interface ASDeleteOriginalBottomSheet : UIView
+ (void)presentInViewController:(UIViewController *)vc
                          title:(NSString *)title
                       onDelete:(ASDeleteSheetBlock)onDelete;
@end

@interface ASDeleteOriginalBottomSheet ()
@property (nonatomic, strong) NSLayoutConstraint *deleteBottomC;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *sheetShadowView;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *reserveBtn;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, copy, nullable) void (^onDelete)(void);
@end

@implementation ASDeleteOriginalBottomSheet

+ (void)presentInViewController:(UIViewController *)vc
                          title:(NSString *)title
                       onDelete:(ASDeleteSheetBlock)onDelete {

    if (!vc.view.window && vc.presentedViewController) vc = vc.presentedViewController;

    ASDeleteOriginalBottomSheet *v = [ASDeleteOriginalBottomSheet new];
    v.onDelete = onDelete;
    [v buildUIWithTitle:title ?: NSLocalizedString(@"Delete original ?",nil)];

    UIView *container = vc.view.window;
    if (!container) {
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { container = w; break; }
                }
                if (container) break;
            }
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            container = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
        }
    }
    if (!container) container = vc.view;

    [container addSubview:v];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:container.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [container layoutIfNeeded];
    [v layoutIfNeeded];
    [v animateIn];
}

- (void)buildUIWithTitle:(NSString *)title {
    self.backgroundColor = UIColor.clearColor;

    self.dimView = [UIView new];
    self.dimView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.10];
    [self addSubview:self.dimView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapDim:)];
    tap.cancelsTouchesInView = NO;
    [self.dimView addGestureRecognizer:tap];
    self.dimView.userInteractionEnabled = YES;

    self.sheetShadowView = [UIView new];
    self.sheetShadowView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.sheetShadowView];

    self.sheetView = [UIView new];
    self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sheetView.backgroundColor = UIColor.whiteColor;
    self.sheetView.layer.cornerRadius = AS(16);
    if (@available(iOS 11.0, *)) {
        self.sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    self.sheetView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) self.sheetView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.sheetShadowView addSubview:self.sheetView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = title;
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.font = ASFontS(20, UIFontWeightMedium);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.sheetView addSubview:self.titleLabel];

    self.reserveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.reserveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.reserveBtn setTitle:NSLocalizedString(@"Reserve",nil) forState:UIControlStateNormal];
    self.reserveBtn.titleLabel.font = ASFontS(20, UIFontWeightRegular);
    [self.reserveBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.reserveBtn.backgroundColor = ASBlue();
    self.reserveBtn.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) self.reserveBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [self.reserveBtn addTarget:self action:@selector(onReserve) forControlEvents:UIControlEventTouchUpInside];
    [self.sheetView addSubview:self.reserveBtn];

    self.deleteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.deleteBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deleteBtn setTitle:NSLocalizedString(@"Delete",nil) forState:UIControlStateNormal];
    self.deleteBtn.titleLabel.font = ASFontS(20, UIFontWeightMedium);
    [self.deleteBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.deleteBtn.backgroundColor = ASGrayBG();
    self.deleteBtn.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) self.deleteBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [self.deleteBtn addTarget:self action:@selector(onTapDelete) forControlEvents:UIControlEventTouchUpInside];
    [self.sheetView addSubview:self.deleteBtn];

    self.reserveBtn.layer.cornerRadius = AS(25.5);
    self.deleteBtn.layer.cornerRadius  = AS(25.5);
    self.reserveBtn.layer.masksToBounds = YES;
    self.deleteBtn.layer.masksToBounds  = YES;

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];
    self.deleteBottomC = [self.deleteBtn.bottomAnchor constraintEqualToAnchor:self.sheetView.bottomAnchor constant:-AS(20)];
    [self.deleteBottomC setActive:YES];

    [cs addObjectsFromArray:@[
        [self.dimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.dimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.dimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.dimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.sheetShadowView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.sheetShadowView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.sheetShadowView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
        [self.sheetShadowView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.sheetView.leadingAnchor constraintEqualToAnchor:self.sheetShadowView.leadingAnchor],
        [self.sheetView.trailingAnchor constraintEqualToAnchor:self.sheetShadowView.trailingAnchor],
        [self.sheetView.topAnchor constraintEqualToAnchor:self.sheetShadowView.topAnchor],
        [self.sheetView.bottomAnchor constraintEqualToAnchor:self.sheetShadowView.bottomAnchor],

        // 内容布局
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor constant:AS(30)],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:AS(20)],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-AS(20)],

        [self.reserveBtn.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:AS(37)],
        [self.reserveBtn.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:AS(20)],
        [self.reserveBtn.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-AS(20)],
        [self.reserveBtn.heightAnchor constraintEqualToConstant:AS(51)],

        [self.deleteBtn.topAnchor constraintEqualToAnchor:self.reserveBtn.bottomAnchor constant:AS(15)],
        [self.deleteBtn.leadingAnchor constraintEqualToAnchor:self.reserveBtn.leadingAnchor],
        [self.deleteBtn.trailingAnchor constraintEqualToAnchor:self.reserveBtn.trailingAnchor],
        [self.deleteBtn.heightAnchor constraintEqualToConstant:AS(51)],
    ]];

    [NSLayoutConstraint activateConstraints:cs];

    self.sheetShadowView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:(0x33/255.0)].CGColor;
    self.sheetShadowView.layer.shadowOpacity = 1.0;
    self.sheetShadowView.layer.shadowOffset = CGSizeMake(0, -AS(5));
    self.sheetShadowView.layer.shadowRadius = AS(10);

    self.dimView.alpha = 0.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat h1 = CGRectGetHeight(self.reserveBtn.bounds);
    CGFloat h2 = CGRectGetHeight(self.deleteBtn.bounds);
    if (h1 > 0) self.reserveBtn.layer.cornerRadius = h1 * 0.5;
    if (h2 > 0) self.deleteBtn.layer.cornerRadius  = h2 * 0.5;

    if (@available(iOS 13.0, *)) {
        self.reserveBtn.layer.cornerCurve = kCACornerCurveContinuous;
        self.deleteBtn.layer.cornerCurve  = kCACornerCurveContinuous;
    }
    self.reserveBtn.layer.masksToBounds = YES;
    self.deleteBtn.layer.masksToBounds  = YES;

    CGRect r = self.sheetShadowView.bounds;
    if (!CGRectIsEmpty(r)) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r
                                               byRoundingCorners:(UIRectCornerTopLeft|UIRectCornerTopRight)
                                                     cornerRadii:CGSizeMake(AS(16), AS(16))];
        self.sheetShadowView.layer.shadowPath = p.CGPath;
    }
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    self.deleteBottomC.constant = -(AS(20) + self.safeAreaInsets.bottom);
}

- (void)animateIn {
    [self layoutIfNeeded];
    CGFloat h = self.sheetShadowView.bounds.size.height;
    self.sheetShadowView.transform = CGAffineTransformMakeTranslation(0, h);

    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.dimView.alpha = 1.0;
        self.sheetShadowView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)animateOut:(void(^)(void))completion {
    CGFloat h = self.sheetShadowView.bounds.size.height;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.dimView.alpha = 0.0;
        self.sheetShadowView.transform = CGAffineTransformMakeTranslation(0, h);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

- (void)onTapDim:(UITapGestureRecognizer *)gr {
    CGPoint p = [gr locationInView:self];
    if (CGRectContainsPoint(self.sheetShadowView.frame, p)) return;
    [self onReserve];
}
- (void)onReserve { [self animateOut:nil]; }

- (void)onTapDelete {
    ASDeleteSheetBlock deleteBlock = self.onDelete;

    [self animateOut:^{
        if (!deleteBlock) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { deleteBlock(); }
            @catch (NSException *e) {
                NSLog(@"[DeleteSheet] onDelete exception: %@ %@", e.name, e.reason);
            }
        });
    }];
}

@end

#pragma mark - Base VC

@interface ASCompressionResultBaseViewController ()
@property (nonatomic, strong) id<ASCompressionResultSummary> summary;

@property (nonatomic, strong) UIView *topCard;
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UIButton *homeBtn;

@property (nonatomic, strong) UIView *headerBG;

@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UIImageView *starFloat;
@property (nonatomic, strong) UIImageView *staticIconView;

@property (nonatomic, strong) UILabel *greatLabel;
@property (nonatomic, strong) UILabel *infoLabel;

@property (nonatomic, strong) UIView *table;
@property (nonatomic, strong) UILabel *vBefore;
@property (nonatomic, strong) UILabel *vAfter;
@property (nonatomic, strong) UILabel *vSaved;

@property (nonatomic, strong) UIControl *studioRow;
@property (nonatomic, strong) UIImageView *studioIcon;
@property (nonatomic, strong) UILabel *studioLabel;
@property (nonatomic, strong) UIButton *todoBtn;

@property (nonatomic, assign) BOOL hasAskedDelete;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *scrollContentView;

@end

@implementation ASCompressionResultBaseViewController

- (instancetype)initWithSummary:(id<ASCompressionResultSummary>)summary {
    if (self = [super init]) _summary = summary;
    return self;
}

#pragma mark - Override points

- (BOOL)useStaticPreviewIcon { return NO; }
- (NSString *)staticPreviewIconName { return nil; }
- (CGSize)staticPreviewSize { return CGSizeMake(180, 170); }
- (NSString *)deleteSheetTitle { return NSLocalizedString(@"Delete original ?",nil); }
- (NSString *)itemSingular { return NSLocalizedString(@"item",nil); }
- (NSString *)itemPlural   { return NSLocalizedString(@"items",nil); }
- (NSString *)homeIconName { return @"ic_back_home"; }
- (BOOL)shouldShowHomeButton { return YES; }

#pragma mark - Life

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ASGrayBG();
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self fillData];

    if (![self useStaticPreviewIcon]) {
        [self loadThumbIfNeeded];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.hasAskedDelete) {
        self.hasAskedDelete = YES;
        [self askDeleteOriginalIfNeeded];
    }
}

#pragma mark - Delete helpers (unchanged)

- (NSArray<PHAsset *> *)as_deletableAssetsFrom:(NSArray<PHAsset *> *)assets
                               blockedCountOut:(NSInteger *)blockedCountOut {
    NSMutableArray<PHAsset *> *ok = [NSMutableArray array];
    NSInteger blocked = 0;

    for (PHAsset *a in assets) {
        BOOL canDelete = YES;
        if (@available(iOS 8.0, *)) {
            canDelete = [a canPerformEditOperation:PHAssetEditOperationDelete];
        }
        if (canDelete) [ok addObject:a];
        else blocked++;
    }

    if (blockedCountOut) *blockedCountOut = blocked;
    return ok.copy;
}

- (UIViewController *)as_topPresentingVC {
    UIViewController *vc = self.navigationController ?: self;
    vc = vc.presentedViewController ?: vc;

    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }

    if ([vc isKindOfClass:UIAlertController.class] && vc.presentingViewController) {
        vc = vc.presentingViewController;
    }
    return vc;
}

- (void)as_deleteOriginalAssetsSafely:(NSArray<PHAsset *> *)assets {
    if (assets.count == 0) return;

    PHAuthorizationStatus st;
    if (@available(iOS 14.0, *)) st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    else st = [PHPhotoLibrary authorizationStatus];

    if (!(st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited)) {
        [self as_showSimpleAlert:NSLocalizedString(@"No Permission",nil)
                         message:NSLocalizedString(@"Please allow Photos access to delete originals.",nil)];
        return;
    }

    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
    for (PHAsset *a in assets) {
        if (a.localIdentifier.length) [ids addObject:a.localIdentifier];
    }
    if (ids.count == 0) return;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) {
        [self as_showSimpleAlert:NSLocalizedString(@"Not Found",nil)
                         message:NSLocalizedString(@"These photos are no longer available.",nil)];
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:fr];
    } completionHandler:^(__unused BOOL success, __unused NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
        });
    }];
}

- (void)as_showSimpleAlert:(NSString *)title message:(NSString *)msg {
    UIViewController *vc = self;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:ac animated:YES completion:nil];
}

#pragma mark - UI

- (void)buildUI {
    CGFloat headerH = AS(56);
    CGFloat side20  = AS(20);

    self.navBar = [UIView new];
    self.navBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.navBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.navBar];

    self.headerBG = [UIView new];
    self.headerBG.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerBG.backgroundColor = UIColor.whiteColor;
    [self.view insertSubview:self.headerBG belowSubview:self.navBar];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];
    self.backBtn.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.navBar addSubview:self.backBtn];

    self.homeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *homeImg = [UIImage imageNamed:[self homeIconName]];
    if (!homeImg && @available(iOS 13.0, *)) {
        homeImg = [UIImage systemImageNamed:@"house"];
        homeImg = [[homeImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] copy];
        self.homeBtn.tintColor = ASBlue();
    } else {
        homeImg = [homeImg imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    [self.homeBtn setImage:homeImg forState:UIControlStateNormal];
    self.homeBtn.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
    self.homeBtn.adjustsImageWhenHighlighted = NO;
    self.homeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.homeBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.homeBtn addTarget:self action:@selector(onHome) forControlEvents:UIControlEventTouchUpInside];
    [self.navBar addSubview:self.homeBtn];
    self.homeBtn.hidden = ![self shouldShowHomeButton];

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.scrollView];

    self.scrollContentView = [UIView new];
    self.scrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollContentView.backgroundColor = UIColor.clearColor;
    [self.scrollView addSubview:self.scrollContentView];

    self.topCard = [UIView new];
    self.topCard.backgroundColor = UIColor.whiteColor;
    self.topCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.topCard.layer.cornerRadius = AS(34);
    if (@available(iOS 11.0,*)) {
        self.topCard.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    self.topCard.layer.masksToBounds = YES;
    [self.scrollContentView addSubview:self.topCard];

    UIView *previewRef = nil;

    if ([self useStaticPreviewIcon]) {
        self.staticIconView = [UIImageView new];
        self.staticIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.staticIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.staticIconView.image = [[UIImage imageNamed:[self staticPreviewIconName]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.topCard addSubview:self.staticIconView];
        previewRef = self.staticIconView;
    } else {
        self.thumbView = [UIImageView new];
        self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
        self.thumbView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        self.thumbView.layer.cornerRadius = AS(22);
        self.thumbView.layer.masksToBounds = YES;
        [self.topCard addSubview:self.thumbView];

        self.playIcon = [UIImageView new];
        self.playIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.playIcon.image = [[UIImage imageNamed:@"ic_play"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.playIcon.contentMode = UIViewContentModeScaleAspectFit;
        [self.thumbView addSubview:self.playIcon];

        self.thumbView.userInteractionEnabled = YES;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapPreview)];
        [self.thumbView addGestureRecognizer:tap];

        self.starFloat = [UIImageView new];
        self.starFloat.translatesAutoresizingMaskIntoConstraints = NO;
        self.starFloat.image = [[UIImage imageNamed:@"ic_star_float"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.starFloat.contentMode = UIViewContentModeScaleAspectFit;
        [self.topCard addSubview:self.starFloat];

        previewRef = self.thumbView;
    }

    self.greatLabel = [UILabel new];
    self.greatLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.greatLabel.text = NSLocalizedString(@"Great!",nil);
    self.greatLabel.textColor = UIColor.blackColor;
    self.greatLabel.font = ASFontS(34, UIFontWeightMedium);
    self.greatLabel.textAlignment = NSTextAlignmentCenter;
    [self.topCard addSubview:self.greatLabel];

    self.infoLabel = [UILabel new];
    self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.infoLabel.textColor = UIColor.blackColor;
    self.infoLabel.font = ASFontS(12, UIFontWeightMedium);
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    self.infoLabel.numberOfLines = 0;
    [self.topCard addSubview:self.infoLabel];

    self.table = [self buildStatsTable];
    [self.topCard addSubview:self.table];

    // ===== studioRow（也滚动）=====
    self.studioRow = [UIControl new];
    self.studioRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.studioRow.backgroundColor = UIColor.whiteColor;
    self.studioRow.layer.cornerRadius = AS(24);
    self.studioRow.layer.masksToBounds = NO;
    [self.studioRow addTarget:self action:@selector(onStudio) forControlEvents:UIControlEventTouchUpInside];
    self.studioRow.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    self.studioRow.layer.shadowOpacity = 1.0;
    self.studioRow.layer.shadowOffset = CGSizeMake(0, AS(10));
    self.studioRow.layer.shadowRadius = AS(20);
    [self.scrollContentView addSubview:self.studioRow];

    self.studioIcon = [UIImageView new];
    self.studioIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.studioIcon.image = [[UIImage imageNamed:@"ic_studio"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.studioIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.studioRow addSubview:self.studioIcon];

    self.studioLabel = [UILabel new];
    self.studioLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.studioLabel.text = NSLocalizedString(@"My studio",nil);
    self.studioLabel.textColor = UIColor.blackColor;
    self.studioLabel.font = ASFontS(24, UIFontWeightMedium);
    [self.studioRow addSubview:self.studioLabel];

    self.todoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.todoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *todo = [[UIImage imageNamed:@"ic_todo_big"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.todoBtn setImage:todo forState:UIControlStateNormal];
    self.todoBtn.adjustsImageWhenHighlighted = NO;
    [self.todoBtn addTarget:self action:@selector(onStudio) forControlEvents:UIControlEventTouchUpInside];
    [self.studioRow addSubview:self.todoBtn];

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];

    [cs addObjectsFromArray:@[
        [self.headerBG.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.headerBG.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerBG.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerBG.bottomAnchor constraintEqualToAnchor:self.navBar.bottomAnchor],

        [self.navBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.navBar.heightAnchor constraintEqualToConstant:headerH],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.navBar.leadingAnchor constant:AS(6)],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:self.navBar.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:AS(44)],
        [self.backBtn.heightAnchor constraintEqualToConstant:AS(44)],

        [self.homeBtn.trailingAnchor constraintEqualToAnchor:self.navBar.trailingAnchor constant:-AS(12)],
        [self.homeBtn.centerYAnchor constraintEqualToAnchor:self.navBar.centerYAnchor],
        [self.homeBtn.widthAnchor constraintEqualToConstant:AS(44)],
        [self.homeBtn.heightAnchor constraintEqualToConstant:AS(44)],
    ]];

    [cs addObjectsFromArray:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.navBar.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.scrollContentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollContentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.scrollContentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.scrollContentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.scrollContentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    [cs addObjectsFromArray:@[
        [self.topCard.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:0],
        [self.topCard.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor],
        [self.topCard.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor],
    ]];

    if ([self useStaticPreviewIcon]) {
        CGSize sz = [self staticPreviewSize];
        [cs addObjectsFromArray:@[
            [self.staticIconView.topAnchor constraintEqualToAnchor:self.topCard.topAnchor constant:AS(18)],
            [self.staticIconView.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
            [self.staticIconView.widthAnchor constraintEqualToConstant:AS(sz.width)],
            [self.staticIconView.heightAnchor constraintEqualToConstant:AS(sz.height)],
        ]];
    } else {
        [cs addObjectsFromArray:@[
            [self.thumbView.topAnchor constraintEqualToAnchor:self.topCard.topAnchor constant:AS(10)],
            [self.thumbView.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
            [self.thumbView.widthAnchor constraintEqualToConstant:AS(180)],
            [self.thumbView.heightAnchor constraintEqualToConstant:AS(240)],

            [self.playIcon.leadingAnchor constraintEqualToAnchor:self.thumbView.leadingAnchor constant:AS(13)],
            [self.playIcon.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor constant:AS(13)],
            [self.playIcon.widthAnchor constraintEqualToConstant:AS(26)],
            [self.playIcon.heightAnchor constraintEqualToConstant:AS(26)],

            [self.starFloat.centerXAnchor constraintEqualToAnchor:self.thumbView.centerXAnchor],
            [self.starFloat.centerYAnchor constraintEqualToAnchor:self.thumbView.centerYAnchor],
            [self.starFloat.widthAnchor constraintEqualToConstant:AS(267)],
            [self.starFloat.heightAnchor constraintEqualToConstant:AS(216)],
        ]];
    }

    [cs addObjectsFromArray:@[
        [self.greatLabel.topAnchor constraintEqualToAnchor:previewRef.bottomAnchor constant:AS(18)],
        [self.greatLabel.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side20],
        [self.greatLabel.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side20],

        [self.infoLabel.topAnchor constraintEqualToAnchor:self.greatLabel.bottomAnchor constant:AS(12)],
        [self.infoLabel.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:AS(40)],
        [self.infoLabel.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-AS(40)],

        [self.table.topAnchor constraintEqualToAnchor:self.infoLabel.bottomAnchor constant:AS(20)],
        [self.table.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:AS(20)],
        [self.table.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-AS(20)],
        [self.table.heightAnchor constraintEqualToConstant:AS(110)],

        [self.topCard.bottomAnchor constraintEqualToAnchor:self.table.bottomAnchor constant:AS(35)],

        [self.studioRow.topAnchor constraintEqualToAnchor:self.topCard.bottomAnchor constant:AS(30)],
        [self.studioRow.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:AS(20)],
        [self.studioRow.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-AS(20)],
        [self.studioRow.heightAnchor constraintEqualToConstant:AS(110)],

        [self.studioIcon.leadingAnchor constraintEqualToAnchor:self.studioRow.leadingAnchor constant:AS(22)],
        [self.studioIcon.centerYAnchor constraintEqualToAnchor:self.studioRow.centerYAnchor],
        [self.studioIcon.widthAnchor constraintEqualToConstant:AS(72)],
        [self.studioIcon.heightAnchor constraintEqualToConstant:AS(72)],

        [self.studioLabel.leadingAnchor constraintEqualToAnchor:self.studioIcon.trailingAnchor constant:AS(18)],
        [self.studioLabel.centerYAnchor constraintEqualToAnchor:self.studioRow.centerYAnchor],

        [self.todoBtn.trailingAnchor constraintEqualToAnchor:self.studioRow.trailingAnchor constant:-AS(22)],
        [self.todoBtn.centerYAnchor constraintEqualToAnchor:self.studioRow.centerYAnchor],
        [self.todoBtn.widthAnchor constraintEqualToConstant:AS(60)],
        [self.todoBtn.heightAnchor constraintEqualToConstant:AS(36)],

        [self.studioRow.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-AS(22)],
    ]];

    [NSLayoutConstraint activateConstraints:cs];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.studioRow.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.studioRow.bounds cornerRadius:AS(24)].CGPath;
    });
}

#pragma mark - Preview tap

- (void)onTapPreview {
    NSArray<PHAsset *> *assets = self.summary.originalAssets ?: @[];
    if (assets.count == 0) return;

    NSArray<PHAsset *> *previewAssets = assets;
    NSIndexSet *preSel = [NSIndexSet indexSet];

    ASMediaPreviewViewController *p =
    [[ASMediaPreviewViewController alloc] initWithAssets:previewAssets
                                           initialIndex:0
                                        selectedIndexes:preSel];

    p.bestIndex = 0;
    p.showsBestBadge = YES;

    if (self.navigationController) {
        [self.navigationController pushViewController:p animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:p];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - Table

- (UIView *)vSep {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = [ASBlue() colorWithAlphaComponent:0.25];
    [v.widthAnchor constraintEqualToConstant:1].active = YES;
    return v;
}

- (UIView *)wrapCenter:(UIView *)view {
    UIView *c = [UIView new];
    c.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:view];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
        [view.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
    ]];
    return c;
}

- (UILabel *)makeValueLabel:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = color;
    l.font = ASFontS(16, UIFontWeightSemibold);
    l.text = @"--";
    return l;
}

- (UIView *)makeTitleCellTop:(NSString *)top bottom:(NSString *)bottom {
    UILabel *t = [UILabel new];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 2;

    NSMutableAttributedString *att = [NSMutableAttributedString new];
    NSDictionary *aTop = @{ NSFontAttributeName: ASFontS(15, UIFontWeightSemibold), NSForegroundColorAttributeName: UIColor.blackColor };
    NSDictionary *aBottom = @{ NSFontAttributeName: ASFontS(12, UIFontWeightSemibold), NSForegroundColorAttributeName: UIColor.blackColor };
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:top attributes:aTop]];
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:aTop]];
    [att appendAttributedString:[[NSAttributedString alloc] initWithString:bottom attributes:aBottom]];
    t.attributedText = att;

    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:t];
    [NSLayoutConstraint activateConstraints:@[
        [t.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [t.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
        [t.leadingAnchor constraintGreaterThanOrEqualToAnchor:wrap.leadingAnchor constant:AS(6)],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor constant:-AS(6)],
    ]];
    return wrap;
}

- (UIView *)makeTitleCellSingle:(NSString *)title {
    UILabel *t = [UILabel new];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.textAlignment = NSTextAlignmentCenter;
    t.textColor = UIColor.blackColor;
    t.font = ASFontS(15, UIFontWeightSemibold);
    t.text = title;

    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:t];
    [NSLayoutConstraint activateConstraints:@[
        [t.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [t.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
        [t.leadingAnchor constraintGreaterThanOrEqualToAnchor:wrap.leadingAnchor constant:AS(6)],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor constant:-AS(6)],
    ]];
    return wrap;
}

- (UIView *)buildStatsTable {
    UIView *table = [UIView new];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.layer.cornerRadius = AS(16);
    table.layer.borderWidth = AS(2);
    table.layer.borderColor = ASBlue().CGColor;
    table.layer.masksToBounds = YES;

    UIView *topRow = [UIView new];
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    topRow.backgroundColor = ASE5EDFF();
    [table addSubview:topRow];

    UIView *bottomRow = [UIView new];
    bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    [table addSubview:bottomRow];

    UIView *hSep = [UIView new];
    hSep.translatesAutoresizingMaskIntoConstraints = NO;
    hSep.backgroundColor = [ASBlue() colorWithAlphaComponent:0.25];
    [table addSubview:hSep];

    UIView *t1 = [self makeTitleCellTop:NSLocalizedString(@"Before",nil) bottom:NSLocalizedString(@"Compression",nil)];
    UIView *t2 = [self makeTitleCellTop:NSLocalizedString(@"After",nil) bottom:NSLocalizedString(@"Compression",nil)];
    UIView *t3 = [self makeTitleCellSingle:NSLocalizedString(@"Space Saved",nil)];

    UIStackView *topStack = [[UIStackView alloc] initWithArrangedSubviews:@[t1, [self vSep], t2, [self vSep], t3]];
    topStack.translatesAutoresizingMaskIntoConstraints = NO;
    topStack.axis = UILayoutConstraintAxisHorizontal;
    topStack.distribution = UIStackViewDistributionFill;
    [topRow addSubview:topStack];
    [t1.widthAnchor constraintEqualToAnchor:t2.widthAnchor].active = YES;
    [t2.widthAnchor constraintEqualToAnchor:t3.widthAnchor].active = YES;

    self.vBefore = [self makeValueLabel:UIColor.blackColor];
    self.vAfter  = [self makeValueLabel:ASBlue()];
    self.vSaved  = [self makeValueLabel:ASBlue()];

    UIView *b1 = [self wrapCenter:self.vBefore];
    UIView *b2 = [self wrapCenter:self.vAfter];
    UIView *b3 = [self wrapCenter:self.vSaved];

    UIStackView *bottomStack = [[UIStackView alloc] initWithArrangedSubviews:@[b1, [self vSep], b2, [self vSep], b3]];
    bottomStack.translatesAutoresizingMaskIntoConstraints = NO;
    bottomStack.axis = UILayoutConstraintAxisHorizontal;
    bottomStack.distribution = UIStackViewDistributionFill;
    [bottomRow addSubview:bottomStack];
    [b1.widthAnchor constraintEqualToAnchor:b2.widthAnchor].active = YES;
    [b2.widthAnchor constraintEqualToAnchor:b3.widthAnchor].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [topRow.topAnchor constraintEqualToAnchor:table.topAnchor],
        [topRow.leadingAnchor constraintEqualToAnchor:table.leadingAnchor],
        [topRow.trailingAnchor constraintEqualToAnchor:table.trailingAnchor],
        [topRow.heightAnchor constraintEqualToConstant:AS(55)],

        [hSep.topAnchor constraintEqualToAnchor:topRow.bottomAnchor],
        [hSep.leadingAnchor constraintEqualToAnchor:table.leadingAnchor],
        [hSep.trailingAnchor constraintEqualToAnchor:table.trailingAnchor],
        [hSep.heightAnchor constraintEqualToConstant:AS(1)],

        [bottomRow.topAnchor constraintEqualToAnchor:hSep.bottomAnchor],
        [bottomRow.leadingAnchor constraintEqualToAnchor:table.leadingAnchor],
        [bottomRow.trailingAnchor constraintEqualToAnchor:table.trailingAnchor],
        [bottomRow.bottomAnchor constraintEqualToAnchor:table.bottomAnchor],

        [topStack.topAnchor constraintEqualToAnchor:topRow.topAnchor],
        [topStack.bottomAnchor constraintEqualToAnchor:topRow.bottomAnchor],
        [topStack.leadingAnchor constraintEqualToAnchor:topRow.leadingAnchor],
        [topStack.trailingAnchor constraintEqualToAnchor:topRow.trailingAnchor],

        [bottomStack.topAnchor constraintEqualToAnchor:bottomRow.topAnchor],
        [bottomStack.bottomAnchor constraintEqualToAnchor:bottomRow.bottomAnchor],
        [bottomStack.leadingAnchor constraintEqualToAnchor:bottomRow.leadingAnchor],
        [bottomStack.trailingAnchor constraintEqualToAnchor:bottomRow.trailingAnchor],
    ]];

    return table;
}

#pragma mark - Data

- (void)fillData {
    NSInteger count = self.summary.inputCount;
    NSString *noun = (count == 1) ? [self itemSingular] : [self itemPlural];
    NSString *aux  = (count == 1) ? NSLocalizedString(@"has",nil) : NSLocalizedString(@"have",nil);

    self.infoLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld %@ %@ been compressed and saved to your system album",nil),
                           (long)count, noun, aux];

    self.vBefore.text = ASHumanSize(self.summary.beforeBytes) ?: @"--";
    self.vAfter.text  = ASHumanSize(self.summary.afterBytes)  ?: @"--";
    self.vSaved.text  = ASHumanSize(self.summary.savedBytes)  ?: @"--";
}

- (void)loadThumbIfNeeded {
    PHAsset *asset = self.summary.originalAssets.firstObject;
    if (!asset) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    CGFloat scale = UIScreen.mainScreen.scale;

    CGSize target = CGSizeMake(AS(180) * scale * 2.0, AS(240) * scale * 2.0);

    __weak typeof(self) weakSelf = self;
    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        NSNumber *degraded = info[PHImageResultIsDegradedKey];
        if (degraded.boolValue) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.thumbView.image = result;
        });
    }];
}

#pragma mark - Delete original

- (void)askDeleteOriginalIfNeeded {
    NSArray<PHAsset *> *originals = self.summary.originalAssets ?: @[];
    if (originals.count == 0) return;

    NSInteger blocked = 0;
    NSArray<PHAsset *> *deletable = [self as_deletableAssetsFrom:originals blockedCountOut:&blocked];

    if (deletable.count == 0) {
        [self as_showSimpleAlert:NSLocalizedString(@"Can't delete",nil)
                         message:NSLocalizedString(@"These photos can't be deleted (shared/synced or restricted).",nil)];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [ASDeleteOriginalBottomSheet presentInViewController:self
                                                  title:[self deleteSheetTitle]
                                               onDelete:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self as_deleteOriginalAssetsSafely:deletable];
    }];
}

#pragma mark - Actions

- (void)onBack { [self.navigationController popToRootViewControllerAnimated:YES]; }

- (void)onHome {
    UINavigationController *nav = self.navigationController;
    if (!nav) return;

    Class homeCls = NSClassFromString(@"VideoViewController");
    if (homeCls) {
        for (UIViewController *vc in nav.viewControllers) {
            if ([vc isKindOfClass:homeCls]) {
                [nav popToViewController:vc animated:YES];
                return;
            }
        }
    }
    [nav popToRootViewControllerAnimated:YES];
}

- (void)onStudio {
    ASMyStudioViewController *studio = [ASMyStudioViewController new];
    UINavigationController *nav = self.navigationController;
    if (!nav) return;

    UIViewController *root = nav.viewControllers.firstObject;
    [nav setViewControllers:@[root, studio] animated:YES];
}

@end
