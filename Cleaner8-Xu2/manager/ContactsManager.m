#import "ContactsManager.h"
#import <Contacts/Contacts.h>

NSString * const CMBackupsDidChangeNotification = @"CMBackupsDidChangeNotification";

@implementation CMDuplicateGroup
@end

@implementation CMBackupInfo
@end

@implementation CMIncompleteGroup
@end

@interface ContactsManager ()
@property (nonatomic, strong) CNContactStore *store;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@end

@implementation ContactsManager

+ (instancetype)shared {
    static ContactsManager *m;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        m = [[ContactsManager alloc] init];
    });
    return m;
}

- (instancetype)init {
    if (self = [super init]) {
        _store = [[CNContactStore alloc] init];
        _workQueue = dispatch_queue_create("com.contacts.manager.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Permission

- (void)requestContactsAccess:(CMVoidBlock)completion {
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (status == CNAuthorizationStatusAuthorized) {
        if (completion) completion(nil);
        return;
    }
    if (status == CNAuthorizationStatusDenied || status == CNAuthorizationStatusRestricted) {
        if (completion) completion([NSError errorWithDomain:@"ContactsManager"
                                                      code:1
                                                  userInfo:@{NSLocalizedDescriptionKey:@"Contacts access denied/restricted"}]);
        return;
    }
    [self.store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!granted) {
                NSError *e = error ?: [NSError errorWithDomain:@"ContactsManager"
                                                         code:2
                                                     userInfo:@{NSLocalizedDescriptionKey:@"Contacts access not granted"}];
                if (completion) completion(e);
            } else {
                if (completion) completion(nil);
            }
        });
    }];
}

#pragma mark - Dashboard Counts (All / Incomplete / Duplicate / Backups)

- (NSArray<id<CNKeyDescriptor>> *)_keysForDashboardCounts {
    // 一次取齐：够算 incomplete + duplicate（name + phone）
    id<CNKeyDescriptor> nameKeys =
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName];

    return @[
        CNContactIdentifierKey,
        nameKeys,

        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactOrganizationNameKey,
        CNContactNicknameKey,

        CNContactPhoneNumbersKey
    ];
}

- (BOOL)_canReadContactsStatus:(CNAuthorizationStatus)st {
    if (st == CNAuthorizationStatusAuthorized) return YES;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
    if (@available(iOS 18.0, *)) {
        if (st == CNAuthorizationStatusLimited) return YES;
    }
#endif

    return NO;
}

- (void)fetchDashboardCounts:(CMDashboardCountsBlock)completion {

    dispatch_async(self.workQueue, ^{
        NSUInteger backupCount = 0;
        NSDictionary *idx = [self _readBackupIndex];
        NSArray *items = [idx[@"backups"] isKindOfClass:[NSArray class]] ? idx[@"backups"] : @[];
        if (items.count > 0) {
            backupCount = items.count;
        } else {
            backupCount = [self _scanBackupsFromDisk].count;
        }

        CNAuthorizationStatus st = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
        if (![self _canReadContactsStatus:st]) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                             code:990
                                         userInfo:@{NSLocalizedDescriptionKey:@"Contacts not readable"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(0, 0, 0, backupCount, e);
            });
            return;
        }

        NSError *error = nil;
        __block NSUInteger allCount = 0;
        __block NSUInteger incompleteCount = 0;

        NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *nameMap = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *phoneMap = [NSMutableDictionary dictionary];

        CNContactFetchRequest *req =
            [[CNContactFetchRequest alloc] initWithKeysToFetch:[self _keysForDashboardCounts]];
        req.unifyResults = YES;

        BOOL ok = [self.store enumerateContactsWithFetchRequest:req
                                                         error:&error
                                                    usingBlock:^(CNContact * _Nonnull c, BOOL * _Nonnull stop) {
            @autoreleasepool {
                allCount++;

                BOOL n = [self _isNameMissing:c];
                BOOL p = [self _isPhoneMissing:c];
                if (n || p) incompleteCount++;

                NSString *cid = c.identifier ?: @"";
                if (cid.length == 0) return;

                NSString *nk = [self _normalizeName:c];
                if (nk.length > 0) {
                    NSMutableSet *set = nameMap[nk] ?: (nameMap[nk] = [NSMutableSet set]);
                    [set addObject:cid];
                }

                if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
                    for (CNLabeledValue<CNPhoneNumber *> *lv in (c.phoneNumbers ?: @[])) {
                        NSString *pk = [self _normalizePhone:lv.value.stringValue];
                        if (pk.length == 0) continue;

                        NSMutableSet *set = phoneMap[pk] ?: (phoneMap[pk] = [NSMutableSet set]);
                        [set addObject:cid];
                    }
                }
            }
        }];

        if (!ok && !error) {
            error = [NSError errorWithDomain:@"ContactsManager"
                                        code:901
                                    userInfo:@{NSLocalizedDescriptionKey:@"Enumerate contacts failed"}];
        }

        NSMutableSet<NSString *> *dupIds = [NSMutableSet set];
        [nameMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableSet<NSString *> *obj, BOOL *stop) {
            if (obj.count >= 2) [dupIds unionSet:obj];
        }];
        [phoneMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableSet<NSString *> *obj, BOOL *stop) {
            if (obj.count >= 2) [dupIds unionSet:obj];
        }];

        NSUInteger duplicateCount = dupIds.count;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(allCount, incompleteCount, duplicateCount, backupCount, error);
        });
    });
}

#pragma mark - Keys

// 列表展示：只要名字 + 电话就够
- (NSArray<id<CNKeyDescriptor>> *)keysForList {
    id<CNKeyDescriptor> nameKeys =
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName];

    return @[
        CNContactIdentifierKey,
        nameKeys,
        CNContactPhoneNumbersKey
    ];
}

// 不完整检测：要用到姓名字段 + 电话字段
- (NSArray<id<CNKeyDescriptor>> *)keysForIncompleteDetect {
    id<CNKeyDescriptor> nameKeys =
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName];

    return @[
        CNContactIdentifierKey,
        nameKeys,
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactOrganizationNameKey,
        CNContactNicknameKey,
        CNContactPhoneNumbersKey
    ];
}

// 重复检测：名字 + 电话
- (NSArray<id<CNKeyDescriptor>> *)keysForDuplicateDetect {
    return [self keysForList];
}

// 合并：需要合并哪些字段，就请求哪些字段（⚠️不要请求 Note）
- (NSArray<id<CNKeyDescriptor>> *)keysForMerge {
    return @[
        CNContactIdentifierKey,
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName],
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey,
        CNContactPostalAddressesKey,
        CNContactUrlAddressesKey,
        CNContactBirthdayKey,
        CNContactNonGregorianBirthdayKey,
        CNContactImageDataKey,
        CNContactOrganizationNameKey,
        CNContactDepartmentNameKey,
        CNContactJobTitleKey
    ];
}

#pragma mark - 1 Fetch All

- (void)fetchAllContacts:(CMContactsBlock)completion {
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSMutableArray<CNContact *> *result = [NSMutableArray array];

        CNContactFetchRequest *req =
        [[CNContactFetchRequest alloc] initWithKeysToFetch:[self keysForList]];

        BOOL ok = [self.store enumerateContactsWithFetchRequest:req
                                                         error:&error
                                                    usingBlock:^(CNContact * _Nonnull contact, BOOL * _Nonnull stop) {
            [result addObject:contact];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                if (completion) completion(nil, error);
            } else {
                if (completion) completion(result, nil);
            }
        });
    });
}


#pragma mark - Helpers: fetch by identifiers

