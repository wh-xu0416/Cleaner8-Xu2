#import "ASABTestManager.h"
#import "FirebaseRemoteConfig.h"
#import <FirebaseCore/FirebaseCore.h>
#import <Network/Network.h>
#import "Cleaner8_Xu2-Swift.h"

#define kABKeyPaidRate (AppConstants.abKeyPaidRateRate)
#define kABKeySetRate  (AppConstants.abKeySetRateRate)
#define kABDefaultOpen (AppConstants.abDefaultClose)

static NSString * const kASABCacheFlagKey      = @"as_abtest_cached";
static NSString * const kASABCacheDictKey      = @"as_abtest_cached_dict";
static NSString * const kASABCacheSourceDictKey= @"as_abtest_cached_source_dict";
static NSString * const kASABCacheTimeKey      = @"as_abtest_cached_time";

static inline NSString *ASABNormalize(NSString * _Nullable v) {
    if (v.length == 0) return kABDefaultOpen;
    NSString *lv = v.lowercaseString;
    if ([lv isEqualToString:kABDefaultOpen] || [lv isEqualToString:@"close"]) return lv;
    return kABDefaultOpen;
}

static inline NSString *ASABSourceString(FIRRemoteConfigSource source) {
    switch (source) {
        case FIRRemoteConfigSourceRemote:  return @"remote";
        case FIRRemoteConfigSourceDefault: return @"default";
        case FIRRemoteConfigSourceStatic:  return @"static";
        default:                           return @"unknown";
    }
}

static inline void ASABLog(NSString *msg) {
    NSLog(@"【ABTest】%@", msg ?: @"");
}

@interface ASABTestManager ()
@property (nonatomic, strong) FIRRemoteConfig *remoteConfig;
@property (nonatomic, strong) nw_path_monitor_t monitor;
@property (nonatomic, assign) BOOL isFetching;
@end

@implementation ASABTestManager

+ (instancetype)shared {
    static ASABTestManager *m;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        m = [ASABTestManager new];
    });
    return m;
}

- (void)startIfNeeded {
    if (![FIRApp defaultApp]) {
        ASABLog(@"Firebase 未配置（[FIRApp defaultApp] 为空），跳过 ABTest 启动");
        return;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kASABCacheFlagKey]) {
        ASABLog(@"本地已缓存 AB 结果，跳过远程拉取");
        return;
    }

    self.remoteConfig = [FIRRemoteConfig remoteConfig];

    FIRRemoteConfigSettings *settings = [[FIRRemoteConfigSettings alloc] init];
    settings.minimumFetchInterval = 0;
    self.remoteConfig.configSettings = settings;

    NSDictionary *defaults = @{
        kABKeyPaidRate : kABDefaultOpen,
        kABKeySetRate  : kABDefaultOpen,
    };

    [self.remoteConfig setDefaults:defaults];

    ASABLog(@"开始监听网络：首次联网时拉取 Remote Config 并缓存一次");

    self.monitor = nw_path_monitor_create();
    dispatch_queue_t q = dispatch_queue_create("as.abtest.nwpath", DISPATCH_QUEUE_SERIAL);

    __weak typeof(self) weakSelf = self;
    nw_path_monitor_set_update_handler(self.monitor, ^(nw_path_t  _Nonnull path) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if ([[NSUserDefaults standardUserDefaults] boolForKey:kASABCacheFlagKey]) {
            [self stopMonitorIfNeeded];
            return;
        }

        if (nw_path_get_status(path) == nw_path_status_satisfied) {
            [self fetchOnceAndCache];
        } else {
            ASABLog(@"网络不可用，等待首次联网...");
        }
    });

    nw_path_monitor_set_queue(self.monitor, q);
    nw_path_monitor_start(self.monitor);
}

- (void)fetchOnceAndCache {
    if (self.isFetching) return;
    self.isFetching = YES;

    ASABLog(@"网络已可用，开始 fetch Remote Config...");

    __weak typeof(self) weakSelf = self;
    [self.remoteConfig fetchWithCompletionHandler:^(FIRRemoteConfigFetchStatus status, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (status != FIRRemoteConfigFetchStatusSuccess || error) {
            self.isFetching = NO;
            ASABLog([NSString stringWithFormat:@"fetch 失败：status=%ld error=%@",
                     (long)status, error.localizedDescription ?: @""]);
            return; // 不缓存，后续还能再试
        }

        ASABLog(@"fetch 成功，开始 activate...");

        [self.remoteConfig activateWithCompletion:^(BOOL changed, NSError * _Nullable error) {
            if (error) {
                self.isFetching = NO;
                ASABLog([NSString stringWithFormat:@"activate 失败：%@", error.localizedDescription ?: @""]);
                return;
            }

            FIRRemoteConfigValue *paidV = [self.remoteConfig configValueForKey:kABKeyPaidRate];
            FIRRemoteConfigValue *setV  = [self.remoteConfig configValueForKey:kABKeySetRate];

            NSString *paid = ASABNormalize(paidV.stringValue);
            NSString *set  = ASABNormalize(setV.stringValue);

            NSDictionary *valueDict = @{
                kABKeyPaidRate : paid,
                kABKeySetRate  : set,
            };
            NSDictionary *sourceDict = @{
                kABKeyPaidRate : ASABSourceString(paidV.source),
                kABKeySetRate  : ASABSourceString(setV.source),
            };

            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            [ud setBool:YES forKey:kASABCacheFlagKey];
            [ud setObject:valueDict forKey:kASABCacheDictKey];
            [ud setObject:sourceDict forKey:kASABCacheSourceDictKey];
            [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kASABCacheTimeKey];

            ASABLog([NSString stringWithFormat:@"已缓存 AB 结果：value=%@ source=%@", valueDict, sourceDict]);

            [self stopMonitorIfNeeded];
            self.isFetching = NO;
        }];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ABTestStateChanged" object:nil];
    }];
}

- (void)stopMonitorIfNeeded {
    if (self.monitor) {
        ASABLog(@"AB 已缓存，停止网络监听");
        nw_path_monitor_cancel(self.monitor);
        self.monitor = nil;
    }
}

#pragma mark - Read cache (only)

- (NSDictionary *)cachedValueDict {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kASABCacheDictKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

- (NSDictionary *)cachedSourceDict {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kASABCacheSourceDictKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

- (NSString *)stringForKey:(NSString *)key {
    NSString *v = [self cachedValueDict][key];
    if (![v isKindOfClass:NSString.class]) return kABDefaultOpen;
    return ASABNormalize(v);
}

- (BOOL)isOpenForKey:(NSString *)key {
    return [[self stringForKey:key] isEqualToString:@"open"];
}

- (BOOL)isPaidRateOpen { return [self isOpenForKey:kABKeyPaidRate]; }
- (BOOL)isSetRateOpen  { return [self isOpenForKey:kABKeySetRate];  }

- (BOOL)isRemoteValueForKey:(NSString *)key {
    NSString *src = [self cachedSourceDict][key];
    if (![src isKindOfClass:NSString.class]) return NO;
    return [src isEqualToString:@"remote"];
}

@end
