#import "VideoViewController.h"
#import "VideoCompressionMainViewController.h"
#import "ImageCompressionMainViewController.h"
#import "LivePhotoCompressionMainViewController.h"
#import "ASMyStudioViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import "Common.h"

#pragma mark - UI Helpers
static NSString * const kASLastPhotoAuthStatusKey = @"as_last_photo_auth_status_v1";

static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

@interface ASNoAuthPlaceholderView : UIView
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *t1;
@property(nonatomic,strong) UILabel *t2;
@property(nonatomic,strong) UIButton *btn;
@property(nonatomic,copy) void (^onTap)(void);
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end

@implementation ASNoAuthPlaceholderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.image = [UIImage imageNamed:@"ic_photo_permission_not"];
        [self addSubview:_iconView];

        _t1 = [UILabel new];
        _t1.text = NSLocalizedString(@"Allow Photo Access", nil);
        _t1.textColor = UIColor.blackColor;
        _t1.font = ASFont(20, UIFontWeightMedium);
        _t1.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_t1];

        _t2 = [UILabel new];
        _t2.text = NSLocalizedString(@"To compress photos, videos, and LivePhotos. please allow access to your photo library.", nil);
        _t2.textColor = ASRGB(102, 102, 102);
        _t2.font = ASFont(13, UIFontWeightRegular);
        _t2.numberOfLines = 3;
        _t2.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_t2];

        _btn = [UIButton buttonWithType:UIButtonTypeCustom];
        _btn.backgroundColor = ASBlue();
        _btn.layer.cornerRadius = 35;
        _btn.clipsToBounds = YES;
        [_btn setTitle:NSLocalizedString(@"Go to Settings", nil) forState:UIControlStateNormal];
        [_btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _btn.titleLabel.font = ASFont(20, UIFontWeightRegular);
        _btn.contentEdgeInsets = UIEdgeInsetsMake(18, 0, 18, 0);
        [_btn addTarget:self action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_btn];
    }
    return self;
}

- (void)onBtn {
    if (self.onTap) self.onTap();
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
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

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    CGFloat w = width;
    CGFloat top = 60;
    CGFloat iconBottom = top + 96;
    CGFloat t1Top = iconBottom + 20;
    CGFloat t1Bottom = t1Top + 24;

    CGFloat t2W = w - 90;
    CGSize t2Size = [self.t2 sizeThatFits:CGSizeMake(t2W, CGFLOAT_MAX)];
    CGFloat lineH = self.t2.font.lineHeight;
    CGFloat t2H = MIN(t2Size.height, ceil(lineH * 3.0));

    CGFloat t2Top = t1Bottom + 10;
    CGFloat t2Bottom = t2Top + t2H;

    CGFloat btnTop = t2Bottom + 50;
    CGFloat btnBottom = btnTop + 70;

    return ceil(btnBottom);
}

@end

@interface VideoViewController ()

@property (nonatomic, strong) CAGradientLayer *topGradient;
@property(nonatomic,strong) UILabel *titleLab;

@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIView *content;

// 顶部两个卡片
@property(nonatomic,strong) UIControl *imageCard;
@property(nonatomic,strong) UIControl *videoCard;

@property(nonatomic,strong) UIControl *liveRow;
@property(nonatomic,strong) UIControl *studioRow;

@property(nonatomic,strong) UIButton *imgTodoBtn;
@property(nonatomic,strong) UIButton *videoTodoBtn;
@property(nonatomic,strong) UIButton *liveTodoBtn;
@property(nonatomic,strong) UIButton *studioTodoBtn;

@property(nonatomic,strong) UIControl *settingBar;
@property(nonatomic,strong) UILabel *settingTipLab;
@property(nonatomic,strong) UIButton *settingBtn;

@property(nonatomic,strong) NSLayoutConstraint *imageCardTopToTitle;
@property(nonatomic,strong) NSLayoutConstraint *imageCardTopToSettingBar;
@property(nonatomic,strong) NSLayoutConstraint *settingBarHeightZero;

@property(nonatomic,strong) ASNoAuthPlaceholderView *noAuthView;

@property(nonatomic,strong) NSArray<UIView *> *shadowViews;

@property(nonatomic,assign) BOOL hasShownNoNetworkAlertThisAppear;

@property(nonatomic,assign) BOOL hasNetwork;

@end

@implementation VideoViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ASRGB(246, 248, 251);
    [self buildUI];
    [self applyPhotoAuthStatusIfDetermined];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.navigationController) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }

    self.hasShownNoNetworkAlertThisAppear = NO;

     PHAuthorizationStatus status = [self currentPhotoAuthStatus];
     if (status == PHAuthorizationStatusNotDetermined) {
         [self requestAndApplyPhotoPermission];
     }
}