- (NSArray<CNContact *> *)_fetchContactsByIdentifiers:(NSArray<NSString *> *)identifiers error:(NSError **)error {
    if (identifiers.count == 0) return @[];
    NSPredicate *pred = [CNContact predicateForContactsWithIdentifiers:identifiers];
    return [self.store unifiedContactsMatchingPredicate:pred
                                             keysToFetch:[self keysForMerge]
                                                   error:error] ?: @[];
}

#pragma mark - 2 Delete

- (void)deleteContactsWithIdentifiers:(NSArray<NSString *> *)identifiers completion:(CMVoidBlock)completion {
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSArray<CNContact *> *contacts = [self _fetchContactsByIdentifiers:identifiers error:&error];
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }

        CNSaveRequest *req = [[CNSaveRequest alloc] init];
        for (CNContact *c in contacts) {
            CNMutableContact *mc = [c mutableCopy];
            [req deleteContact:mc];
        }

        BOOL ok = [self.store executeSaveRequest:req error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) { if (completion) completion(error); }
            else { if (completion) completion(nil); }
        });
    });
}

#pragma mark - Backup Storage (vCard)

- (NSURL *)_backupRootURL {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    return [docs URLByAppendingPathComponent:@"CMBackups" isDirectory:YES];
}

- (NSURL *)_backupIndexURL {
    return [[self _backupRootURL] URLByAppendingPathComponent:@"index.json"];
}

- (void)_ensureBackupDir {
    NSURL *root = [self _backupRootURL];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:root.path isDirectory:&isDir] || !isDir) {
        [[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    }
    // index.json 不存在也没关系，读的时候兼容
}

- (NSDictionary *)_readBackupIndex {
    [self _ensureBackupDir];

    NSURL *idxURL = [self _backupIndexURL];
    NSData *data = [NSData dataWithContentsOfURL:idxURL];

    if (!data || data.length == 0) {
        return @{@"backups": @[]};
    }

    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) {
        return @{@"backups": @[]};
    }

    id backups = ((NSDictionary *)obj)[@"backups"];
    if (![backups isKindOfClass:[NSArray class]]) {
        return @{@"backups": @[]};
    }

    return (NSDictionary *)obj;
}


- (BOOL)_writeBackupIndex:(NSDictionary *)index error:(NSError **)error {
    [self _ensureBackupDir];

    NSURL *idxURL = [self _backupIndexURL];

    NSData *data = [NSJSONSerialization dataWithJSONObject:index
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;

    BOOL ok = [data writeToURL:idxURL options:NSDataWritingAtomic error:error];

    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:idxURL.path];
    NSDictionary *attr = exists ? [[NSFileManager defaultManager] attributesOfItemAtPath:idxURL.path error:nil] : nil;
    NSNumber *size = attr[NSFileSize];

    NSLog(@"[CM][index] write ok=%d path=%@ exists=%d size=%@", ok, idxURL.path, exists, size);

    return ok && exists && size.longLongValue > 0;
}


