#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ResultViewController : UIViewController

/// deletedCount: 删除数量（Photos/Videos 自行传）
/// freedBytes: 释放空间 bytes
- (instancetype)initWithDeletedCount:(NSUInteger)deletedCount
                           freedBytes:(uint64_t)freedBytes;

@end

NS_ASSUME_NONNULL_END
