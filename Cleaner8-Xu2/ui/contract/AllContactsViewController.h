#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AllContactsViewController : UIViewController

typedef NS_ENUM(NSInteger, AllContactsMode) {
    AllContactsModeDelete = 0,  // 删除系统联系人
    AllContactsModeBackup = 1,  // 备份系统联系人
    AllContactsModeRestore = 2, // 恢复备份联系人（从备份文件）
    AllContactsModeIncomplete = 3,  // 不完整联系人（缺姓名/缺电话
};

- (instancetype)initWithMode:(AllContactsMode)mode backupId:(nullable NSString *)backupId;

@end

NS_ASSUME_NONNULL_END