- (NSURL *)_backupFileURL:(NSString *)backupId {
    return [[self _backupRootURL] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", backupId]];
}

#pragma mark - 3 Backup Selected

- (void)backupContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                           backupName:(NSString *)backupName
                           completion:(void(^)(NSString * _Nullable backupId, NSError * _Nullable error))completion {

    dispatch_async(self.workQueue, ^{
        // 0) 参数校验
        if (identifiers.count == 0) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                             code:300
                                         userInfo:@{NSLocalizedDescriptionKey:@"No contacts selected"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        // 1) 拉取联系人
        NSError *error = nil;
        NSArray<CNContact *> *contacts = [self _fetchContactsByIdentifiersForVCard:identifiers error:&error];
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
            return;
        }
        if (contacts.count == 0) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                             code:301
                                         userInfo:@{NSLocalizedDescriptionKey:@"Fetched 0 contacts by identifiers"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        // 2) vCard 序列化
        NSData *vcard = [CNContactVCardSerialization dataWithContacts:contacts error:&error];
        if (!vcard || error) {
            NSError *e = error ?: [NSError errorWithDomain:@"ContactsManager"
                                                     code:302
                                                 userInfo:@{NSLocalizedDescriptionKey:@"vCard serialization failed"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        // 3) 生成备份 JSON
        NSString *backupId = [[NSUUID UUID] UUIDString];
        NSDate *now = [NSDate date];

        NSDictionary *backupJson = @{
            @"backupId": backupId,
            @"name": backupName ?: @"Backup",
            @"date": @((long long)(now.timeIntervalSince1970 * 1000)),
            @"count": @(contacts.count),
            @"vcardBase64": [vcard base64EncodedStringWithOptions:0]
        };

        // 4) 确保目录存在
        [self _ensureBackupDir];

        NSLog(@"[CM][backup] bundleId=%@", [[NSBundle mainBundle] bundleIdentifier]);
        NSLog(@"[CM][backup] root=%@", [self _backupRootURL].path);

        // 5) 写备份文件（先写文件，后写 index）
        NSURL *fileURL = [self _backupFileURL:backupId];

        NSData *data = [NSJSONSerialization dataWithJSONObject:backupJson
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
        if (!data || error) {
            NSError *e = error ?: [NSError errorWithDomain:@"ContactsManager"
                                                     code:303
                                                 userInfo:@{NSLocalizedDescriptionKey:@"Backup JSON encode failed"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        BOOL ok = [data writeToURL:fileURL options:NSDataWritingAtomic error:&error];

        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path];
        NSDictionary *attr = exists ? [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] : nil;
        NSNumber *size = attr[NSFileSize];

        NSLog(@"[CM][backup] write file ok=%d path=%@ exists=%d size=%@ err=%@",
              ok, fileURL.path, exists, size, error);

        // ✅ 写完立即自检：只要文件不存在 / size=0 就算失败
        if (!ok || !exists || size.longLongValue <= 0) {
            NSError *e = error ?: [NSError errorWithDomain:@"ContactsManager"
                                                     code:304
                                                 userInfo:@{NSLocalizedDescriptionKey:@"Backup file not created or size=0"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        // 6) 更新 index.json
        NSDictionary *idx = [self _readBackupIndex];
        NSMutableArray *arr = [idx[@"backups"] mutableCopy];
        if (![arr isKindOfClass:[NSMutableArray class]]) arr = [NSMutableArray array];

        [arr insertObject:@{
            @"backupId": backupId,
            @"name": backupName ?: @"Backup",
            @"date": @((long long)(now.timeIntervalSince1970 * 1000)),
            @"count": @(contacts.count)
        } atIndex:0];

        NSMutableDictionary *newIdx = [idx mutableCopy];
        if (![newIdx isKindOfClass:[NSMutableDictionary class]]) newIdx = [NSMutableDictionary dictionary];
        newIdx[@"backups"] = arr;

        NSError *idxErr = nil;
        BOOL idxOk = [self _writeBackupIndex:newIdx error:&idxErr];

        BOOL idxExists = [[NSFileManager defaultManager] fileExistsAtPath:[self _backupIndexURL].path];
        NSDictionary *idxAttr = idxExists ? [[NSFileManager defaultManager] attributesOfItemAtPath:[self _backupIndexURL].path error:nil] : nil;

        NSLog(@"[CM][index] write ok=%d path=%@ exists=%d size=%@ err=%@",
              idxOk,
              [self _backupIndexURL].path,
              idxExists,
              idxAttr[NSFileSize],
              idxErr);

        NSError *dirErr = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self _backupRootURL].path error:&dirErr];
        NSLog(@"[CM][backup] dir files=%@ err=%@", files, dirErr);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:CMBackupsDidChangeNotification object:nil];
            if (!idxOk) {
                if (completion) completion(nil, idxErr);
            } else {
                if (completion) completion(backupId, nil);
            }
        });

    });
}


- (NSArray<id<CNKeyDescriptor>> *)keysForVCard {
    // ✅ vCard 序列化必须的 keys
    return @[
        [CNContactVCardSerialization descriptorForRequiredKeys]
    ];
}

- (NSArray<CNContact *> *)_fetchContactsByIdentifiersForVCard:(NSArray<NSString *> *)identifiers
                                                       error:(NSError **)error {
    if (identifiers.count == 0) return @[];
    NSPredicate *pred = [CNContact predicateForContactsWithIdentifiers:identifiers];

    return [self.store unifiedContactsMatchingPredicate:pred
                                             keysToFetch:[self keysForVCard]
                                                   error:error] ?: @[];
}


#pragma mark - 7 Backup List

- (void)fetchBackupList:(CMBackupsBlock)completion {
    dispatch_async(self.workQueue, ^{
        [self _ensureBackupDir];

        NSLog(@"[CM][list] bundleId=%@", [[NSBundle mainBundle] bundleIdentifier]);
        NSLog(@"[CM][list] root=%@", [self _backupRootURL].path);
        NSLog(@"[CM][list] index=%@", [self _backupIndexURL].path);

        NSError *dirErr = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self _backupRootURL].path error:&dirErr];
        NSLog(@"[CM][list] files=%@ err=%@", files, dirErr);

        NSDictionary *idx = [self _readBackupIndex];
        NSArray *items = [idx[@"backups"] isKindOfClass:[NSArray class]] ? idx[@"backups"] : @[];

        // index 有数据：按 index 走
        if (items.count > 0) {
            NSMutableArray<CMBackupInfo *> *out = [NSMutableArray array];
            for (NSDictionary *d in items) {
                if (![d isKindOfClass:[NSDictionary class]]) continue;
                CMBackupInfo *info = [CMBackupInfo new];
                info.backupId = d[@"backupId"] ?: @"";
                info.name = d[@"name"] ?: @"";
                long long ms = [d[@"date"] longLongValue];
                info.date = [NSDate dateWithTimeIntervalSince1970:(ms / 1000.0)];
                info.count = (NSUInteger)[d[@"count"] integerValue];
                [out addObject:info];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(out, nil);
            });
            return;
        }

        NSArray<CMBackupInfo *> *scanned = [self _scanBackupsFromDisk];

        if (scanned.count > 0) {
            NSMutableArray *arr = [NSMutableArray array];
            for (CMBackupInfo *info in scanned) {
                long long ms = (long long)(info.date.timeIntervalSince1970 * 1000);
                [arr addObject:@{
                    @"backupId": info.backupId ?: @"",
                    @"name": info.name ?: @"",
                    @"date": @(ms),
                    @"count": @(info.count)
                }];
            }
            [self _writeBackupIndex:@{@"backups": arr} error:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(scanned, nil);
        });
    });
}


- (NSArray<CMBackupInfo *> *)_scanBackupsFromDisk {
    [self _ensureBackupDir];

    NSError *err = nil;
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self _backupRootURL]
                                                          includingPropertiesForKeys:nil
                                                                             options:0
                                                                               error:&err];
    NSLog(@"[CM][scan] urls=%@ err=%@", urls, err);

    if (err || urls.count == 0) return @[];

    NSMutableArray<CMBackupInfo *> *out = [NSMutableArray array];

    for (NSURL *u in urls) {
        if (![[u.pathExtension lowercaseString] isEqualToString:@"json"]) continue;
        if ([[u.lastPathComponent lowercaseString] isEqualToString:@"index.json"]) continue;

        NSData *data = [NSData dataWithContentsOfURL:u];
        if (!data || data.length == 0) {
            NSLog(@"[CM][scan] skip empty file=%@", u.path);
            continue;
        }

        NSError *e = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&e];
        if (e || ![json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[CM][scan] json parse fail file=%@ err=%@", u.path, e);
            continue;
        }

        NSString *bid = json[@"backupId"];
        NSNumber *msN = json[@"date"];
        NSNumber *cntN = json[@"count"];
        if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;

        CMBackupInfo *info = [CMBackupInfo new];
        info.backupId = bid;
        info.name = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : @"";
        long long ms = [msN longLongValue];
        info.date = [NSDate dateWithTimeIntervalSince1970:(ms / 1000.0)];
        info.count = (NSUInteger)[cntN integerValue];

        [out addObject:info];
    }

    [out sortUsingComparator:^NSComparisonResult(CMBackupInfo *a, CMBackupInfo *b) {
        return [b.date compare:a.date];
    }];

    NSLog(@"[CM][scan] found backups=%lu", (unsigned long)out.count);
    return out;
}


#pragma mark - 7 Contacts in Backup

- (void)fetchContactsInBackupId:(NSString *)backupId completion:(CMBackupContactsBlock)completion {
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:[self _backupFileURL:backupId]];
        if (!data) {
            error = [NSError errorWithDomain:@"ContactsManager" code:100 userInfo:@{NSLocalizedDescriptionKey:@"Backup not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!json || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
            return;
        }

        NSString *b64 = json[@"vcardBase64"];
        NSData *vcard = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
        if (!vcard) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager" code:101 userInfo:@{NSLocalizedDescriptionKey:@"Invalid vCard data"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }

        NSArray<CNContact *> *contacts = [CNContactVCardSerialization contactsWithData:vcard error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(contacts, error);
        });
    });
}

#pragma mark - 4 Restore Selected From Backup

- (void)restoreContactsFromBackupId:(NSString *)backupId
             contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                        completion:(CMVoidBlock)completion {
    // 先把备份里解析出来，然后根据 indices 选中，再逐个 addContact
    [self fetchContactsInBackupId:backupId completion:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error) {
        if (error || !contacts) { if (completion) completion(error); return; }

        dispatch_async(self.workQueue, ^{
            NSError *e = nil;
            NSMutableArray<CNContact *> *selected = [NSMutableArray array];

            if (indices.count == 0) {
                [selected addObjectsFromArray:contacts];
            } else {
                for (NSNumber *n in indices) {
                    NSInteger i = n.integerValue;
                    if (i >= 0 && i < (NSInteger)contacts.count) {
                        [selected addObject:contacts[i]];
                    }
                }
            }

            CNSaveRequest *req = [[CNSaveRequest alloc] init];
            for (CNContact *c in selected) {
                CNMutableContact *mc = [c mutableCopy];
                [req addContact:mc toContainerWithIdentifier:nil];
            }

            BOOL ok = [self.store executeSaveRequest:req error:&e];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) { if (completion) completion(e); }
                else { if (completion) completion(nil); }
            });
        });
    }];
}

#pragma mark - Normalization helpers

- (BOOL)_isNameMissing:(CNContact *)c {
    // 用系统全名格式化
    NSString *full = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
    if (full.length > 0) return NO;

    // 必须 isKeyAvailable，避免 “property not fetched” 崩溃
    if ([c isKeyAvailable:CNContactGivenNameKey] && c.givenName.length > 0) return NO;
    if ([c isKeyAvailable:CNContactFamilyNameKey] && c.familyName.length > 0) return NO;
    if ([c isKeyAvailable:CNContactMiddleNameKey] && c.middleName.length > 0) return NO;
    if ([c isKeyAvailable:CNContactNicknameKey] && c.nickname.length > 0) return NO;
    if ([c isKeyAvailable:CNContactOrganizationNameKey] && c.organizationName.length > 0) return NO;

    return YES;
}

