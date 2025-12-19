#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>

@interface ContactsManager : NSObject

// 获取所有联系人
- (NSArray<CNContact *> *)fetchAllContacts;

// 删除选中联系人
- (BOOL)deleteContact:(CNContact *)contact;

// 备份联系人信息
- (void)backupContacts;

// 恢复联系人信息
- (void)restoreContacts;

// 计算联系人文件大小
- (uint64_t)calculateContactSize:(CNContact *)contact;

@end
