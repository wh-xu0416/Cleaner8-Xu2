#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASABTestManager : NSObject

+ (instancetype)shared;

- (void)startIfNeeded;

- (NSString *)stringForKey:(NSString *)key;
- (BOOL)isOpenForKey:(NSString *)key;

- (BOOL)isPaidRateOpen; // paid_rate_rate
- (BOOL)isSetRateOpen;  // set_rate_rate

// 周SKU AB测试：返回 "default" / "trial899" / "trial999"
- (NSString *)weeklySkuValue;

// 栏门页面调用：尝试锁定周SKU值（如果AB测试已获取且本地未锁定）
- (void)tryLockWeeklySkuIfNeeded;

// 该 key 当前缓存值是否来自 Remote
// 没有缓存/默认值/静态值 -> NO
- (BOOL)isRemoteValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