- (BOOL)_isPhoneMissing:(CNContact *)c {
    if (![c isKeyAvailable:CNContactPhoneNumbersKey]) {
        // 没取到 key 时按缺失处理
        return YES;
    }
    return (c.phoneNumbers.count == 0);
}

- (NSString *)_normalizeName:(CNContact *)c {
    // 先用系统格式化全名
    NSString *full = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
    if (full.length == 0) {
        full = [NSString stringWithFormat:@"%@%@%@",
                c.familyName ?: @"",
                c.givenName ?: @"",
                c.organizationName ?: @""];
    }

    NSString *s = [[full stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];

    // 保留“任意语种的字母” + “数字”，去掉空格/标点
    NSMutableCharacterSet *keep = [NSMutableCharacterSet characterSetWithCharactersInString:@""];
    [keep formUnionWithCharacterSet:[NSCharacterSet letterCharacterSet]];        // 包含中文等 Unicode 字母
    [keep formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]]; // 数字
    NSCharacterSet *remove = [keep invertedSet];

    NSArray *parts = [s componentsSeparatedByCharactersInSet:remove];
    NSString *key = [parts componentsJoinedByString:@""];

    return key;
}

- (NSString *)_normalizePhone:(NSString *)raw {
    if (raw.length == 0) return @"";
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar ch = [raw characterAtIndex:i];
        if (ch >= '0' && ch <= '9') [digits appendFormat:@"%c", ch];
    }

    if (digits.length > 11) {
        return [digits substringFromIndex:digits.length - 11];
    }
    return digits;
}

#pragma mark - 5 Duplicate detection

- (void)fetchDuplicateContactsWithMode:(CMDuplicateMode)mode completion:(CMDuplicatesBlock)completion {
    [self fetchAllContacts:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error) {
        if (error || !contacts) { if (completion) completion(nil, nil, nil, error); return; }

        dispatch_async(self.workQueue, ^{
            NSMutableDictionary<NSString *, NSMutableArray<CNContact *> *> *nameMap  = [NSMutableDictionary dictionary];
            NSMutableDictionary<NSString *, NSMutableArray<CNContact *> *> *phoneMap = [NSMutableDictionary dictionary];

            for (CNContact *c in contacts) {
                NSString *nk = [self _normalizeName:c];
                if (nk.length > 0) {
                    if (!nameMap[nk]) nameMap[nk] = [NSMutableArray array];
                    [nameMap[nk] addObject:c];
                }

                if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
                    for (CNLabeledValue<CNPhoneNumber *> *lv in c.phoneNumbers) {
                        NSString *pk = [self _normalizePhone:lv.value.stringValue];
                        if (pk.length > 0) {
                            if (!phoneMap[pk]) phoneMap[pk] = [NSMutableArray array];
                            [phoneMap[pk] addObject:c];
                        }
                    }
                }
            }

            NSArray<CMDuplicateGroup *> *(^buildGroups)(NSDictionary<NSString *, NSMutableArray<CNContact *> *> *, CMDuplicateMode) =
            ^(NSDictionary<NSString *, NSMutableArray<CNContact *> *> *map, CMDuplicateMode byMode) {
                NSMutableArray<CMDuplicateGroup *> *groups = [NSMutableArray array];
                [map enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<CNContact *> *obj, BOOL *stop) {
                    NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:obj];
                    if (set.count >= 2) {
                        CMDuplicateGroup *g = [CMDuplicateGroup new];
                        g.key = key;
                        g.by = byMode;
                        g.items = set.array;
                        [groups addObject:g];
                    }
                }];
                return groups;
            };

            NSArray<CMDuplicateGroup *> *nameGroups = buildGroups(nameMap, CMDuplicateModeName);

            NSMutableSet<NSString *> *nameDupIDs = [NSMutableSet set];
            for (CMDuplicateGroup *g in nameGroups) {
                for (CNContact *c in g.items) {
                    if (c.identifier.length > 0) {
                        [nameDupIDs addObject:c.identifier];
                    }
                }
            }

            NSMutableDictionary<NSString *, NSMutableArray<CNContact *> *> *phoneMapFiltered = [NSMutableDictionary dictionary];
            [phoneMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<CNContact *> *obj, BOOL *stop) {
                NSMutableArray<CNContact *> *filtered = [NSMutableArray array];
                NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:obj];
                for (CNContact *c in set.array) {
                    if (c.identifier.length == 0) continue;
                    if (![nameDupIDs containsObject:c.identifier]) {
                        [filtered addObject:c];
                    }
                }
                if (filtered.count >= 2) {
                    phoneMapFiltered[key] = filtered;
                }
            }];

            NSArray<CMDuplicateGroup *> *phoneGroups = buildGroups(phoneMapFiltered, CMDuplicateModePhone);

            NSArray<CMDuplicateGroup *> *outGroups = nil;
            if (mode == CMDuplicateModeName) {
                outGroups = nameGroups;
            } else if (mode == CMDuplicateModePhone) {
                outGroups = phoneGroups;
            } else {
                outGroups = [nameGroups arrayByAddingObjectsFromArray:phoneGroups];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    if (mode == CMDuplicateModeAll) {
                        completion(outGroups, nameGroups, phoneGroups, nil);
                    } else {
                        completion(outGroups, nil, nil, nil);
                    }
                }
            });
        });
    }];
}

#pragma mark - 6 Merge contacts

- (void)mergeContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                    preferredPrimary:(nullable NSString *)primaryIdentifier
                          completion:(void(^)(NSString * _Nullable mergedIdentifier, NSError * _Nullable error))completion {

    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSArray<CNContact *> *contacts = [self _fetchContactsByIdentifiers:identifiers error:&error];
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); }); return; }
        if (contacts.count < 2) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager" code:200
                                         userInfo:@{NSLocalizedDescriptionKey:@"Need at least 2 contacts to merge"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, e); });
            return;
        }

        CNContact *primary = contacts.firstObject;
        if (primaryIdentifier.length > 0) {
            for (CNContact *c in contacts) {
                if ([c.identifier isEqualToString:primaryIdentifier]) { primary = c; break; }
            }
        }

        CNMutableContact *merged = [primary mutableCopy];

        NSMutableSet<NSString *> *phoneKeySet = [NSMutableSet set];

        NSMutableArray *phones = [NSMutableArray array];
        NSMutableArray *emails = [NSMutableArray array];
        NSMutableArray *addrs  = [NSMutableArray array];
        NSMutableArray *urls   = [NSMutableArray array];

        CNLabeledValue* (^CloneLV)(CNLabeledValue*) = ^CNLabeledValue* (CNLabeledValue *lv) {
            if (!lv) return nil;
            return [CNLabeledValue labeledValueWithLabel:lv.label value:lv.value];
        };

        for (CNContact *c in contacts) {
            // phones
            if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
                for (CNLabeledValue<CNPhoneNumber *> *lv in (c.phoneNumbers ?: @[])) {
                    NSString *p = lv.value.stringValue ?: @"";
                    if (p.length == 0) continue;

                    if ([phoneKeySet containsObject:p]) continue;
                    [phoneKeySet addObject:p];

                    CNLabeledValue *newLV = CloneLV(lv);
                    if (newLV) [phones addObject:newLV];
                }
            }

            // emails
            if ([c isKeyAvailable:CNContactEmailAddressesKey]) {
                for (CNLabeledValue<NSString *> *lv in (c.emailAddresses ?: @[])) {
                    CNLabeledValue *newLV = CloneLV(lv);
                    if (newLV) [emails addObject:newLV];
                }
            }

            // addresses
            if ([c isKeyAvailable:CNContactPostalAddressesKey]) {
                for (CNLabeledValue<CNPostalAddress *> *lv in (c.postalAddresses ?: @[])) {
                    CNLabeledValue *newLV = CloneLV(lv);
                    if (newLV) [addrs addObject:newLV];
                }
            }

            // urls
            if ([c isKeyAvailable:CNContactUrlAddressesKey]) {
                for (CNLabeledValue<NSString *> *lv in (c.urlAddresses ?: @[])) {
                    CNLabeledValue *newLV = CloneLV(lv);
                    if (newLV) [urls addObject:newLV];
                }
            }

            if (merged.organizationName.length == 0 && [c isKeyAvailable:CNContactOrganizationNameKey] && c.organizationName.length > 0) {
                merged.organizationName = c.organizationName;
            }
            if (merged.departmentName.length == 0 && [c isKeyAvailable:CNContactDepartmentNameKey] && c.departmentName.length > 0) {
                merged.departmentName = c.departmentName;
            }
            if (merged.jobTitle.length == 0 && [c isKeyAvailable:CNContactJobTitleKey] && c.jobTitle.length > 0) {
                merged.jobTitle = c.jobTitle;
            }
            if (!merged.imageData && [c isKeyAvailable:CNContactImageDataKey] && c.imageData) {
                merged.imageData = c.imageData;
            }
        }

        merged.phoneNumbers     = phones;
        merged.emailAddresses   = emails;
        merged.postalAddresses  = addrs;
        merged.urlAddresses     = urls;

        CNSaveRequest *req = [[CNSaveRequest alloc] init];

        // 更新 primary
        [req updateContact:merged];

        // 删除非 primary
        for (CNContact *c in contacts) {
            if ([c.identifier isEqualToString:primary.identifier]) continue;
            [req deleteContact:[c mutableCopy]];
        }

        BOOL ok = [self.store executeSaveRequest:req error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) completion(nil, error);
            else completion(primary.identifier, nil); // primary id 不变
        });
    });
}

