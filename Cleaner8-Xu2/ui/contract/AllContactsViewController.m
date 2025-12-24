#import "AllContactsViewController.h"
#import "ContactCell.h"
#import "ASCustomNavBar.h"
#import "ContactsManager.h"
#import <Contacts/Contacts.h>

@interface AllContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, assign) AllContactsMode mode;
@property (nonatomic, copy) NSString *backupId; // restore 模式用

@property (nonatomic, strong) NSMutableArray<CNContact *> *contacts;

// delete/backup 模式用 identifier 选中
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedContactIds;

// ✅ restore 模式：备份内联系人没有稳定 identifier，用 index 选中
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selectedBackupIndices;

@property (nonatomic, strong) ContactsManager *contactsManager;
@property (nonatomic, strong) ASCustomNavBar *navBar;
@property (nonatomic, strong) UICollectionView *cv;

// bottom
@property (nonatomic, strong) UIButton *singleActionButton; // delete/backup
@property (nonatomic, strong) UIView *restoreBar;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic, strong) UIButton *deleteFromBackupButton;

@end

@implementation AllContactsViewController

- (instancetype)initWithMode:(AllContactsMode)mode backupId:(nullable NSString *)backupId {
    if (self = [super init]) {
        _mode = mode;
        _backupId = backupId ?: @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    self.contactsManager = [ContactsManager shared];
    self.selectedContactIds = [NSMutableSet set];
    self.selectedBackupIndices = [NSMutableSet set];

    [self setupNavBar];
    [self setupUI];
    [self loadContacts];
}

- (void)setupNavBar {
    NSString *title = @"所有联系人";
    if (self.mode == AllContactsModeBackup) title = @"选择联系人备份";
    if (self.mode == AllContactsModeRestore) title = @"备份联系人";

    self.navBar = [[ASCustomNavBar alloc] initWithTitle:title];

    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{ [weakSelf.navigationController popViewControllerAnimated:YES]; };

    [self.navBar setShowRightButton:YES];
    self.navBar.onRight = ^(BOOL allSelected) {
        if (weakSelf.mode == AllContactsModeRestore) {
            if ([weakSelf isAllSelectedInBackup]) [weakSelf deselectAllInBackup];
            else [weakSelf selectAllInBackup];
        } else {
            if ([weakSelf isAllSelectedInSystem]) [weakSelf deselectAllInSystem];
            else [weakSelf selectAllInSystem];
        }
        [weakSelf updateBottomState];
        [weakSelf.cv reloadData];
    };

    [self.view addSubview:self.navBar];
}

- (void)setupUI {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(10, 16, 10, 16);
    layout.itemSize = CGSizeMake(self.view.bounds.size.width - 32, 60);

    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.whiteColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    [self.cv registerClass:[ContactCell class] forCellWithReuseIdentifier:@"ContactCell"];
    [self.view addSubview:self.cv];

    if (self.mode == AllContactsModeRestore) {
        [self setupRestoreBar];
    } else {
        [self setupSingleActionButton];
    }
}

- (void)setupSingleActionButton {
    CGFloat h = 50;
    self.singleActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *t = (self.mode == AllContactsModeBackup) ? @"备份联系人" : @"删除联系人";
    [self.singleActionButton setTitle:t forState:UIControlStateNormal];
    self.singleActionButton.frame = CGRectMake(0, self.view.bounds.size.height - h, self.view.bounds.size.width, h);
    self.singleActionButton.backgroundColor = (self.mode == AllContactsModeBackup) ? UIColor.systemBlueColor : UIColor.systemRedColor;
    [self.singleActionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.singleActionButton addTarget:self action:@selector(onSingleAction) forControlEvents:UIControlEventTouchUpInside];
    self.singleActionButton.alpha = 0.0;
    self.singleActionButton.enabled = NO;
    [self.view addSubview:self.singleActionButton];
}

- (void)setupRestoreBar {
    CGFloat h = 50;

    self.restoreBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - h, self.view.bounds.size.width, h)];
    self.restoreBar.backgroundColor = UIColor.whiteColor;

    CGFloat w = self.view.bounds.size.width / 2.0;

    self.restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.restoreButton setTitle:@"恢复" forState:UIControlStateNormal];
    self.restoreButton.frame = CGRectMake(0, 0, w, h);
    self.restoreButton.backgroundColor = UIColor.systemBlueColor;
    [self.restoreButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.restoreButton addTarget:self action:@selector(onRestore) forControlEvents:UIControlEventTouchUpInside];

    self.deleteFromBackupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.deleteFromBackupButton setTitle:@"删除" forState:UIControlStateNormal];
    self.deleteFromBackupButton.frame = CGRectMake(w, 0, w, h);
    self.deleteFromBackupButton.backgroundColor = UIColor.systemRedColor;
    [self.deleteFromBackupButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.deleteFromBackupButton addTarget:self action:@selector(onDeleteFromBackup) forControlEvents:UIControlEventTouchUpInside];

    [self.restoreBar addSubview:self.restoreButton];
    [self.restoreBar addSubview:self.deleteFromBackupButton];

    self.restoreBar.alpha = 0.0;
    self.restoreButton.enabled = NO;
    self.deleteFromBackupButton.enabled = NO;

    [self.view addSubview:self.restoreBar];
}