- (PHAuthorizationStatus)currentPhotoAuthStatus {
    if (@available(iOS 14, *)) {
        return [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
        return [PHPhotoLibrary authorizationStatus];
    }
}

- (void)applyPhotoAuthStatusIfDetermined {
    PHAuthorizationStatus status = [self currentPhotoAuthStatus];
    if (status != PHAuthorizationStatusNotDetermined) {
        [self applyPhotoAuthStatus:status];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;

    CGFloat gradientH = safeTop + 402.0;
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);

    for (UIView *v in self.shadowViews) {
        if (!v) continue;
        CGFloat r = v.layer.cornerRadius;
        v.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:v.bounds cornerRadius:r].CGPath;
    }

    if (!self.noAuthView.hidden) {
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = [self.noAuthView preferredHeightForWidth:w];

        CGRect titleInView = [self.titleLab.superview convertRect:self.titleLab.frame toView:self.view];
        CGFloat minY = CGRectGetMaxY(titleInView) + 20;

        CGFloat viewH = self.view.bounds.size.height;
        CGFloat safeBottom = 0;
        if (@available(iOS 11.0, *)) safeBottom = self.view.safeAreaInsets.bottom;

        CGFloat y = MAX(minY, (viewH - h) * 0.5);
        y = MIN(y, viewH - safeBottom - h - 20);

        self.noAuthView.frame = CGRectMake(0, y, w, h);
    }
}

#pragma mark - Photo Permission

- (void)requestAndApplyPhotoPermission {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];

        if (status == PHAuthorizationStatusNotDetermined) {
            __weak typeof(self) weakSelf = self;
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus newStatus) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf applyPhotoAuthStatus:newStatus];
                });
            }];
        } else {
            [self applyPhotoAuthStatus:status];
        }
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];

        if (status == PHAuthorizationStatusNotDetermined) {
            __weak typeof(self) weakSelf = self;
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf applyPhotoAuthStatus:newStatus];
                });
            }];
        } else {
            [self applyPhotoAuthStatus:status];
        }
    }
}