- (void)deleteContactsFromBackupId:(NSString *)backupId
             contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                         completion:(CMVoidBlock)completion {

    dispatch_async(self.workQueue, ^{
        NSError *error = nil;

        // 读备份文件
        NSData *data = [NSData dataWithContentsOfURL:[self _backupFileURL:backupId]];
        if (!data) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager" code:120 userInfo:@{NSLocalizedDescriptionKey:@"Backup not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!json || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }

        NSString *b64 = json[@"vcardBase64"] ?: @"";
        NSData *vcard = [[NSData alloc] initWithBase64EncodedString:b64 options:0];

        NSArray<CNContact *> *contacts = @[];
        if (vcard.length > 0) {
            contacts = [CNContactVCardSerialization contactsWithData:vcard error:&error] ?: @[];
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
                return;
            }
        }

        if (indices.count == 0) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager" code:121 userInfo:@{NSLocalizedDescriptionKey:@"No indices to delete"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
            return;
        }

        // 生成要删除的 indexSet（过滤越界）
        NSMutableIndexSet *removeSet = [NSMutableIndexSet indexSet];
        for (NSNumber *n in indices) {
            NSInteger i = n.integerValue;
            if (i >= 0 && i < (NSInteger)contacts.count) [removeSet addIndex:(NSUInteger)i];
        }
        if (removeSet.count == 0) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager" code:122 userInfo:@{NSLocalizedDescriptionKey:@"Indices out of range"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
            return;
        }

        NSMutableArray<CNContact *> *mutable = [contacts mutableCopy];
        [mutable removeObjectsAtIndexes:removeSet];

        // 如果删空：直接删除这个备份文件 + 从 index.json 移除
        if (mutable.count == 0) {
            [[NSFileManager defaultManager] removeItemAtURL:[self _backupFileURL:backupId] error:nil];

            NSDictionary *idx = [self _readBackupIndex];
            NSMutableArray *arr = [idx[@"backups"] mutableCopy] ?: [NSMutableArray array];
            NSIndexSet *rm = [arr indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx2, BOOL *stop) {
                return [obj[@"backupId"] isEqualToString:backupId];
            }];
            if (rm.count > 0) [arr removeObjectsAtIndexes:rm];

            NSMutableDictionary *newIdx = [idx mutableCopy];
            newIdx[@"backups"] = arr;
            BOOL ok = [self _writeBackupIndex:newIdx error:&error];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) { if (completion) completion(error); }
                else {
                    [[NSNotificationCenter defaultCenter] postNotificationName:CMBackupsDidChangeNotification object:nil];
                    if (completion) completion(nil);
                }
            });
            return;
        }

        // 重新序列化 vCard
        NSData *newVcard = [CNContactVCardSerialization dataWithContacts:mutable error:&error];
        if (!newVcard || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }

        NSMutableDictionary *newJson = [json mutableCopy];
        newJson[@"count"] = @(mutable.count);
        newJson[@"vcardBase64"] = [newVcard base64EncodedStringWithOptions:0];

        NSData *out = [NSJSONSerialization dataWithJSONObject:newJson options:NSJSONWritingPrettyPrinted error:&error];
        if (!out || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }

        BOOL w = [out writeToURL:[self _backupFileURL:backupId] options:NSDataWritingAtomic error:&error];
        if (!w) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }

        // 同步更新 index.json 里的 count
        NSDictionary *idx = [self _readBackupIndex];
        NSMutableArray *arr = [idx[@"backups"] mutableCopy] ?: [NSMutableArray array];
        for (NSUInteger i = 0; i < arr.count; i++) {
            NSMutableDictionary *d = [arr[i] mutableCopy];
            if ([d[@"backupId"] isEqualToString:backupId]) {
                d[@"count"] = @(mutable.count);
                arr[i] = d;
                break;
            }
        }
        NSMutableDictionary *newIdx = [idx mutableCopy];
        newIdx[@"backups"] = arr;

        BOOL ok = [self _writeBackupIndex:newIdx error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:CMBackupsDidChangeNotification object:nil];
            
            if (!ok) { if (completion) completion(error); }
            else {
                if (completion) completion(nil);
            }
        });

    });
}

// 是否“已存在”（只用于去重；不做 update）
- (BOOL)_backupContactExistsByPhoneOrEmail:(CNContact *)backup
                                 phoneSet:(NSSet<NSString *> *)phoneSet
                                 emailSet:(NSSet<NSString *> *)emailSet {

    if ([backup isKeyAvailable:CNContactPhoneNumbersKey]) {
        for (CNLabeledValue<CNPhoneNumber *> *lv in (backup.phoneNumbers ?: @[])) {
            NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
            if (k.length > 0 && [phoneSet containsObject:k]) return YES;
        }
    }
    if ([backup isKeyAvailable:CNContactEmailAddressesKey]) {
        for (CNLabeledValue<NSString *> *lv in (backup.emailAddresses ?: @[])) {
            NSString *k = [self _normalizeEmailForMatch:lv.value];
            if (k.length > 0 && [emailSet containsObject:k]) return YES;
        }
    }
    return NO;
}

