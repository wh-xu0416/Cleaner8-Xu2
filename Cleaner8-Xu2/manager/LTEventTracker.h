#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LTEventTracker : NSObject

+ (instancetype)shared;

/// 打印开关（Debug 可默认 YES）
@property (nonatomic, assign) BOOL enableLog;

/// 最基础：直接传 event + properties（字符串形式）
- (void)track:(NSString *)event properties:(nullable NSDictionary<NSString *, id> *)properties;

/// 带必填字段校验：requiredKeys 里任何 key 缺失/空字符串会 assert（enableAssert=YES 时）
- (void)track:(NSString *)event
   properties:(nullable NSDictionary<NSString *, id> *)properties
 requiredKeys:(nullable NSArray<NSString *> *)requiredKeys;

@end

NS_ASSUME_NONNULL_END
