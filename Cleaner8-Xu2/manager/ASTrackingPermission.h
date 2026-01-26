#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^ASTrackingAuthCompletion)(NSInteger status);

@interface ASTrackingPermission : NSObject

/// 是否已经触发过系统弹窗
+ (BOOL)hasRequested;

/// 当前是否仍可触发系统弹窗（iOS14+ 且状态为 NotDetermined 且未请求过）
+ (BOOL)shouldRequest;

/// 发起请求（只会请求一次；不满足条件直接回调当前状态）
+ (void)requestIfNeededWithDelay:(NSTimeInterval)delay
                      completion:(nullable ASTrackingAuthCompletion)completion;

@end

NS_ASSUME_NONNULL_END