// 从备份 contact 构建一个“可安全新增”的 CNMutableContact（不碰 note 等敏感字段）
- (CNMutableContact *)_mutableContactForAddFromBackupContact:(CNContact *)b {
    CNMutableContact *mc = [CNMutableContact new];

    // name
    if ([b isKeyAvailable:CNContactGivenNameKey])  mc.givenName  = b.givenName ?: @"";
    if ([b isKeyAvailable:CNContactFamilyNameKey]) mc.familyName = b.familyName ?: @"";
    if ([b isKeyAvailable:CNContactMiddleNameKey]) mc.middleName = b.middleName ?: @"";
    if ([b isKeyAvailable:CNContactNamePrefixKey]) mc.namePrefix = b.namePrefix ?: @"";
    if ([b isKeyAvailable:CNContactNameSuffixKey]) mc.nameSuffix = b.nameSuffix ?: @"";
    if ([b isKeyAvailable:CNContactNicknameKey])   mc.nickname   = b.nickname ?: @"";

    // org/job
    if ([b isKeyAvailable:CNContactOrganizationNameKey]) mc.organizationName = b.organizationName ?: @"";
    if ([b isKeyAvailable:CNContactDepartmentNameKey])   mc.departmentName   = b.departmentName ?: @"";
    if ([b isKeyAvailable:CNContactJobTitleKey])         mc.jobTitle         = b.jobTitle ?: @"";

    // image/birthday
    if ([b isKeyAvailable:CNContactImageDataKey] && b.imageData) mc.imageData = b.imageData;
    if ([b isKeyAvailable:CNContactBirthdayKey] && b.birthday) mc.birthday = b.birthday;
    if ([b isKeyAvailable:CNContactNonGregorianBirthdayKey] && b.nonGregorianBirthday) mc.nonGregorianBirthday = b.nonGregorianBirthday;

    // phones
    if ([b isKeyAvailable:CNContactPhoneNumbersKey]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<CNPhoneNumber *> *lv in (b.phoneNumbers ?: @[])) {
            [arr addObject:[CNLabeledValue labeledValueWithLabel:lv.label value:lv.value]];
        }
        mc.phoneNumbers = arr;
    }

    // emails
    if ([b isKeyAvailable:CNContactEmailAddressesKey]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<NSString *> *lv in (b.emailAddresses ?: @[])) {
            [arr addObject:[CNLabeledValue labeledValueWithLabel:lv.label value:lv.value]];
        }
        mc.emailAddresses = arr;
    }

    // urls
    if ([b isKeyAvailable:CNContactUrlAddressesKey]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<NSString *> *lv in (b.urlAddresses ?: @[])) {
            [arr addObject:[CNLabeledValue labeledValueWithLabel:lv.label value:lv.value]];
        }
        mc.urlAddresses = arr;
    }

    // addresses
    if ([b isKeyAvailable:CNContactPostalAddressesKey]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<CNPostalAddress *> *lv in (b.postalAddresses ?: @[])) {
            [arr addObject:[CNLabeledValue labeledValueWithLabel:lv.label value:lv.value]];
        }
        mc.postalAddresses = arr;
    }

    return mc;
}

- (void)_indexMutableForSets:(CNContact *)c
                    phoneSet:(NSMutableSet<NSString *> *)phoneSet
                    emailSet:(NSMutableSet<NSString *> *)emailSet {

    if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
        for (CNLabeledValue<CNPhoneNumber *> *lv in (c.phoneNumbers ?: @[])) {
            NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
            if (k.length > 0) [phoneSet addObject:k];
        }
    }
    if ([c isKeyAvailable:CNContactEmailAddressesKey]) {
        for (CNLabeledValue<NSString *> *lv in (c.emailAddresses ?: @[])) {
            NSString *k = [self _normalizeEmailForMatch:lv.value];
            if (k.length > 0) [emailSet addObject:k];
        }
    }
}

- (void)restoreContactsSmartFromBackupId:(NSString *)backupId
                 contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                             completion:(CMVoidBlock)completion {

    [self fetchContactsInBackupId:backupId completion:^(NSArray<CNContact *> * _Nullable backupContacts, NSError * _Nullable error) {
        if (error || !backupContacts) { if (completion) completion(error); return; }

        dispatch_async(self.workQueue, ^{
            NSMutableArray<CNContact *> *selected = [NSMutableArray array];
            if (indices.count == 0) {
                [selected addObjectsFromArray:backupContacts];
            } else {
                for (NSNumber *n in indices) {
                    NSInteger i = n.integerValue;
                    if (i >= 0 && i < (NSInteger)backupContacts.count) {
                        [selected addObject:backupContacts[i]];
                    }
                }
            }

            if (selected.count == 0) {
                NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                                 code:501
                                             userInfo:@{NSLocalizedDescriptionKey:@"No contacts selected in backup"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
                return;
            }

            NSString *containerId = [self.store defaultContainerIdentifier];
            if (containerId.length == 0) {
                NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                                 code:502
                                             userInfo:@{NSLocalizedDescriptionKey:@"Default container not found"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
                return;
            }

            NSError *fetchErr = nil;
            NSArray<CNContact *> *existing = [self _fetchAllContactsInDefaultContainerForSmartMatch:&fetchErr];
            if (fetchErr) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(fetchErr); });
                return;
            }

            NSMutableSet<NSString *> *phoneSet = [NSMutableSet set];
            NSMutableSet<NSString *> *emailSet = [NSMutableSet set];

            for (CNContact *c in existing) {
                if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
                    for (CNLabeledValue<CNPhoneNumber *> *lv in (c.phoneNumbers ?: @[])) {
                        NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
                        if (k.length > 0) [phoneSet addObject:k];
                    }
                }
                if ([c isKeyAvailable:CNContactEmailAddressesKey]) {
                    for (CNLabeledValue<NSString *> *lv in (c.emailAddresses ?: @[])) {
                        NSString *k = [self _normalizeEmailForMatch:lv.value];
                        if (k.length > 0) [emailSet addObject:k];
                    }
                }
            }

            CNSaveRequest *req = [CNSaveRequest new];
            NSUInteger addCount = 0;

            for (CNContact *b in selected) {
                if ([self _backupContactExistsByPhoneOrEmail:b phoneSet:phoneSet emailSet:emailSet]) {
                    continue;
                }

                CNMutableContact *mc = [self _mutableContactForAddFromBackupContact:b];
                [req addContact:mc toContainerWithIdentifier:containerId];
                addCount++;

                [self _indexMutableForSets:mc phoneSet:phoneSet emailSet:emailSet];
            }

            if (addCount == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil);
                });
                return;
            }

            NSError *saveErr = nil;
            BOOL ok = [self.store executeSaveRequest:req error:&saveErr];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) { if (completion) completion(saveErr); }
                else { if (completion) completion(nil); }
            });
        });
    }];
}

#pragma mark - Smart Restore Helpers

- (NSArray<id<CNKeyDescriptor>> *)_keysForSmartRestoreFetch {
    return @[
        CNContactIdentifierKey,

        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactNamePrefixKey,
        CNContactNameSuffixKey,
        CNContactNicknameKey,

        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey,
        CNContactPostalAddressesKey,
        CNContactUrlAddressesKey,

        CNContactOrganizationNameKey,
        CNContactDepartmentNameKey,
        CNContactJobTitleKey,

        CNContactImageDataKey,
        CNContactBirthdayKey,
        CNContactNonGregorianBirthdayKey
    ];
}

- (NSArray<CNContact *> *)_fetchAllContactsInDefaultContainerForSmartMatch:(NSError **)error {
    NSString *containerId = [self.store defaultContainerIdentifier];
    if (containerId.length == 0) return @[];

    NSPredicate *pred = [CNContact predicateForContactsInContainerWithIdentifier:containerId];
    return [self.store unifiedContactsMatchingPredicate:pred
                                             keysToFetch:[self _keysForSmartRestoreFetch]
                                                   error:error] ?: @[];
}