- (void)applyPhotoAuthStatus:(PHAuthorizationStatus)status {
    BOOL deniedOrRestricted = (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted);
    BOOL limited = (status == PHAuthorizationStatusLimited);

    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setInteger:status forKey:kASLastPhotoAuthStatusKey];
    [ud synchronize];

    self.noAuthView.hidden = !deniedOrRestricted;

    self.scroll.hidden = NO;

    self.scroll.scrollEnabled = !deniedOrRestricted;

    [self setFeatureButtonsEnabled:!deniedOrRestricted];

    self.imageCard.hidden = deniedOrRestricted;
    self.videoCard.hidden = deniedOrRestricted;
    self.liveRow.hidden   = deniedOrRestricted;
    self.studioRow.hidden = deniedOrRestricted;

    if (deniedOrRestricted) {
        self.settingBar.hidden = YES;
        self.settingBarHeightZero.active = YES;
    }

    if (!deniedOrRestricted) {
        BOOL limited = (status == PHAuthorizationStatusLimited);
        BOOL showBubble = limited;
        self.settingBar.hidden = !showBubble;
        self.settingBarHeightZero.active = !showBubble;

        self.imageCardTopToTitle.active = !showBubble;
        self.imageCardTopToSettingBar.active = showBubble;

        self.imageCard.hidden = NO;
        self.videoCard.hidden = NO;
        self.liveRow.hidden   = NO;
        self.studioRow.hidden = NO;
    }

    [UIView animateWithDuration:0.20 animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - UI enable/disable

- (void)setFeatureButtonsEnabled:(BOOL)enabled {
    CGFloat alpha = enabled ? 1.0 : 0.4;

    self.imageCard.userInteractionEnabled = enabled;
    self.videoCard.userInteractionEnabled = enabled;
    self.liveRow.userInteractionEnabled   = enabled;
    self.studioRow.userInteractionEnabled = enabled;

    self.imageCard.alpha = alpha;
    self.videoCard.alpha = alpha;
    self.liveRow.alpha   = alpha;
    self.studioRow.alpha = alpha;
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - Build UI

- (void)buildUI {
    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];

    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0];
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0];

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    self.scroll = [UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.backgroundColor = UIColor.clearColor;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.content = [UIView new];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content.backgroundColor = UIColor.clearColor;
    [self.scroll addSubview:self.content];

    self.titleLab = [UILabel new];
    self.titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLab.text = NSLocalizedString(@"Compress", nil);
    self.titleLab.textColor = UIColor.blackColor;
    self.titleLab.font = ASFont(28, UIFontWeightSemibold);
    self.titleLab.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.titleLab];

    self.settingBar = [UIControl new];
    self.settingBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingBar.backgroundColor = ASBlue(); // #024DFFFF
    self.settingBar.layer.cornerRadius = 20;
    self.settingBar.layer.masksToBounds = YES;

    [self.settingBar addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

    [self.content addSubview:self.settingBar];


    self.settingTipLab = [UILabel new];
    self.settingTipLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingTipLab.text = NSLocalizedString(@"Photo Access Is Required.", nil);
    self.settingTipLab.textColor = UIColor.whiteColor;
    self.settingTipLab.font = ASFont(15, UIFontWeightMedium);
    [self.settingBar addSubview:self.settingTipLab];

    UIColor *accent = ASRGB(9, 255, 243); // #09FFF3FF

    UILabel *settingTextLab = [UILabel new];
    settingTextLab.translatesAutoresizingMaskIntoConstraints = NO;
    settingTextLab.text = NSLocalizedString(@"Setting", nil);
    settingTextLab.textColor = accent;
    settingTextLab.font = ASFont(15, UIFontWeightMedium);

    UIImageView *moreIcon = [UIImageView new];
    moreIcon.translatesAutoresizingMaskIntoConstraints = NO;
    moreIcon.image = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    moreIcon.tintColor = accent;
    moreIcon.contentMode = UIViewContentModeScaleAspectFit;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[settingTextLab, moreIcon]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisHorizontal;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.spacing = 10;
    [self.settingBar addSubview:rightStack];

    [self.settingTipLab setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                       forAxis:UILayoutConstraintAxisHorizontal];
    [self.settingTipLab setContentHuggingPriority:UILayoutPriorityDefaultLow
                                          forAxis:UILayoutConstraintAxisHorizontal];

    [rightStack setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                forAxis:UILayoutConstraintAxisHorizontal];
    [rightStack setContentHuggingPriority:UILayoutPriorityRequired
                                  forAxis:UILayoutConstraintAxisHorizontal];


    self.settingBar.hidden = YES;
    self.settingBarHeightZero = [self.settingBar.heightAnchor constraintEqualToConstant:0];
    self.settingBarHeightZero.active = YES;

    // small cards
    self.imageCard = [self buildHomeSmallCardWithIcon:@"ic_img"
                                               title:NSLocalizedString(@"Image", nil)
                                            subtitle:NSLocalizedString(@"Compressor", nil)
                                            todoIcon:@"ic_todo_small"
                                              action:@selector(tapImage)
                                          todoBtnRef:&_imgTodoBtn];

    self.videoCard = [self buildHomeSmallCardWithIcon:@"ic_video"
                                               title:NSLocalizedString(@"Video", nil)
                                            subtitle:NSLocalizedString(@"Compressor", nil)
                                            todoIcon:@"ic_todo_small"
                                              action:@selector(tapVideo)
                                          todoBtnRef:&_videoTodoBtn];

    [self.content addSubview:self.imageCard];
    [self.content addSubview:self.videoCard];

    self.liveRow = [self buildHomeRowWithIcon:@"ic_livephoto"
                                       title:NSLocalizedString(@"Live Photo", nil)
                                    subtitle:NSLocalizedString(@"Compressor", nil)
                                    todoIcon:@"ic_todo_big"
                                      action:@selector(tapLive)
                                   todoBtnRef:&_liveTodoBtn];

    self.studioRow = [self buildHomeRowWithIcon:@"ic_studio"
                                         title:NSLocalizedString(@"My studio", nil)
                                      subtitle:nil
                                      todoIcon:@"ic_todo_big"
                                        action:@selector(tapStudio)
                                     todoBtnRef:&_studioTodoBtn];

    [self.content addSubview:self.liveRow];
    [self.content addSubview:self.studioRow];

    // 无权限占位
    [self buildNoAuthPlaceholder];

    // 约束
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.content.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [self.content.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [self.content.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.content.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor],

        [self.titleLab.topAnchor constraintEqualToAnchor:self.content.safeAreaLayoutGuide.topAnchor constant:13],
        [self.titleLab.centerXAnchor constraintEqualToAnchor:self.content.centerXAnchor],

        [self.settingBar.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:20],
        [self.settingBar.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:20],
        [self.settingBar.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-20],
        
        [self.settingTipLab.leadingAnchor constraintEqualToAnchor:self.settingBar.leadingAnchor constant:20],
        [self.settingTipLab.topAnchor constraintEqualToAnchor:self.settingBar.topAnchor constant:16],
        [self.settingTipLab.bottomAnchor constraintEqualToAnchor:self.settingBar.bottomAnchor constant:-16],

        [self.settingTipLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightStack.leadingAnchor constant:-12],

        [rightStack.trailingAnchor constraintEqualToAnchor:self.settingBar.trailingAnchor constant:-20],
        [rightStack.centerYAnchor constraintEqualToAnchor:self.settingBar.centerYAnchor],

        [moreIcon.widthAnchor constraintEqualToConstant:16],
        [moreIcon.heightAnchor constraintEqualToConstant:16],


        [self.imageCard.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:20],

        [self.videoCard.topAnchor constraintEqualToAnchor:self.imageCard.topAnchor],
        [self.videoCard.leadingAnchor constraintEqualToAnchor:self.imageCard.trailingAnchor constant:12],
        [self.videoCard.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-20],

        [self.imageCard.widthAnchor constraintEqualToAnchor:self.videoCard.widthAnchor],

        [self.imageCard.heightAnchor constraintEqualToAnchor:self.imageCard.widthAnchor multiplier:(196.0/175.0)],
        [self.videoCard.heightAnchor constraintEqualToAnchor:self.videoCard.widthAnchor multiplier:(196.0/175.0)],

        [self.liveRow.topAnchor constraintEqualToAnchor:self.imageCard.bottomAnchor constant:20],
        [self.liveRow.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:20],
        [self.liveRow.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-20],
        [self.liveRow.heightAnchor constraintEqualToConstant:110],

        [self.studioRow.topAnchor constraintEqualToAnchor:self.liveRow.bottomAnchor constant:20],
        [self.studioRow.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:20],
        [self.studioRow.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-20],
        [self.studioRow.heightAnchor constraintEqualToConstant:110],

        [self.studioRow.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor constant:-34],
    ]];

    self.imageCardTopToTitle =
        [self.imageCard.topAnchor constraintEqualToAnchor:self.titleLab.bottomAnchor constant:64];
    self.imageCardTopToSettingBar =
        [self.imageCard.topAnchor constraintEqualToAnchor:self.settingBar.bottomAnchor constant:20];

    self.imageCardTopToTitle.active = YES;
    self.imageCardTopToSettingBar.active = NO;

    self.shadowViews = @[self.imageCard, self.videoCard, self.liveRow, self.studioRow];
}

