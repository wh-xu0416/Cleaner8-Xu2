#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CMDuplicateMode) {
    CMDuplicateModeName,          // 姓名重复
    CMDuplicateModePhone,         // 电话重复
    CMDuplicateModeNameOrPhone,   // 姓名或电话任一重复（并集）
    CMDuplicateModeAll            // 返回全部重复：分别返回姓名重复组 + 电话重复组
};

/// 重复联系人分组
@interface CMDuplicateGroup : NSObject
@property (nonatomic, copy) NSString *key;                 // 分组key（name或phone）
@property (nonatomic, assign) CMDuplicateMode by;          // 本组是按姓名还是按号码
@property (nonatomic, strong) NSArray<CNContact *> *items; // 组内联系人
@end

/// 备份元信息
@interface CMBackupInfo : NSObject
@property (nonatomic, copy) NSString *backupId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) NSUInteger count;
@end

typedef void(^CMVoidBlock)(NSError * _Nullable error);
typedef void(^CMContactsBlock)(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error);
typedef void(^CMBackupsBlock)(NSArray<CMBackupInfo *> * _Nullable backups, NSError * _Nullable error);
typedef void(^CMBackupContactsBlock)(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error);
typedef void(^CMDuplicatesBlock)(NSArray<CMDuplicateGroup *> * _Nullable groups,
                                 NSArray<CMDuplicateGroup *> * _Nullable nameGroups,
                                 NSArray<CMDuplicateGroup *> * _Nullable phoneGroups,
                                 NSError * _Nullable error);

@interface ContactsManager : NSObject

+ (instancetype)shared;

/// 权限（建议App启动时调用一次）
- (void)requestContactsAccess:(CMVoidBlock)completion;

/// 1 获取所有联系人
- (void)fetchAllContacts:(CMContactsBlock)completion;

/// 2 删除选中联系人（传 identifier 列表）
- (void)deleteContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                           completion:(CMVoidBlock)completion;

/// 3 备份选中联系人（传 identifier 列表，生成一个备份）
- (void)backupContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                           backupName:(NSString *)backupName
                           completion:(void(^)(NSString * _Nullable backupId, NSError * _Nullable error))completion;

/// 4 恢复选中已经备份的联系人（从某个备份里选择若干条恢复；传 vCard 对应的索引或 identifiers）
- (void)restoreContactsFromBackupId:(NSString *)backupId
               contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                          completion:(CMVoidBlock)completion;

// 智能恢复 通过电话/电子邮件匹配，合并到现有记录；否则添加新记录
- (void)restoreContactsSmartFromBackupId:(NSString *)backupId
                 contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                             completion:(CMVoidBlock)completion;

// 覆盖所有联系人
- (void)restoreContactsOverwriteAllFromBackupId:(NSString *)backupId
                        contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                                    completion:(CMVoidBlock)completion;

/// 5 获取重复联系人（姓名重复/电话重复/全部）
- (void)fetchDuplicateContactsWithMode:(CMDuplicateMode)mode
                            completion:(CMDuplicatesBlock)completion;

/// 6 合并选中的重复联系人（传要合并的一组 identifiers，返回合并后新 contact 的 identifier）
- (void)mergeContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                    preferredPrimary:(nullable NSString *)primaryIdentifier
                          completion:(void(^)(NSString * _Nullable mergedIdentifier, NSError * _Nullable error))completion;

/// 7 获取备份列表 & 备份里的联系人列表
- (void)fetchBackupList:(CMBackupsBlock)completion;
- (void)fetchContactsInBackupId:(NSString *)backupId completion:(CMBackupContactsBlock)completion;

// 删除备份内的部分联系人（按备份内下标删除）
- (void)deleteContactsFromBackupId:(NSString *)backupId
             contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                         completion:(CMVoidBlock)completion;

@end

NS_ASSUME_NONNULL_END