- (NSString *)_normalizePhoneForMatch:(NSString *)raw {
    if (raw.length == 0) return @"";
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar ch = [raw characterAtIndex:i];
        if (ch >= '0' && ch <= '9') [digits appendFormat:@"%c", ch];
    }
    if (digits.length > 11) {
        return [digits substringFromIndex:digits.length - 11]; // 国内手机号常用；如不需要可去掉
    }
    return digits;
}

- (NSString *)_normalizeEmailForMatch:(NSString *)raw {
    if (![raw isKindOfClass:[NSString class]] || raw.length == 0) return @"";
    NSString *s = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return s;
}

- (NSString *)_addressKey:(CNPostalAddress *)a {
    if (!a) return @"";
    NSString *s = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",
                   a.street ?: @"",
                   a.city ?: @"",
                   a.state ?: @"",
                   a.postalCode ?: @"",
                   a.country ?: @"",
                   a.ISOCountryCode ?: @""];
    NSString *k = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    // 去掉一些空格
    k = [[k componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    return k;
}

- (CNContact *)_matchExistingContactForBackupContact:(CNContact *)backup
                                           phoneMap:(NSDictionary<NSString *, CNContact *> *)phoneMap
                                           emailMap:(NSDictionary<NSString *, CNContact *> *)emailMap {

    // 先用 phone 匹配
    if ([backup isKeyAvailable:CNContactPhoneNumbersKey]) {
        for (CNLabeledValue<CNPhoneNumber *> *lv in (backup.phoneNumbers ?: @[])) {
            NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
            CNContact *hit = (k.length > 0) ? phoneMap[k] : nil;
            if (hit) return hit;
        }
    }
    // 再用 email 匹配
    if ([backup isKeyAvailable:CNContactEmailAddressesKey]) {
        for (CNLabeledValue<NSString *> *lv in (backup.emailAddresses ?: @[])) {
            NSString *k = [self _normalizeEmailForMatch:lv.value];
            CNContact *hit = (k.length > 0) ? emailMap[k] : nil;
            if (hit) return hit;
        }
    }
    return nil;
}

- (void)_reindexContact:(CNContact *)c
               phoneMap:(NSMutableDictionary<NSString *, CNContact *> *)phoneMap
               emailMap:(NSMutableDictionary<NSString *, CNContact *> *)emailMap {

    if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
        for (CNLabeledValue<CNPhoneNumber *> *lv in (c.phoneNumbers ?: @[])) {
            NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
            if (k.length > 0 && !phoneMap[k]) phoneMap[k] = c;
        }
    }
    if ([c isKeyAvailable:CNContactEmailAddressesKey]) {
        for (CNLabeledValue<NSString *> *lv in (c.emailAddresses ?: @[])) {
            NSString *k = [self _normalizeEmailForMatch:lv.value];
            if (k.length > 0 && !emailMap[k]) emailMap[k] = c;
        }
    }
}

static inline BOOL CMIsEmptyStr(NSString *s) {
    return (![s isKindOfClass:[NSString class]] || s.length == 0);
}

- (void)_mergeBackupContact:(CNContact *)backup intoExistingMutable:(CNMutableContact *)dst {
    if (!backup || !dst) return;

    // 1) 姓名：仅在 dst 为空时补全（不强行覆盖）
    if (CMIsEmptyStr(dst.givenName) && !CMIsEmptyStr(backup.givenName)) dst.givenName = backup.givenName;
    if (CMIsEmptyStr(dst.familyName) && !CMIsEmptyStr(backup.familyName)) dst.familyName = backup.familyName;
    if (CMIsEmptyStr(dst.middleName) && !CMIsEmptyStr(backup.middleName)) dst.middleName = backup.middleName;
    if (CMIsEmptyStr(dst.namePrefix) && !CMIsEmptyStr(backup.namePrefix)) dst.namePrefix = backup.namePrefix;
    if (CMIsEmptyStr(dst.nameSuffix) && !CMIsEmptyStr(backup.nameSuffix)) dst.nameSuffix = backup.nameSuffix;
    if (CMIsEmptyStr(dst.nickname) && !CMIsEmptyStr(backup.nickname)) dst.nickname = backup.nickname;

    // 2) 公司/职位：dst 为空才补
    if (CMIsEmptyStr(dst.organizationName) && !CMIsEmptyStr(backup.organizationName)) dst.organizationName = backup.organizationName;
    if (CMIsEmptyStr(dst.departmentName) && !CMIsEmptyStr(backup.departmentName)) dst.departmentName = backup.departmentName;
    if (CMIsEmptyStr(dst.jobTitle) && !CMIsEmptyStr(backup.jobTitle)) dst.jobTitle = backup.jobTitle;

    // 3) 生日/头像：dst 没有才补
    if (!dst.birthday && backup.birthday) dst.birthday = backup.birthday;
    if (!dst.nonGregorianBirthday && backup.nonGregorianBirthday) dst.nonGregorianBirthday = backup.nonGregorianBirthday;
    if (!dst.imageData && backup.imageData) dst.imageData = backup.imageData;

    // 4) phones：合并 + 去重（按数字）
    NSMutableDictionary<NSString *, CNLabeledValue<CNPhoneNumber *> *> *phoneDict = [NSMutableDictionary dictionary];
    for (CNLabeledValue<CNPhoneNumber *> *lv in (dst.phoneNumbers ?: @[])) {
        NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
        if (k.length > 0 && !phoneDict[k]) phoneDict[k] = lv;
    }
    for (CNLabeledValue<CNPhoneNumber *> *lv in (backup.phoneNumbers ?: @[])) {
        NSString *k = [self _normalizePhoneForMatch:lv.value.stringValue];
        if (k.length == 0) continue;
        if (!phoneDict[k]) {
            CNLabeledValue *newLV = [CNLabeledValue labeledValueWithLabel:lv.label value:lv.value];
            phoneDict[k] = (CNLabeledValue<CNPhoneNumber *> *)newLV;
        }
    }
    dst.phoneNumbers = phoneDict.allValues;

    // 5) emails：合并 + 去重（按 lower）
    NSMutableDictionary<NSString *, CNLabeledValue<NSString *> *> *emailDict = [NSMutableDictionary dictionary];
    for (CNLabeledValue<NSString *> *lv in (dst.emailAddresses ?: @[])) {
        NSString *k = [self _normalizeEmailForMatch:lv.value];
        if (k.length > 0 && !emailDict[k]) emailDict[k] = lv;
    }
    for (CNLabeledValue<NSString *> *lv in (backup.emailAddresses ?: @[])) {
        NSString *k = [self _normalizeEmailForMatch:lv.value];
        if (k.length == 0) continue;
        if (!emailDict[k]) {
            CNLabeledValue *newLV = [CNLabeledValue labeledValueWithLabel:lv.label value:lv.value];
            emailDict[k] = (CNLabeledValue<NSString *> *)newLV;
        }
    }
    dst.emailAddresses = emailDict.allValues;

    // 6) urls：合并 + 去重
    NSMutableDictionary<NSString *, CNLabeledValue<NSString *> *> *urlDict = [NSMutableDictionary dictionary];
    for (CNLabeledValue<NSString *> *lv in (dst.urlAddresses ?: @[])) {
        NSString *k = [self _normalizeEmailForMatch:lv.value]; // url 也用 lower/trim 即可
        if (k.length > 0 && !urlDict[k]) urlDict[k] = lv;
    }
    for (CNLabeledValue<NSString *> *lv in (backup.urlAddresses ?: @[])) {
        NSString *k = [self _normalizeEmailForMatch:lv.value];
        if (k.length == 0) continue;
        if (!urlDict[k]) {
            CNLabeledValue *newLV = [CNLabeledValue labeledValueWithLabel:lv.label value:lv.value];
            urlDict[k] = (CNLabeledValue<NSString *> *)newLV;
        }
    }
    dst.urlAddresses = urlDict.allValues;

    // 7) addresses：合并 + 去重（按字段拼接）
    NSMutableDictionary<NSString *, CNLabeledValue<CNPostalAddress *> *> *addrDict = [NSMutableDictionary dictionary];
    for (CNLabeledValue<CNPostalAddress *> *lv in (dst.postalAddresses ?: @[])) {
        NSString *k = [self _addressKey:lv.value];
        if (k.length > 0 && !addrDict[k]) addrDict[k] = lv;
    }
    for (CNLabeledValue<CNPostalAddress *> *lv in (backup.postalAddresses ?: @[])) {
        NSString *k = [self _addressKey:lv.value];
        if (k.length == 0) continue;
        if (!addrDict[k]) {
            CNLabeledValue *newLV = [CNLabeledValue labeledValueWithLabel:lv.label value:lv.value];
            addrDict[k] = (CNLabeledValue<CNPostalAddress *> *)newLV;
        }
    }
    dst.postalAddresses = addrDict.allValues;
}

