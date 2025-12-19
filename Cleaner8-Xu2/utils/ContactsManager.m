#import "ContactsManager.h"

@implementation ContactsManager

// 获取所有联系人
- (NSArray<CNContact *> *)fetchAllContacts {
    NSError *error = nil;
    CNContactStore *contactStore = [[CNContactStore alloc] init];
    NSArray *keysToFetch = @[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactIdentifierKey];

    CNContactFetchRequest *fetchRequest = [[CNContactFetchRequest alloc] initWithKeysToFetch:keysToFetch];
    NSMutableArray<CNContact *> *contacts = [NSMutableArray array];
    
    [contactStore enumerateContactsWithFetchRequest:fetchRequest error:&error usingBlock:^(CNContact * _Nonnull contact, BOOL * _Nonnull stop) {
        [contacts addObject:contact];
    }];
    
    if (error) {
        NSLog(@"Error fetching contacts: %@", error);
    }
    
    return contacts;
}

// 删除选中的联系人
- (BOOL)deleteContact:(CNContact *)contact {
    NSError *error = nil;
    CNContactStore *contactStore = [[CNContactStore alloc] init];
    CNMutableContact *mutableContact = [contact mutableCopy];
    CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
    [saveRequest deleteContact:mutableContact];
    [contactStore executeSaveRequest:saveRequest error:&error];
    
    return (error == nil);
}

// 备份联系人信息
- (void)backupContacts {
    NSArray<CNContact *> *contacts = [self fetchAllContacts];
    NSData *contactData = [NSKeyedArchiver archivedDataWithRootObject:contacts];
    
    NSString *backupPath = [self backupFilePath];
    [contactData writeToFile:backupPath atomically:YES];
    
    NSLog(@"Backup completed. Backup path: %@", backupPath);
}

// 恢复联系人信息
- (void)restoreContacts {
    NSString *backupPath = [self backupFilePath];
    NSData *contactData = [NSData dataWithContentsOfFile:backupPath];
    
    if (contactData) {
        NSArray<CNContact *> *contacts = [NSKeyedUnarchiver unarchiveObjectWithData:contactData];
        CNContactStore *contactStore = [[CNContactStore alloc] init];
        CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
        
        for (CNContact *contact in contacts) {
            CNMutableContact *mutableContact = [contact mutableCopy];
            [saveRequest addContact:mutableContact toContainerWithIdentifier:nil];
        }
        
        NSError *error = nil;
        [contactStore executeSaveRequest:saveRequest error:&error];
        
        if (error) {
            NSLog(@"Error restoring contacts: %@", error);
        } else {
            NSLog(@"Restore completed.");
        }
    } else {
        NSLog(@"No backup found.");
    }
}

// 获取备份路径
- (NSString *)backupFilePath {
    NSString *documentDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *backupPath = [documentDirectory stringByAppendingPathComponent:@"contacts_backup.dat"];
    return backupPath;
}
@end
