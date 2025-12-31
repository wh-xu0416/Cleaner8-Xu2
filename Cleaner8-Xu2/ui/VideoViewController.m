#import "VideoViewController.h"
#import "VideoCompressionMainViewController.h"
#import "ImageCompressionMainViewController.h"
#import "LivePhotoCompressionMainViewController.h"
#import "ASMyStudioViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <Network/Network.h>

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

@interface VideoViewController ()

@property(nonatomic,strong) UIImageView *bgTop;
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

@property(nonatomic,strong) UIView *noAuthView;

@property(nonatomic,strong) NSArray<UIView *> *shadowViews;

@property(nonatomic,assign) BOOL hasShownNoNetworkAlertThisAppear;

@property(nonatomic,assign) nw_path_monitor_t pathMonitor;
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
    [self startNetworkMonitor];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.navigationController) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }

    self.hasShownNoNetworkAlertThisAppear = NO;

    [self requestAndApplyPhotoPermission];
    [self checkNetworkAndMaybeAlert];
}

- (void)startNetworkMonitor {
    if (@available(iOS 12.0, *)) {
        if (self.pathMonitor) return;

        self.hasNetwork = YES;

        nw_path_monitor_t m = nw_path_monitor_create();
        self.pathMonitor = m;

        dispatch_queue_t q = dispatch_queue_create("as.net.monitor", DISPATCH_QUEUE_SERIAL);
        nw_path_monitor_set_queue(m, q);

        __weak typeof(self) weakSelf = self;
        nw_path_monitor_set_update_handler(m, ^(nw_path_t  _Nonnull path) {
            BOOL ok = (nw_path_get_status(path) == nw_path_status_satisfied);
            weakSelf.hasNetwork = ok;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf) return;
                if (!ok) {
                    [weakSelf checkNetworkAndMaybeAlert];
                }
            });
        });

        nw_path_monitor_start(m);
    }
}

- (void)checkNetworkAndMaybeAlert {
    if (!self.isViewLoaded || self.view.window == nil) return;
    if (self.hasShownNoNetworkAlertThisAppear) return;

    if (!self.hasNetwork) {
        self.hasShownNoNetworkAlertThisAppear = YES;
        // [self showNoNetworkAlert];
    }
}

- (void)dealloc {
    if (@available(iOS 12.0, *)) {
        if (self.pathMonitor) {
            nw_path_monitor_cancel(self.pathMonitor);
            self.pathMonitor = nil;
        }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    for (UIView *v in self.shadowViews) {
        if (!v) continue;
        CGFloat r = v.layer.cornerRadius;
        v.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:v.bounds cornerRadius:r].CGPath;
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
    self.scroll.hidden = deniedOrRestricted;

    [self setFeatureButtonsEnabled:!deniedOrRestricted];

    BOOL showBubble = (!deniedOrRestricted && limited);
    self.settingBar.hidden = !showBubble;
    self.settingBarHeightZero.active = !showBubble;

    self.imageCardTopToTitle.active = !showBubble;
    self.imageCardTopToSettingBar.active = showBubble;

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
    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    [self.view addSubview:self.bgTop];

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
    self.titleLab.text = @"Compressly";
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
    self.settingTipLab.text = @"Photo Access Is Required.";
    self.settingTipLab.textColor = UIColor.whiteColor;
    self.settingTipLab.font = ASFont(15, UIFontWeightMedium);
    [self.settingBar addSubview:self.settingTipLab];

    UIColor *accent = ASRGB(9, 255, 243); // #09FFF3FF

    UILabel *settingTextLab = [UILabel new];
    settingTextLab.translatesAutoresizingMaskIntoConstraints = NO;
    settingTextLab.text = @"Setting";
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
                                               title:@"Image"
                                            subtitle:@"Compressor"
                                            todoIcon:@"ic_todo_small"
                                              action:@selector(tapImage)
                                          todoBtnRef:&_imgTodoBtn];

    self.videoCard = [self buildHomeSmallCardWithIcon:@"ic_video"
                                               title:@"Video"
                                            subtitle:@"Compressor"
                                            todoIcon:@"ic_todo_small"
                                              action:@selector(tapVideo)
                                          todoBtnRef:&_videoTodoBtn];

    [self.content addSubview:self.imageCard];
    [self.content addSubview:self.videoCard];

    self.liveRow = [self buildHomeRowWithIcon:@"ic_livephoto"
                                       title:@"Live Photo"
                                    subtitle:@"Compressor"
                                    todoIcon:@"ic_todo_big"
                                      action:@selector(tapLive)
                                   todoBtnRef:&_liveTodoBtn];

    self.studioRow = [self buildHomeRowWithIcon:@"ic_studio"
                                         title:@"My studio"
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
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:360],

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
    self.noAuthView = [UIView new];
    self.noAuthView.translatesAutoresizingMaskIntoConstraints = NO;
    self.noAuthView.backgroundColor = UIColor.clearColor;
    self.noAuthView.hidden = YES;
    [self.view addSubview:self.noAuthView];

    UIImageView *img = [UIImageView new];
    img.translatesAutoresizingMaskIntoConstraints = NO;
    img.image = [UIImage imageNamed:@"ic_photo_permission_not"];
    img.contentMode = UIViewContentModeScaleAspectFit;
    [self.noAuthView addSubview:img];

    UILabel *t1 = [UILabel new];
    t1.translatesAutoresizingMaskIntoConstraints = NO;
    t1.text = @"Allow Photo Access";
    t1.textColor = UIColor.blackColor;
    t1.font = ASFont(20, UIFontWeightMedium);
    t1.textAlignment = NSTextAlignmentCenter;
    [self.noAuthView addSubview:t1];

    UILabel *t2 = [UILabel new];
    t2.translatesAutoresizingMaskIntoConstraints = NO;
    t2.text = @"To compress photos, videos, and LivePhotos.\nplease allow access to your photo library.";
    t2.textColor = ASRGB(102, 102, 102); // #666666FF
    t2.font = ASFont(13, UIFontWeightRegular);
    t2.numberOfLines = 0;
    t2.textAlignment = NSTextAlignmentCenter;
    [self.noAuthView addSubview:t2];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = ASBlue(); // #024DFFFF
    btn.layer.cornerRadius = 20;
    btn.layer.masksToBounds = YES;
    [btn setTitle:@"Go to Settings" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = ASFont(20, UIFontWeightRegular);
    btn.contentEdgeInsets = UIEdgeInsetsMake(23, 0, 23, 0);
    [btn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.noAuthView addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [self.noAuthView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.noAuthView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.noAuthView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.noAuthView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [img.topAnchor constraintEqualToAnchor:self.noAuthView.topAnchor],
        [img.centerXAnchor constraintEqualToAnchor:self.noAuthView.centerXAnchor],
        [img.widthAnchor constraintEqualToConstant:96],
        [img.heightAnchor constraintEqualToConstant:96],

        [t1.topAnchor constraintEqualToAnchor:img.bottomAnchor constant:20],
        [t1.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:30],
        [t1.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-30],

        [t2.topAnchor constraintEqualToAnchor:t1.bottomAnchor constant:10],
        [t2.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:45],
        [t2.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-45],

        [btn.topAnchor constraintEqualToAnchor:t2.bottomAnchor constant:86],
        [btn.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:45],
        [btn.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-45],

        [btn.bottomAnchor constraintEqualToAnchor:self.noAuthView.bottomAnchor],
    ]];
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
