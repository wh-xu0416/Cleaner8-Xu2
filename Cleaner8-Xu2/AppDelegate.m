#import "AppDelegate.h"
#import "FirebaseCore.h"
#import "ThinkingSDK.h"
#import "AppsFlyerLib/AppsFlyerLib.h"
#import "ASTrackingPermission.h"
#import "PaywallPresenter.h"
#import "LTEventTracker.h"
#import "ASABTestManager.h"
#import "Cleaner8_Xu2-Swift.h"

static inline void ASLog(NSString *module, NSString *msg) {
    NSLog(@"【%@】%@", module ?: @"日志", msg ?: @"");
}

static inline BOOL ASIsBlank(NSString *s) {
    return (s == nil || s.length == 0);
}

static inline BOOL ASIsPlaceholder(NSString *s) {
    if (ASIsBlank(s)) return YES;
    return ([s containsString:@"YOUR_"] || [s containsString:@"YOUR-"] || [s containsString:@"<YOUR"]);
}

static inline BOOL ASIsValidHttpUrl(NSString *urlStr) {
    if (ASIsBlank(urlStr)) return NO;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
}

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
    if (![ud objectForKey:kASFirstInstallTSKey]) {
        [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kASFirstInstallTSKey];
    }
    
    ASLog(@"App", @"应用启动：didFinishLaunching 开始");

    // Firebase
    ASLog(@"Firebase", @"初始化");
    if (AppConstants.firebaseEnabled) {
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Active hook

- (void)as_onDidBecomeActive:(NSNotification *)note {
    ASLog(@"App", @"收到 DidBecomeActive 通知");
    [self requestATTWhenNoModal];
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

    ASLog(@"ATT", @"请求开始：准备弹出/查询 ATT 授权状态");

    [ASTrackingPermission requestIfNeededWithDelay:0.0 completion:^(NSInteger status) {

        dispatch_async(dispatch_get_main_queue(), ^{
            ASLog(@"ATT", [NSString stringWithFormat:@"请求结束：状态=%@（%ld）",
                           ASATTStatusText(status), (long)status]);

            self.as_attFinished = YES;
            [self tryStartAppsFlyerIfPossible];
        });
    }];
}

#pragma mark - SDK setup

- (void)setupThinkingData {

    ASLog(@"数数(ThinkingData)", @"初始化开始");

    NSString *appId = AppConstants.thinkingDataAppId;
    NSString *serverUrl = AppConstants.thinkingDataServerUrl;

    if (ASIsPlaceholder(appId) || ASIsBlank(appId)) {
        ASLog(@"数数(ThinkingData)", @"初始化失败：AppId 还是占位符（请替换 AppConstants.thinkingDataAppId）");
        return;
    }
    if (!ASIsValidHttpUrl(serverUrl) || ASIsPlaceholder(serverUrl)) {
        ASLog(@"数数(ThinkingData)", @"初始化失败：ServerUrl 非法或是占位符（必须是 http/https 完整 URL，例如 https://xxx；请替换 AppConstants.thinkingDataServerUrl）");
        return;
    }

    [TDAnalytics enableLog:AppConstants.thinkingDataEnableLog];
    [TDAnalytics startAnalyticsWithAppId:appId serverUrl:serverUrl];

    NSString *deviceId = [TDAnalytics getDeviceId];
    if (deviceId.length > 0) {
        [TDAnalytics setDistinctId:deviceId];
        ASLog(@"数数(ThinkingData)", [NSString stringWithFormat:@"设置 distinctId 成功：%@", deviceId]);
    } else {
        ASLog(@"数数(ThinkingData)", @"设置 distinctId 失败：deviceId 为空");
    }

    [TDAnalytics enableAutoTrack:(TDAutoTrackEventTypeAppInstall
                                  | TDAutoTrackEventTypeAppStart
                                  | TDAutoTrackEventTypeAppEnd)];

    [TDAnalytics enableThirdPartySharing:TDThirdPartyTypeAppsFlyer];

    ASLog(@"数数(ThinkingData)", @"初始化结束：本地初始化已完成（网络是否可达看后续 sync 请求）");
}

- (void)setupAppsFlyer {

    ASLog(@"AppsFlyer", @"初始化开始（配置参数阶段，不会 start）");

    NSString *devKey = AppConstants.appsFlyerDevKey;
    NSString *appleAppId = AppConstants.appsFlyerAppleAppId;

    if (ASIsPlaceholder(devKey) || ASIsBlank(devKey)) {
        ASLog(@"AppsFlyer", @"初始化失败：DevKey 还是占位/为空（请替换 AppConstants.appsFlyerDevKey）");
        return;
    }
    if (ASIsPlaceholder(appleAppId) || ASIsBlank(appleAppId)) {
        ASLog(@"AppsFlyer", @"初始化失败：AppleAppId 还是占位/为空（请替换 AppConstants.appsFlyerAppleAppId，纯数字字符串）");
        return;
    }

    AppsFlyerLib *af = [AppsFlyerLib shared];
    af.appsFlyerDevKey = devKey;
    af.appleAppID = appleAppId;
    af.delegate = self;

#if DEBUG
    af.isDebug = YES;
    ASLog(@"AppsFlyer", @"调试模式：已开启 isDebug=YES（仅开发环境使用）");
#endif

    NSTimeInterval timeout = (NSTimeInterval)AppConstants.appsFlyerAttWaitTimeout;
    [af waitForATTUserAuthorizationWithTimeoutInterval:timeout];
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"初始化结束：参数已配置 + 已设置 waitForATT(%.0fs)", timeout]);
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
        ASLog(@"AppsFlyer", @"启动中止：ATT 尚未结束");
        return;
    }

    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    if (state != UIApplicationStateActive) {
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"启动中止：应用非激活态（state=%ld）", (long)state]);
        return;
    }

    ASLog(@"AppsFlyer", @"启动开始：准备设置 customerUserID 并调用 start");

    NSString *distinctId = nil;
    @try { distinctId = [TDAnalytics getDistinctId]; } @catch (__unused NSException *e) {}

    if (distinctId.length > 0) {
        [[AppsFlyerLib shared] setCustomerUserID:distinctId];
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"customerUserID 设置成功：%@", distinctId]);
    } else {
        ASLog(@"AppsFlyer", @"customerUserID 未设置：distinctId 为空");
    }

    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"关键参数：DevKey=%@ AppleAppId=%@",
                         AppConstants.appsFlyerDevKey,
                         AppConstants.appsFlyerAppleAppId]);

    [[AppsFlyerLib shared] start];
    self.as_afStarted = YES;
}

#pragma mark - AppsFlyerLibDelegate

- (void)onConversionDataSuccess:(NSDictionary *)conversionInfo {
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"成功：%@", conversionInfo ?: @{}]);
    [[LTEventTracker shared] track:@"Appsflyer_client" properties:@{@"step": @"c_af_init"}];
}

- (void)onConversionDataFail:(NSError *)error {
    NSString *err = error.localizedDescription ?: @"";
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"失败：%@", err]);
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
