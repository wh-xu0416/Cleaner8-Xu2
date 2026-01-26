#import "AppDelegate.h"
#import "FirebaseCore.h"
#import "ThinkingSDK.h"
#import "AppsFlyerLib/AppsFlyerLib.h"
#import "ASTrackingPermission.h"
#import "PaywallPresenter.h"
#import "LTEventTracker.h"
#import "ASABTestManager.h"
#import "Cleaner8_Xu2-Swift.h"

static NSString * const kASHasLaunchedBeforeKey = @"as_has_launched_before";
static NSString * const kASATTDidFinishNotification = @"as_att_did_finish";
static NSString * const kHasCompletedOnboardingKey = @"hasCompletedOnboarding"; // 和你 Onboarding 里保持一致

#ifdef DEBUG
static inline void ASLog(NSString *module, NSString *msg) {
    NSLog(@"【%@】%@", module ?: @"日志", msg ?: @"");
}
#endif

static inline NSString *ASATTStatusText(NSInteger status) {
    switch (status) {
        case 0: return @"未决定（NotDetermined）";
        case 1: return @"受限（Restricted）";
        case 2: return @"拒绝（Denied）";
        case 3: return @"允许（Authorized）";
        default: return [NSString stringWithFormat:@"未知（%ld）", (long)status];
    }
}

static NSString * const kASFirstInstallTSKey = @"as_first_install_ts";

@interface AppDelegate () <AppsFlyerLibDelegate>
@property (nonatomic, assign) BOOL as_attFinished;
@property (nonatomic, assign) BOOL as_attRequested;
@property (nonatomic, assign) BOOL as_afStarted;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // 是否首次启动（首次安装第一次打开）
    BOOL hasLaunchedBefore = [ud boolForKey:kASHasLaunchedBeforeKey];
    self.as_isFirstLaunch = !hasLaunchedBefore;
    if (!hasLaunchedBefore) {
        [ud setBool:YES forKey:kASHasLaunchedBeforeKey];
    }

    // 监听引导页触发的 ATT 结果
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(as_onATTFinishedFromOnboarding:)
                                                 name:kASATTDidFinishNotification
                                               object:nil];

    // 你原来的 first_install_ts 逻辑保留
    if (![ud objectForKey:kASFirstInstallTSKey]) {
        [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kASFirstInstallTSKey];
    }
    
    // Firebase
    if (AppConstants.firebaseEnabled) {
        ASLog(@"Firebase", @"初始化");
        [FIRApp configure];
        ASLog(@"Firebase", @"已启用并完成 configure");
    } else {
        ASLog(@"Firebase", @"已关闭（AppConstants.firebaseEnabled=false）");
    }

    // ThinkingData：主线程初始化
    if ([NSThread isMainThread]) {
        [self setupThinkingData];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setupThinkingData];
        });
    }

    // 配置 AppsFlyer 参数（不 start）
    [self setupAppsFlyer];

    // 启动 ABTest
    [[ASABTestManager shared] startIfNeeded];

    // Scene 架构下：App active 时再尝试一次
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(as_onDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    ASLog(@"Paywall", @"PaywallPresenter 启动开始");
    [[PaywallPresenter shared] start];
    ASLog(@"Paywall", @"PaywallPresenter 启动结束");
    return YES;
}

- (void)as_onATTFinishedFromOnboarding:(NSNotification *)note {
    NSNumber *num = note.userInfo[@"status"];
    NSInteger status = num.integerValue;
    ASLog(@"ATT", [NSString stringWithFormat:@"收到引导页 ATT 完成通知 status=%@（%ld）",
                   ASATTStatusText(status), (long)status]);

    [self as_markATTFinishedAndTryStart:status];
}

- (void)as_markATTFinishedAndTryStart:(NSInteger)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.as_attFinished = YES;
        [self tryStartAppsFlyerIfPossible];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Active hook

- (void)as_onDidBecomeActive:(NSNotification *)note {
    ASLog(@"App", @"收到 DidBecomeActive 通知");

    BOOL onboardingDone = [[NSUserDefaults standardUserDefaults] boolForKey:kHasCompletedOnboardingKey];

    if (!onboardingDone) {
        ASLog(@"ATT", @"引导未完成：ATT 交给引导页第2页触发");
    } else {
        [self requestATTWhenNoModal];
    }

    [self tryStartAppsFlyerIfPossible];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    ASLog(@"App", @"applicationDidBecomeActive 回调");
    [self tryStartAppsFlyerIfPossible];
}

#pragma mark - ATT