- (void)buildNoAuthPlaceholder {
    self.noAuthView = [[ASNoAuthPlaceholderView alloc] initWithFrame:CGRectZero];
    self.noAuthView.hidden = YES;

    __weak typeof(self) weakSelf = self;
    self.noAuthView.onTap = ^{
        [weakSelf openSettings];
    };

    [self.view addSubview:self.noAuthView];
}

#pragma mark - Small Card

- (UIControl *)buildHomeSmallCardWithIcon:(NSString *)iconName
                                   title:(NSString *)title
                                subtitle:(NSString *)subtitle
                                todoIcon:(NSString *)todoIcon
                                  action:(SEL)sel
                              todoBtnRef:(UIButton * __strong *)todoBtnRef {

    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [card addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];

    card.layer.cornerRadius = 34;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.10].CGColor;
    card.layer.shadowOpacity = 1.0;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    card.layer.shadowRadius = 20;

    UIImageView *bg = [UIImageView new];
    bg.translatesAutoresizingMaskIntoConstraints = NO;
    bg.image = [[UIImage imageNamed:@"ic_home_card"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    bg.contentMode = UIViewContentModeScaleToFill;
    bg.layer.cornerRadius = 34;
    bg.layer.masksToBounds = YES;
    [card addSubview:bg];

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];

    UILabel *t1 = [UILabel new];
    t1.translatesAutoresizingMaskIntoConstraints = NO;
    t1.text = title;
    t1.textColor = UIColor.blackColor;
    t1.font = ASFont(24, UIFontWeightMedium);

    UILabel *t2 = [UILabel new];
    t2.translatesAutoresizingMaskIntoConstraints = NO;
    t2.text = subtitle;
    t2.textColor = UIColor.blackColor;
    t2.font = ASFont(17, UIFontWeightMedium);

    [card addSubview:t1];
    [card addSubview:t2];

    UIButton *todoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    todoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *todo = [[UIImage imageNamed:todoIcon] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [todoBtn setImage:todo forState:UIControlStateNormal];
    todoBtn.adjustsImageWhenHighlighted = NO;
    [todoBtn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:todoBtn];

    if (todoBtnRef) *todoBtnRef = todoBtn;

    [NSLayoutConstraint activateConstraints:@[
        [bg.topAnchor constraintEqualToAnchor:card.topAnchor],
        [bg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [bg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [bg.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:4],
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:-14],
        [icon.widthAnchor constraintEqualToConstant:107],
        [icon.heightAnchor constraintEqualToConstant:94],

        [t1.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:30],
        [t1.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-30],
        [t1.topAnchor constraintEqualToAnchor:card.topAnchor constant:78],

        [t2.leadingAnchor constraintEqualToAnchor:t1.leadingAnchor],
        [t2.trailingAnchor constraintEqualToAnchor:t1.trailingAnchor],
        [t2.topAnchor constraintEqualToAnchor:t1.bottomAnchor constant:4],

        [todoBtn.leadingAnchor constraintEqualToAnchor:t1.leadingAnchor],
        [todoBtn.topAnchor constraintEqualToAnchor:t2.bottomAnchor constant:18],
        [todoBtn.widthAnchor constraintEqualToConstant:40],
        [todoBtn.heightAnchor constraintEqualToConstant:24],
    ]];

    return card;
}

#pragma mark - Row Card

- (UIControl *)buildHomeRowWithIcon:(NSString *)iconName
                             title:(NSString *)title
                          subtitle:(NSString * _Nullable)subtitle
                          todoIcon:(NSString *)todoIcon
                            action:(SEL)sel
                        todoBtnRef:(UIButton * __strong *)todoBtnRef {

    UIControl *row = [UIControl new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.whiteColor;
    row.layer.cornerRadius = 24;
    row.layer.masksToBounds = NO;

    row.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    row.layer.shadowOpacity = 1.0;
    row.layer.shadowOffset = CGSizeMake(0, 10);
    row.layer.shadowRadius = 20;

    [row addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:icon];

    UILabel *t1 = [UILabel new];
    t1.translatesAutoresizingMaskIntoConstraints = NO;
    t1.text = title;
    t1.textColor = UIColor.blackColor;
    t1.font = ASFont(24, UIFontWeightMedium);
    [row addSubview:t1];

    UILabel *t2 = nil;
    if (subtitle.length > 0) {
        t2 = [UILabel new];
        t2.translatesAutoresizingMaskIntoConstraints = NO;
        t2.text = subtitle;
        t2.textColor = UIColor.blackColor;
        t2.font = ASFont(17, UIFontWeightMedium);
        [row addSubview:t2];
    }

    UIButton *todoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    todoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *todo = [[UIImage imageNamed:todoIcon] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [todoBtn setImage:todo forState:UIControlStateNormal];
    todoBtn.adjustsImageWhenHighlighted = NO;
    [todoBtn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:todoBtn];
    if (todoBtnRef) *todoBtnRef = todoBtn;

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray arrayWithArray:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:4],
        [icon.topAnchor constraintEqualToAnchor:row.topAnchor constant:8],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:107],
        [icon.heightAnchor constraintEqualToConstant:94],

        [todoBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-31],
        [todoBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [todoBtn.widthAnchor constraintEqualToConstant:60],
        [todoBtn.heightAnchor constraintEqualToConstant:36],
    ]];

    if (t2) {
        [cs addObjectsFromArray:@[
            [t1.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9],
            [t1.bottomAnchor constraintEqualToAnchor:row.centerYAnchor constant:-2],

            [t2.leadingAnchor constraintEqualToAnchor:t1.leadingAnchor],
            [t2.topAnchor constraintEqualToAnchor:row.centerYAnchor constant:2],
        ]];
    } else {
        [cs addObjectsFromArray:@[
            [t1.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9],
            [t1.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:cs];
    return row;
}

#pragma mark - Navigation

- (void)tapImage {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    ImageCompressionMainViewController *imageCompressionVC = [[ImageCompressionMainViewController alloc] init];
    [nav pushViewController:imageCompressionVC animated:YES];
}

- (void)tapVideo {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    VideoCompressionMainViewController *videoCompressionVC = [[VideoCompressionMainViewController alloc] init];
    [nav pushViewController:videoCompressionVC animated:YES];
}

- (void)tapLive  {
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    LivePhotoCompressionMainViewController *livePhotoCompressionVC = [[LivePhotoCompressionMainViewController alloc] init];
    [nav pushViewController:livePhotoCompressionVC animated:YES];
}

- (void)tapStudio{
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;
    ASMyStudioViewController *studioCompressionVC = [[ASMyStudioViewController alloc] init];
    [nav pushViewController:studioCompressionVC animated:YES];
}

@end
