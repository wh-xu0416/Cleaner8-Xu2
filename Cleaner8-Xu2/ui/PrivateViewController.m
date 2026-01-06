#import "PrivateViewController.h"
#import "UIViewController+ASPrivateBackground.h"
#import "UIViewController+ASRootNav.h"
#import "ASColors.h"
#import "ASPasscodeManager.h"
#import "SetPasswordViewController.h"
#import "PrivateListViewController.h"
#import "ASPrivatePermissionBanner.h"
#import <Photos/Photos.h>

@interface ASPrivateEntryCard : UIControl
@property (nonatomic, strong) UIImageView *leftIcon;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UIControl *pill;
@end

@implementation ASPrivateEntryCard
- (instancetype)initWithIcon:(NSString *)icon title:(NSString *)title {
    if (self=[super initWithFrame:CGRectZero]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 16;
        self.layer.masksToBounds = YES;

        self.leftIcon = [UIImageView new];
        self.leftIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.leftIcon.contentMode = UIViewContentModeScaleAspectFit;
        self.leftIcon.image = [[UIImage imageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self addSubview:self.leftIcon];

        self.title = [UILabel new];
        self.title.translatesAutoresizingMaskIntoConstraints = NO;
        self.title.text = title;
        self.title.textColor = UIColor.blackColor;
        self.title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        [self addSubview:self.title];

        // pill
        self.pill = [UIControl new];
        self.pill.translatesAutoresizingMaskIntoConstraints = NO;
        self.pill.backgroundColor = ASBlue();
        self.pill.layer.cornerRadius = 23;
        self.pill.layer.masksToBounds = YES;
        [self addSubview:self.pill];

        UILabel *add = [UILabel new];
        add.translatesAutoresizingMaskIntoConstraints = NO;
        add.text = @"Add";
        add.textColor = UIColor.whiteColor;
        add.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        [self.pill addSubview:add];

        UIImageView *arrow = [UIImageView new];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        arrow.contentMode = UIViewContentModeScaleAspectFit;
        arrow.image = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.pill addSubview:arrow];

        [NSLayoutConstraint activateConstraints:@[
            [self.leftIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.leftIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.leftIcon.widthAnchor constraintEqualToConstant:32],
            [self.leftIcon.heightAnchor constraintEqualToConstant:32],

            [self.title.leadingAnchor constraintEqualToAnchor:self.leftIcon.trailingAnchor constant:20],
            [self.title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.pill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [self.pill.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.title.trailingAnchor constraintLessThanOrEqualToAnchor:self.pill.leadingAnchor constant:-12],

            [add.leadingAnchor constraintEqualToAnchor:self.pill.leadingAnchor constant:15],
            [add.topAnchor constraintEqualToAnchor:self.pill.topAnchor constant:11],
            [add.bottomAnchor constraintEqualToAnchor:self.pill.bottomAnchor constant:-11],
            [add.centerYAnchor constraintEqualToAnchor:self.pill.centerYAnchor],

            [arrow.leadingAnchor constraintEqualToAnchor:add.trailingAnchor constant:10],
            [arrow.centerYAnchor constraintEqualToAnchor:self.pill.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:9],
            [arrow.heightAnchor constraintEqualToConstant:15],
            [arrow.trailingAnchor constraintEqualToAnchor:self.pill.trailingAnchor constant:-19],

            [self.heightAnchor constraintEqualToConstant:(14+48+14)],
        ]];

    }
    return self;
}
@end

@interface PrivateViewController ()
@property (nonatomic, strong) UILabel *navTitle;
@property (nonatomic, strong) UIButton *lockBtn;

@property (nonatomic, strong) ASPrivateEntryCard *photoCard;
@property (nonatomic, strong) ASPrivateEntryCard *videoCard;
@property (nonatomic, strong) ASPrivatePermissionBanner *banner;
@end

@implementation PrivateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self as_applyPrivateBackground];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLockUI)
                                                 name:ASPasscodeChangedNotification object:nil];

    [self buildUI];
    [self updateLockUI];
    [self refreshPermissionBanner];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self as_updatePrivateBackgroundLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // top bar
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:bar];

    self.navTitle = [UILabel new];
    self.navTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.navTitle.text = @"Private";
    self.navTitle.textColor = UIColor.blackColor;
    self.navTitle.font = [UIFont systemFontOfSize:34 weight:UIFontWeightMedium];
    [bar addSubview:self.navTitle];

    self.lockBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.lockBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    [self.lockBtn addTarget:self action:@selector(lockTap) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:self.lockBtn];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:45],

        [self.navTitle.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:20],
        [self.navTitle.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [self.lockBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-20],
        [self.lockBtn.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.lockBtn.widthAnchor constraintEqualToConstant:44],
        [self.lockBtn.heightAnchor constraintEqualToConstant:44],
    ]];

    // image + text
    UIImageView *img = [UIImageView new];
    img.translatesAutoresizingMaskIntoConstraints = NO;
    img.contentMode = UIViewContentModeScaleAspectFit;
    img.image = [[UIImage imageNamed:@"ic_private"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.view addSubview:img];

    UILabel *desc = [UILabel new];
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    desc.text = @"Add Photos & Videos to Protected";
    desc.textColor = UIColor.blackColor;
    desc.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    desc.textAlignment = NSTextAlignmentCenter;
    desc.numberOfLines = 2;
    [self.view addSubview:desc];

    [NSLayoutConstraint activateConstraints:@[
        [img.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:40],
        [img.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [img.widthAnchor constraintEqualToConstant:182],
        [img.heightAnchor constraintEqualToConstant:168],

        [desc.topAnchor constraintEqualToAnchor:img.bottomAnchor constant:2],
        [desc.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];

    // cards
    self.photoCard = [[ASPrivateEntryCard alloc] initWithIcon:@"ic_photo_permission_not" title:@"Secret Photos"];
    self.videoCard = [[ASPrivateEntryCard alloc] initWithIcon:@"ic_video_lock" title:@"Secret Videos"];
    [self.view addSubview:self.photoCard];
    [self.view addSubview:self.videoCard];

    [self.photoCard addTarget:self action:@selector(openPhotos) forControlEvents:UIControlEventTouchUpInside];
    [self.videoCard addTarget:self action:@selector(openVideos) forControlEvents:UIControlEventTouchUpInside];
    [self.photoCard.pill addTarget:self action:@selector(openPhotos) forControlEvents:UIControlEventTouchUpInside];
    [self.videoCard.pill addTarget:self action:@selector(openVideos) forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [self.photoCard.topAnchor constraintEqualToAnchor:desc.bottomAnchor constant:40],
        [self.photoCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.photoCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],

        [self.videoCard.topAnchor constraintEqualToAnchor:self.photoCard.bottomAnchor constant:20],
        [self.videoCard.leadingAnchor constraintEqualToAnchor:self.photoCard.leadingAnchor],
        [self.videoCard.trailingAnchor constraintEqualToAnchor:self.photoCard.trailingAnchor],
    ]];

    // permission banner (默认隐藏，按权限显示)
    self.banner = [ASPrivatePermissionBanner new];
    self.banner.translatesAutoresizingMaskIntoConstraints = NO;
    self.banner.hidden = YES;
    __weak typeof(self) ws = self;
    self.banner.onGoSettings = ^{
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        [ws refreshPermissionBanner];
    };
    [self.view addSubview:self.banner];

    [NSLayoutConstraint activateConstraints:@[
        [self.banner.topAnchor constraintEqualToAnchor:self.videoCard.bottomAnchor constant:34],
        [self.banner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.banner.widthAnchor constraintEqualToConstant:310],
        [self.banner.heightAnchor constraintEqualToConstant:145],
    ]];
}

- (void)updateLockUI {
    BOOL enabled = [ASPasscodeManager isEnabled];
    NSString *icon = enabled ? @"ic_locked" : @"ic_unlock";
    UIImage *img = [[UIImage imageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.lockBtn setImage:img forState:UIControlStateNormal];
}

- (void)lockTap {
    UINavigationController *nav = [self as_rootNav];
    if (![nav isKindOfClass:UINavigationController.class]) return;

    if (![ASPasscodeManager isEnabled]) {
        // 默认开锁：设置密码
        SetPasswordViewController *vc = [SetPasswordViewController new];
        vc.flow = ASPasswordFlowSet;
        vc.onSuccess = ^{};
        [nav pushViewController:vc animated:YES];
    } else {
        // 锁上：验证后关闭密码
        SetPasswordViewController *vc = [SetPasswordViewController new];
        vc.flow = ASPasswordFlowDisable;
        vc.onSuccess = ^{};
        [nav pushViewController:vc animated:YES];
    }
}

#pragma mark - Permission

- (BOOL)needFullAccess {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        return (s != PHAuthorizationStatusAuthorized); // limited / denied / notDetermined 都视为需要 Full
    } else {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatus];
        return (s != PHAuthorizationStatusAuthorized);
    }
}

- (void)refreshPermissionBanner {
    self.banner.hidden = ![self needFullAccess];
}

#pragma mark - Navigation

- (void)openPhotos { [self openListWithType:0 title:@"Secret Photos"]; }
- (void)openVideos { [self openListWithType:1 title:@"Secret Videos"]; }

- (void)openListWithType:(NSInteger)type title:(NSString *)title {
    UINavigationController *nav = [self as_rootNav];
    if (![nav isKindOfClass:UINavigationController.class]) return;

    void (^pushList)(void) = ^{
        PrivateListViewController *list = [PrivateListViewController new];
        list.mediaType = (type==0)?ASPrivateMediaTypePhoto:ASPrivateMediaTypeVideo;
        list.navTitleText = title;
        [nav pushViewController:list animated:YES];
    };

    if ([ASPasscodeManager isEnabled]) {
        SetPasswordViewController *vc = [SetPasswordViewController new];
        vc.flow = ASPasswordFlowVerify;

        __weak typeof(nav) weakNav = nav;
        vc.onSuccess = ^{
            // 关键：验证成功后，用 rootNav 继续 push 列表
            // 此时密码页还在栈顶，先 pop 掉它再 push
            [weakNav popViewControllerAnimated:NO];
            pushList();
        };
        [nav pushViewController:vc animated:YES];
    } else {
        pushList();
    }
}

@end