- (void)requestATTWhenNoModal {

    if (self.as_attRequested) return;
    self.as_attRequested = YES;

    ASLog(@"ATT", @"请求开始 准备弹出/查询 ATT 授权状态");

    [ASTrackingPermission requestIfNeededWithDelay:0.0 completion:^(NSInteger status) {

        dispatch_async(dispatch_get_main_queue(), ^{
            ASLog(@"ATT", [NSString stringWithFormat:@"请求结束 状态=%@（%ld）",
                           ASATTStatusText(status), (long)status]);

            [self as_markATTFinishedAndTryStart:status];
        });
    }];
}

#pragma mark - SDK setup

- (void)setupThinkingData {
    ASLog(@"(ThinkingData)", @"初始化开始");
    NSString *appId = AppConstants.thinkingDataAppId;
    NSString *serverUrl = AppConstants.thinkingDataServerUrl;

    [TDAnalytics enableLog:AppConstants.thinkingDataEnableLog];
    [TDAnalytics startAnalyticsWithAppId:appId serverUrl:serverUrl];

    NSString *deviceId = [TDAnalytics getDeviceId];
    if (deviceId.length > 0) {
        [TDAnalytics setDistinctId:deviceId];
        ASLog(@"(ThinkingData)", [NSString stringWithFormat:@"设置 distinctId 成功 %@", deviceId]);
    } else {
        ASLog(@"(ThinkingData)", @"设置 distinctId 失败 deviceId 为空");
    }

    [TDAnalytics enableAutoTrack:(TDAutoTrackEventTypeAppInstall
                                  | TDAutoTrackEventTypeAppStart
                                  | TDAutoTrackEventTypeAppEnd)];

    [TDAnalytics enableThirdPartySharing:TDThirdPartyTypeAppsFlyer];
    ASLog(@"(ThinkingData)", @"初始化结束");
}

- (void)setupAppsFlyer {
    ASLog(@"AppsFlyer", @"配置参数 不start");
    NSString *devKey = AppConstants.appsFlyerDevKey;
    NSString *appleAppId = AppConstants.appsFlyerAppleAppId;

    AppsFlyerLib *af = [AppsFlyerLib shared];
    af.appsFlyerDevKey = devKey;
    af.appleAppID = appleAppId;
    af.delegate = self;

    NSTimeInterval timeout = (NSTimeInterval)AppConstants.appsFlyerAttWaitTimeout;
    [af waitForATTUserAuthorizationWithTimeoutInterval:timeout];
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"初始化结束 已设置 waitForATT(%.0fs)", timeout]);
}

#pragma mark - AppsFlyer start (after ATT)

- (void)tryStartAppsFlyerIfPossible {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self tryStartAppsFlyerIfPossible];
        });
        return;
    }

    if (self.as_afStarted) return;

    if (!self.as_attFinished) {
        ASLog(@"AppsFlyer", @"启动中止 ATT 尚未结束");
        return;
    }

    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    if (state != UIApplicationStateActive) {
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"启动中止 应用非激活态（state=%ld）", (long)state]);
        return;
    }

    ASLog(@"AppsFlyer", @"启动开始 准备设置 customerUserID 并调用 start");

    NSString *distinctId = nil;
    @try { distinctId = [TDAnalytics getDistinctId]; } @catch (__unused NSException *e) {}

    if (distinctId.length > 0) {
        [[AppsFlyerLib shared] setCustomerUserID:distinctId];
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"customerUserID 设置成功 %@", distinctId]);
    } else {
        ASLog(@"AppsFlyer", @"customerUserID 未设置 distinctId 为空");
    }

    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"关键参数 DevKey=%@ AppleAppId=%@",
                         AppConstants.appsFlyerDevKey,
                         AppConstants.appsFlyerAppleAppId]);

    [[AppsFlyerLib shared] start];
    self.as_afStarted = YES;
}

#pragma mark - AppsFlyerLibDelegate

- (void)onConversionDataSuccess:(NSDictionary *)conversionInfo {
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"成功 %@", conversionInfo ?: @{}]);
    [[LTEventTracker shared] track:@"Appsflyer_client" properties:@{@"step": @"c_af_init"}];
}

- (void)onConversionDataFail:(NSError *)error {
    NSString *err = error.localizedDescription ?: @"";
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"失败 %@", err]);
}

- (void)onAppOpenAttribution:(NSDictionary *)attributionData {}
- (void)onAppOpenAttributionFailure:(NSError *)error {}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                          sessionRole:connectingSceneSession.role];
}

@end
