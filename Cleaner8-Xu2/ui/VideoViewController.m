#import "VideoViewController.h"
#import "VideoCompressionMainViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

@interface VideoViewController ()
@property(nonatomic,strong) UIButton *imageBtn;
@property(nonatomic,strong) UIButton *videoBtn;
@property(nonatomic,strong) UIButton *liveBtn;
@property(nonatomic,strong) UIButton *studioBtn;

@property(nonatomic,strong) UIView *settingBar;
@property(nonatomic,strong) UIButton *settingBtn;

// 防止 limited 状态下每次 viewDidAppear 都重复弹系统 picker
@property(nonatomic,assign) BOOL hasPresentedLimitedPickerThisAppear;
@end

@implementation VideoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

    [self buildUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.hasPresentedLimitedPickerThisAppear = NO;
    [self requestAndApplyPhotoPermission];
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
    BOOL authorized = (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);

    // 1) Denied/Restricted：禁用四个功能按钮 + 显示底部 Setting bar
    [self setFeatureButtonsEnabled:!deniedOrRestricted];
    self.settingBar.hidden = !deniedOrRestricted;

    // Limited：拉起系统 picker（仅 iOS14+ 且 SDK 也要 >=14）
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
        if (@available(iOS 14, *)) {
            if (limited && !self.hasPresentedLimitedPickerThisAppear) {
                self.hasPresentedLimitedPickerThisAppear = YES;
                [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:self];
            }
        }
    #endif

    // 3) Authorized：入口可点（保持当前 UI 即可）
    (void)authorized;
}

#pragma mark - UI helpers

- (void)setFeatureButtonsEnabled:(BOOL)enabled {
    self.imageBtn.enabled = enabled;
    self.videoBtn.enabled = enabled;
    self.liveBtn.enabled  = enabled;
    self.studioBtn.enabled = enabled;

    CGFloat alpha = enabled ? 1.0 : 0.4;
    self.imageBtn.alpha = alpha;
    self.videoBtn.alpha = alpha;
    self.liveBtn.alpha = alpha;
    self.studioBtn.alpha = alpha;
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

- (void)buildUI {
    self.imageBtn = [self makeButton:@"Image compressor" action:@selector(tapImage)];
    self.videoBtn = [self makeButton:@"Video compressor" action:@selector(tapVideo)];
    self.liveBtn  = [self makeButton:@"LivePhoto convert" action:@selector(tapLive)];
    self.studioBtn = [self makeButton:@"My Studio" action:@selector(tapStudio)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.imageBtn, self.videoBtn, self.liveBtn, self.studioBtn]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    // Bottom Setting Bar
    self.settingBar = [UIView new];
    self.settingBar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.settingBar.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lab = [UILabel new];
    lab.text = @"Photo access is required.";
    lab.translatesAutoresizingMaskIntoConstraints = NO;

    self.settingBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.settingBtn setTitle:@"Setting" forState:UIControlStateNormal];
    [self.settingBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.settingBtn.translatesAutoresizingMaskIntoConstraints = NO;

    [self.settingBar addSubview:lab];
    [self.settingBar addSubview:self.settingBtn];
    [self.view addSubview:self.settingBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.settingBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.settingBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.settingBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.settingBar.heightAnchor constraintEqualToConstant:56],

        [lab.centerYAnchor constraintEqualToAnchor:self.settingBar.centerYAnchor],
        [lab.leadingAnchor constraintEqualToAnchor:self.settingBar.leadingAnchor constant:16],

        [self.settingBtn.centerYAnchor constraintEqualToAnchor:self.settingBar.centerYAnchor],
        [self.settingBtn.trailingAnchor constraintEqualToAnchor:self.settingBar.trailingAnchor constant:-16],
    ]];

    self.settingBar.hidden = YES;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.layer.cornerRadius = 12;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:1].CGColor;
    b.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - Navigation (占位)
- (void)tapImage { /* push ImageListVC */ }

- (void)tapVideo {
    // 获取当前的导航控制器
    UINavigationController *nav = (UINavigationController *)self.view.window.rootViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return;

    // 创建 VideoCompressionMainViewController 的实例
    VideoCompressionMainViewController *videoCompressionVC = [[VideoCompressionMainViewController alloc] init];
    
    // 使用导航控制器进行跳转
    [nav pushViewController:videoCompressionVC animated:YES];
}

- (void)tapLive  { /* push LivePhotoListVC */ }
- (void)tapStudio{ /* push MyStudioVC */ }

@end