#pragma mark - Load

- (void)loadContacts {
    __weak typeof(self) weakSelf = self;

    if (self.mode == AllContactsModeRestore) {
        // ✅ 从备份读联系人
        [self.contactsManager fetchContactsInBackupId:self.backupId completion:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error) {
            if (error) { NSLog(@"读取备份失败: %@", error.localizedDescription); return; }
            weakSelf.contacts = [NSMutableArray arrayWithArray:contacts ?: @[]];
            [weakSelf.selectedBackupIndices removeAllObjects];
            [weakSelf.cv reloadData];
            [weakSelf updateBottomState];
        }];
        return;
    }

    // 系统联系人（需要权限）
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) { NSLog(@"通讯录权限失败: %@", error.localizedDescription); return; }

        [weakSelf.contactsManager fetchAllContacts:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error2) {
            if (error2) { NSLog(@"获取联系人失败: %@", error2.localizedDescription); return; }

            weakSelf.contacts = [NSMutableArray arrayWithArray:contacts ?: @[]];
            [weakSelf.selectedContactIds removeAllObjects];
            [weakSelf.cv reloadData];
            [weakSelf updateBottomState];
        }];
    }];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.contacts.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ContactCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ContactCell" forIndexPath:indexPath];

    CNContact *c = self.contacts[indexPath.item];

    NSString *name = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
    if (name.length == 0) name = @"(无姓名)";

    NSString *phone = @"";
    if ([c isKeyAvailable:CNContactPhoneNumbersKey] && c.phoneNumbers.count > 0) {
        CNPhoneNumber *pn = c.phoneNumbers.firstObject.value;
        phone = pn.stringValue ?: @"";
    }

    cell.nameLabel.text = name;
    cell.phoneLabel.text = phone.length ? phone : @"无电话号码";

    if (self.mode == AllContactsModeRestore) {
        cell.checkButton.selected = [self.selectedBackupIndices containsObject:@(indexPath.item)];
    } else {
        cell.checkButton.selected = [self.selectedContactIds containsObject:c.identifier];
    }

    __weak typeof(self) weakSelf = self;
    cell.onSelect = ^{
        [weakSelf toggleSelectionAtIndex:indexPath.item];
    };

    return cell;
}

- (void)toggleSelectionAtIndex:(NSInteger)idx {
    if (self.mode == AllContactsModeRestore) {
        NSNumber *k = @(idx);
        if ([self.selectedBackupIndices containsObject:k]) [self.selectedBackupIndices removeObject:k];
        else [self.selectedBackupIndices addObject:k];
    } else {
        CNContact *c = self.contacts[idx];
        NSString *cid = c.identifier ?: @"";
        if (cid.length == 0) return;
        if ([self.selectedContactIds containsObject:cid]) [self.selectedContactIds removeObject:cid];
        else [self.selectedContactIds addObject:cid];
    }

    [self updateBottomState];
    [self.cv reloadData];
}

#pragma mark - Select all / deselect all

- (BOOL)isAllSelectedInSystem {
    if (self.contacts.count == 0) return NO;
    for (CNContact *c in self.contacts) {
        if (c.identifier.length == 0) continue;
        if (![self.selectedContactIds containsObject:c.identifier]) return NO;
    }
    return YES;
}

- (void)selectAllInSystem {
    [self.selectedContactIds removeAllObjects];
    for (CNContact *c in self.contacts) if (c.identifier.length > 0) [self.selectedContactIds addObject:c.identifier];
}

- (void)deselectAllInSystem {
    [self.selectedContactIds removeAllObjects];
}

- (BOOL)isAllSelectedInBackup {
    if (self.contacts.count == 0) return NO;
    return self.selectedBackupIndices.count == self.contacts.count;
}

- (void)selectAllInBackup {
    [self.selectedBackupIndices removeAllObjects];
    for (NSInteger i = 0; i < (NSInteger)self.contacts.count; i++) [self.selectedBackupIndices addObject:@(i)];
}

- (void)deselectAllInBackup {
    [self.selectedBackupIndices removeAllObjects];
}

#pragma mark - Bottom state

- (void)updateBottomState {
    BOOL hasSelected = NO;

    if (self.mode == AllContactsModeRestore) {
        hasSelected = (self.selectedBackupIndices.count > 0);
        self.restoreBar.alpha = hasSelected ? 1.0 : 0.0;
        self.restoreButton.enabled = hasSelected;
        self.deleteFromBackupButton.enabled = hasSelected;
    } else {
        hasSelected = (self.selectedContactIds.count > 0);
        self.singleActionButton.alpha = hasSelected ? 1.0 : 0.0;
        self.singleActionButton.enabled = hasSelected;
    }
}

