#import "AppDelegate.h"
#import "FirebaseCore.h"
#import "ThinkingSDK.h"
#import "AppsFlyerLib/AppsFlyerLib.h"
#import "ASTrackingPermission.h"
#import "PaywallPresenter.h"

/// ====== 这里换自己的配置 ======
static NSString * const kTDAppId      = @"YOUR_THINKINGDATA_APP_ID";
static NSString * const kTDServerUrl  = @"YOUR_THINKINGDATA_SERVER_URL";

static NSString * const kAFDevKey     = @"123456";
static NSString * const kAFAppleAppId = @"123456";   // 纯数字，不要带 "id"
/// ======================================================


static NSString * const kASDidReportAFInitEventKey = @"as_did_report_af_init_event";

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

@interface AppDelegate () <AppsFlyerLibDelegate>
@property (nonatomic, assign) BOOL as_attFinished;     // ATT 流程是否已结束（回调触发即算结束）
@property (nonatomic, assign) BOOL as_attRequested;    // 防止重复请求 ATT
@property (nonatomic, assign) BOOL as_afStarted;       // 防止重复 start AppsFlyer
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    ASLog(@"App", @"应用启动：didFinishLaunching 开始");

    // Firebase
     ASLog(@"Firebase", @"初始化");
//     [FIRApp configure];

    // ThinkingData：主线程初始化
    if ([NSThread isMainThread]) {
        [self setupThinkingData];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setupThinkingData];
        });
    }

    // 配置AppsFlyer参数
    [self setupAppsFlyer];

    // Scene 架构下：App 变为 active 时再尝试一次
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(as_onDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    ASLog(@"Paywall", @"PaywallPresenter 启动开始");
    [[PaywallPresenter shared] start];
    ASLog(@"Paywall", @"PaywallPresenter 启动结束");

    ASLog(@"App", @"应用启动：didFinishLaunching 结束");
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

// 兼容非 Scene / 某些项目仍会走这里
- (void)applicationDidBecomeActive:(UIApplication *)application {
    ASLog(@"App", @"applicationDidBecomeActive 回调");
    [self tryStartAppsFlyerIfPossible];
}

#pragma mark - ATT

// ATT权限请求（尽量只请求一次）
- (void)requestATTWhenNoModal {

    if (self.as_attRequested) return;
    self.as_attRequested = YES;

    ASLog(@"ATT", @"请求开始：准备弹出/查询 ATT 授权状态");

    [ASTrackingPermission requestIfNeededWithDelay:0.0 completion:^(NSInteger status) {

        // 这里回调线程不确定，统一切主线程
        dispatch_async(dispatch_get_main_queue(), ^{
            ASLog(@"ATT", [NSString stringWithFormat:@"请求结束：状态=%@（%ld）",
                           ASATTStatusText(status), (long)status]);

            // 只要回调触发，就视为 ATT 流程结束（包含 NotDetermined）
            self.as_attFinished = YES;

            // ATT 回来了就再试一次启动 AppsFlyer
            [self tryStartAppsFlyerIfPossible];
        });
    }];
}

#pragma mark - SDK setup

- (void)setupThinkingData {

    ASLog(@"数数(ThinkingData)", @"初始化开始");

    // 参数检查：直接把“失败原因”打印出来（否则你只看到 -1002 很难定位）
    if (ASIsPlaceholder(kTDAppId) || ASIsBlank(kTDAppId)) {
        ASLog(@"数数(ThinkingData)", @"初始化失败：AppId 还是占位符（请替换 kTDAppId）");
        return;
    }
    if (!ASIsValidHttpUrl(kTDServerUrl) || ASIsPlaceholder(kTDServerUrl)) {
        ASLog(@"数数(ThinkingData)", @"初始化失败：ServerUrl 非法或是占位符（必须是 http/https 完整 URL，例如 https://xxx）");
        return;
    }

    // 初始化
    [TDAnalytics enableLog:YES]; // 建议放前面，便于看到更完整日志
    [TDAnalytics startAnalyticsWithAppId:kTDAppId serverUrl:kTDServerUrl];

    // distinctId（deviceId）
    NSString *deviceId = [TDAnalytics getDeviceId];
    if (deviceId.length > 0) {
        [TDAnalytics setDistinctId:deviceId];
        ASLog(@"数数(ThinkingData)", [NSString stringWithFormat:@"设置 distinctId 成功：%@", deviceId]);
    } else {
        ASLog(@"数数(ThinkingData)", @"设置 distinctId 失败：deviceId 为空");
    }

    // 自动采集：安装、启动、关闭
    [TDAnalytics enableAutoTrack:(TDAutoTrackEventTypeAppInstall
                                  | TDAutoTrackEventTypeAppStart
                                  | TDAutoTrackEventTypeAppEnd)];

    // 开启与 AppsFlyer 的第三方数据共享（要在 AppsFlyer start 之前调用）
    [TDAnalytics enableThirdPartySharing:TDThirdPartyTypeAppsFlyer];

    ASLog(@"数数(ThinkingData)", @"初始化结束：本地初始化已完成（网络是否可达看后续 sync 请求）");
}

- (void)setupAppsFlyer {

    ASLog(@"AppsFlyer", @"初始化开始（配置参数阶段，不会 start）");

    if (ASIsPlaceholder(kAFDevKey) || ASIsBlank(kAFDevKey)) {
        ASLog(@"AppsFlyer", @"初始化失败：DevKey 还是占位/为空（请替换 kAFDevKey）");
        return;
    }
    if (ASIsPlaceholder(kAFAppleAppId) || ASIsBlank(kAFAppleAppId)) {
        ASLog(@"AppsFlyer", @"初始化失败：AppleAppId 还是占位/为空（请替换 kAFAppleAppId，纯数字）");
        return;
    }

    AppsFlyerLib *af = [AppsFlyerLib shared];
    af.appsFlyerDevKey = kAFDevKey;
    af.appleAppID = kAFAppleAppId;
    af.delegate = self;

#if DEBUG
    af.isDebug = YES;
    ASLog(@"AppsFlyer", @"调试模式：已开启 isDebug=YES（仅开发环境使用）");
#endif

    // 等待 ATT：让 SDK 内部在一定时间内等待 ATT 状态
    [af waitForATTUserAuthorizationWithTimeoutInterval:120];
    ASLog(@"AppsFlyer", @"初始化结束：参数已配置 + 已设置 waitForATT(120s)");
}

#pragma mark - AppsFlyer start (after ATT)

- (void)tryStartAppsFlyerIfPossible {

    // 强制主线程（避免你之前的 Main Thread Checker：UI API called on a background thread）
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self tryStartAppsFlyerIfPossible];
        });
        return;
    }

    // 已经 start 过就不再重复
    if (self.as_afStarted) return;

    // ATT 未结束：不启动
    if (!self.as_attFinished) {
        ASLog(@"AppsFlyer", @"启动中止：ATT 尚未结束");
        return;
    }

    // 只在 active 状态启动更稳
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    if (state != UIApplicationStateActive) {
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"启动中止：应用非激活态（state=%ld）", (long)state]);
        return;
    }

    ASLog(@"AppsFlyer", @"启动开始：准备设置 customerUserID 并调用 start");

    // 1) 取数数 distinctId（用作 AppsFlyer customerUserID）
    NSString *distinctId = nil;
    @try { distinctId = [TDAnalytics getDistinctId]; } @catch (__unused NSException *e) {}

    if (distinctId.length > 0) {
        [AppsFlyerLib shared].customerUserID = distinctId;
        ASLog(@"AppsFlyer", [NSString stringWithFormat:@"customerUserID 设置成功：%@", distinctId]);
    } else {
        ASLog(@"AppsFlyer", @"customerUserID 未设置：distinctId 为空");
    }

    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"关键参数：DevKey=%@ AppleAppId=%@",
                         kAFDevKey, kAFAppleAppId]);

    // 2) 启动 AppsFlyer
    [[AppsFlyerLib shared] start];
    self.as_afStarted = YES;

    ASLog(@"AppsFlyer", @"启动结束：start 已调用（是否归因成功看 conversion 回调）");

    // 3) 启动后：用数数只打一次“AF 已初始化”事件（用于排查与校验）
    BOOL didReport = [[NSUserDefaults standardUserDefaults] boolForKey:kASDidReportAFInitEventKey];
    if (!didReport) {
        NSDictionary *properties = @{@"step": @"c_af_init"};
        [TDAnalytics track:@"Appsflyer_client" properties:properties];
        ASLog(@"数数(ThinkingData)", @"事件上报：Appsflyer_client step=c_af_init（只打一次）");

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kASDidReportAFInitEventKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

#pragma mark - AppsFlyerLibDelegate（用回调判定“归因链路”成功/失败）

- (void)onConversionDataSuccess:(NSDictionary *)conversionInfo {
    ASLog(@"AppsFlyer", [NSString stringWithFormat:@"成功：%@", conversionInfo ?: @{}]);
    [TDAnalytics track:@"Appsflyer_client" properties:@{@"step": @"c_af_init"}];
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
