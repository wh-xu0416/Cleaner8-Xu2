#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASABTestManager : NSObject

+ (instancetype)shared;

- (void)startIfNeeded;

- (NSString *)stringForKey:(NSString *)key;
- (BOOL)isOpenForKey:(NSString *)key;

- (BOOL)isPaidRateOpen; // paid_rate_rate
- (BOOL)isSetRateOpen;  // set_rate_rate

// 该 key 当前缓存值是否来自 Remote
// 没有缓存/默认值/静态值 -> NO
- (BOOL)isRemoteValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