#pragma mark - Actions

- (void)onSingleAction {
    if (self.mode == AllContactsModeBackup) {
        [self doBackupSelected];
    } else {
        [self doDeleteSelectedFromSystem];
    }
}

- (void)doBackupSelected {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *backupName = [NSString stringWithFormat:@"备份 %@", [fmt stringFromDate:[NSDate date]]];

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:@"无法访问通讯录" message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager backupContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                     backupName:backupName
                                                     completion:^(NSString * _Nullable backupId, NSError * _Nullable error2) {
            if (error2) {
                [weakSelf showAlertWithTitle:@"备份失败" message:error2.localizedDescription];
                return;
            }

            // 通知备份列表页刷新
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CMBackupDidFinish" object:nil];

            // ✅ 成功：点确定返回
            [weakSelf showAlertPopBackWithTitle:@"成功" message:@"备份完成"];
        }];
    }];
}


- (void)doDeleteSelectedFromSystem {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:@"无法访问通讯录" message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager deleteContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                    completion:^(NSError * _Nullable error2) {
            if (error2) {
                [weakSelf showAlertWithTitle:@"删除失败" message:error2.localizedDescription];
                return;
            }

            NSIndexSet *rm = [weakSelf.contacts indexesOfObjectsPassingTest:^BOOL(CNContact *obj, NSUInteger idx, BOOL *stop) {
                return [weakSelf.selectedContactIds containsObject:obj.identifier];
            }];
            [weakSelf.contacts removeObjectsAtIndexes:rm];

            [weakSelf.selectedContactIds removeAllObjects];
            [weakSelf.cv reloadData];
            [weakSelf updateBottomState];

            // ✅ 成功：点确定返回
            [weakSelf showAlertPopBackWithTitle:@"成功" message:@"删除完成"];
        }];
    }];
}

- (void)onRestore {
    if (self.selectedBackupIndices.count == 0) return;

    __weak typeof(self) weakSelf = self;
    NSArray<NSNumber *> *indices = self.selectedBackupIndices.allObjects;

    // 追加 restoreContactsFromBackupId
    // 智能覆盖 restoreContactsSmartFromBackupId
    // 强制覆盖所有 restoreContactsOverwriteAllFromBackupId
    [self.contactsManager restoreContactsOverwriteAllFromBackupId:self.backupId
                                         contactIndicesInBackup:indices
                                                     completion:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:@"恢复失败" message:error.localizedDescription];
            return;
        }

        [weakSelf.selectedBackupIndices removeAllObjects];
        [weakSelf.cv reloadData];
        [weakSelf updateBottomState];

        // ✅ 成功：点确定返回
        [weakSelf showAlertPopBackWithTitle:@"成功" message:@"恢复完成"];
    }];
}

- (void)onDeleteFromBackup {
    if (self.selectedBackupIndices.count == 0) return;

    __weak typeof(self) weakSelf = self;
    NSArray<NSNumber *> *indices = self.selectedBackupIndices.allObjects;

    [self.contactsManager deleteContactsFromBackupId:self.backupId
                             contactIndicesInBackup:indices
                                         completion:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:@"删除失败" message:error.localizedDescription];
            return;
        }

        // 本地也删掉（按 indexSet 方式）
        NSMutableIndexSet *rm = [NSMutableIndexSet indexSet];
        for (NSNumber *n in indices) {
            NSInteger i = n.integerValue;
            if (i >= 0 && i < (NSInteger)weakSelf.contacts.count) [rm addIndex:(NSUInteger)i];
        }
        [weakSelf.contacts removeObjectsAtIndexes:rm];

        [weakSelf.selectedBackupIndices removeAllObjects];
        [weakSelf.cv reloadData];
        [weakSelf updateBottomState];

        // 如果备份删空：提示后返回
        if (weakSelf.contacts.count == 0) {
            [weakSelf showAlertPopBackWithTitle:@"提示" message:@"该备份已清空并删除"];
            return;
        }

        // ✅ 成功：点确定返回
        [weakSelf showAlertPopBackWithTitle:@"成功" message:@"已从备份中删除"];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"确定"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showAlertPopBackWithTitle:(NSString *)title message:(NSString *)message {
    __weak typeof(self) weakSelf = self;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"确定"
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat navH = 44 + self.view.safeAreaInsets.top;
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    CGFloat bottomH = 50;
    CGFloat top = navH;

    if (self.mode == AllContactsModeRestore) {
        self.restoreBar.frame = CGRectMake(0, self.view.bounds.size.height - bottomH, self.view.bounds.size.width, bottomH);
    } else {
        self.singleActionButton.frame = CGRectMake(0, self.view.bounds.size.height - bottomH, self.view.bounds.size.width, bottomH);
    }

    self.cv.frame = CGRectMake(0, top, self.view.bounds.size.width, self.view.bounds.size.height - top - bottomH);
}

@end