- (void)deleteBackupsWithIds:(NSArray<NSString *> *)backupIds completion:(CMVoidBlock)completion {
    dispatch_async(self.workQueue, ^{
        if (backupIds.count == 0) {
            NSError *e = [NSError errorWithDomain:@"ContactsManager"
                                             code:130
                                         userInfo:@{NSLocalizedDescriptionKey:@"No backupIds to delete"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
            return;
        }

        [self _ensureBackupDir];

        // 1) 删文件（best-effort）
        for (NSString *bid in backupIds) {
            if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;
            NSURL *u = [self _backupFileURL:bid];
            [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
        }

        // 2) 更新 index.json
        NSError *err = nil;
        NSDictionary *idx = [self _readBackupIndex];
        NSMutableArray *arr = [idx[@"backups"] mutableCopy];
        if (![arr isKindOfClass:[NSMutableArray class]]) arr = [NSMutableArray array];

        NSSet *rmSet = [NSSet setWithArray:backupIds];

        NSIndexSet *rm = [arr indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger i, BOOL *stop) {
            (void)i; (void)stop;
            NSString *bid = [obj isKindOfClass:[NSDictionary class]] ? obj[@"backupId"] : nil;
            return (bid.length > 0) && [rmSet containsObject:bid];
        }];
        if (rm.count > 0) [arr removeObjectsAtIndexes:rm];

        NSMutableDictionary *newIdx = [idx mutableCopy];
        if (![newIdx isKindOfClass:[NSMutableDictionary class]]) newIdx = [NSMutableDictionary dictionary];
        newIdx[@"backups"] = arr;

        BOOL ok = [self _writeBackupIndex:newIdx error:&err];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:CMBackupsDidChangeNotification object:nil];
            if (!ok) { if (completion) completion(err); }
            else { if (completion) completion(nil); }
        });
    });
}

- (void)restoreContactsOverwriteAllFromBackupId:(NSString *)backupId
                        contactIndicesInBackup:(NSArray<NSNumber *> *)indices
                                    completion:(CMVoidBlock)completion {

    [self fetchContactsInBackupId:backupId completion:^(NSArray<CNContact *> * _Nullable backupContacts, NSError * _Nullable error) {
        if (error || !backupContacts) { if (completion) completion(error); return; }

        dispatch_async(self.workQueue, ^{
            // 选中要恢复的联系人
            NSMutableArray<CNContact *> *selected = [NSMutableArray array];
            if (indices.count == 0) {
                [selected addObjectsFromArray:backupContacts];
            } else {
                for (NSNumber *n in indices) {
                    NSInteger i = n.integerValue;
                    if (i >= 0 && i < (NSInteger)backupContacts.count) {
                        [selected addObject:backupContacts[i]];
                    }
                }
            }

            if (selected.count == 0) {
                NSError *e = [NSError errorWithDomain:@"ContactsManager" code:422
                                             userInfo:@{NSLocalizedDescriptionKey:@"No contacts selected to restore"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
                return;
            }

            NSString *containerId = [self.store defaultContainerIdentifier];
            if (containerId.length == 0) {
                NSError *e = [NSError errorWithDomain:@"ContactsManager" code:420
                                             userInfo:@{NSLocalizedDescriptionKey:@"Default container not found"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); });
                return;
            }

            // 只新增：不管现有联系人，不去重，不跳过
            CNSaveRequest *req = [CNSaveRequest new];
            for (CNContact *c in selected) {
                @autoreleasepool {
                    // 从 vCard 解析出来的 CNContact 没有可用 identifier，直接 add 即可
                    CNMutableContact *mc = [c mutableCopy];
                    [req addContact:mc toContainerWithIdentifier:containerId];
                }
            }

            NSError *saveErr = nil;
            BOOL ok = [self.store executeSaveRequest:req error:&saveErr];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) { if (completion) completion(saveErr); }
                else { if (completion) completion(nil); }
            });
        });
    }];
}

- (void)fetchIncompleteContacts:(CMIncompletesBlock)completion {
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;

        NSMutableArray<CNContact *> *all = [NSMutableArray array];
        NSMutableArray<CNContact *> *missName = [NSMutableArray array];
        NSMutableArray<CNContact *> *missPhone = [NSMutableArray array];
        NSMutableArray<CNContact *> *missBoth = [NSMutableArray array];

        CNContactFetchRequest *req =
            [[CNContactFetchRequest alloc] initWithKeysToFetch:[self keysForIncompleteDetect]];
        req.unifyResults = YES;

        BOOL ok = [self.store enumerateContactsWithFetchRequest:req
                                                         error:&error
                                                    usingBlock:^(CNContact * _Nonnull c, BOOL * _Nonnull stop) {
            @autoreleasepool {
                BOOL n = [self _isNameMissing:c];
                BOOL p = [self _isPhoneMissing:c];
                if (!n && !p) return;

                [all addObject:c];

                if (n && p) {
                    [missBoth addObject:c];
                } else if (n) {
                    [missName addObject:c];
                } else if (p) {
                    [missPhone addObject:c];
                }
            }
        }];

        if (!ok && !error) {
            error = [NSError errorWithDomain:@"ContactsManager"
                                        code:800
                                    userInfo:@{NSLocalizedDescriptionKey:@"Enumerate contacts failed"}];
        }

        NSMutableArray<CMIncompleteGroup *> *groups = [NSMutableArray array];
        if (missBoth.count > 0) {
            CMIncompleteGroup *g = [CMIncompleteGroup new];
            g.type = CMIncompleteTypeMissingNameAndPhone;
            g.items = missBoth;
            [groups addObject:g];
        }
        if (missName.count > 0) {
            CMIncompleteGroup *g = [CMIncompleteGroup new];
            g.type = CMIncompleteTypeMissingName;
            g.items = missName;
            [groups addObject:g];
        }
        if (missPhone.count > 0) {
            CMIncompleteGroup *g = [CMIncompleteGroup new];
            g.type = CMIncompleteTypeMissingPhone;
            g.items = missPhone;
            [groups addObject:g];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok ? all : nil, ok ? groups : nil, error);
        });
    });
}

- (void)deleteIncompleteContactsWithIdentifiers:(NSArray<NSString *> *)identifiers
                                     completion:(CMVoidBlock)completion {
    // 这里就是“批量删除选中项”
    // 删除动作会触发对应账户/容器同步（如 iCloud），但如果某些来源只读，会返回 error
    [self deleteContactsWithIdentifiers:identifiers completion:completion];
}

@end
