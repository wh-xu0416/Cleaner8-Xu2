#import "DuplicateContactsViewController.h"
#import "ASCustomNavBar.h"
#import "ContactCell.h"
#import "ContactsManager.h"
#import <Contacts/Contacts.h>

@interface DuplicateContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) ASCustomNavBar *navBar;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIButton *mergeButton;

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, assign) NSInteger currentTab; // 0:所有 1:姓名 2:号码

@property (nonatomic, strong) NSArray<CMDuplicateGroup *> *allGroups;
@property (nonatomic, strong) NSArray<CMDuplicateGroup *> *nameGroups;
@property (nonatomic, strong) NSArray<CMDuplicateGroup *> *phoneGroups;

@property (nonatomic, strong) NSMutableSet<NSString *> *selectedContactIds; // identifier 集合
@property (nonatomic, strong) ContactsManager *contactsManager;

@end

@implementation DuplicateContactsViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentTab = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;
    self.contactsManager = [ContactsManager shared];
    self.selectedContactIds = [NSMutableSet set];

    [self setupNavBar];
    [self setupUI];
    [self setupContacts];
}

#pragma mark - UI

- (void)setupNavBar {
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:@"重复联系人"];

    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };

    [self.navBar setShowRightButton:YES];
    self.navBar.onRight = ^(BOOL allSelected) {
        // ✅ 不用 allSelected，按当前展示范围是否已全选来切换
        if ([weakSelf isAllSelectedDisplayed]) {
            [weakSelf deselectAllDisplayed];
        } else {
            [weakSelf selectAllDisplayed];
        }
        [weakSelf updateMergeButtonState];
        [weakSelf.cv reloadData];
    };

    [self.view addSubview:self.navBar];
}

- (void)setupUI {
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"所有", @"姓名重复", @"号码重复"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(didChangeSegment:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentedControl];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(10, 16, 20, 16);
    layout.itemSize = CGSizeMake(self.view.bounds.size.width - 32, 60);

    // ✅ 组头
    layout.headerReferenceSize = CGSizeMake(self.view.bounds.size.width, 34);

    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.whiteColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;

    [self.cv registerClass:[ContactCell class] forCellWithReuseIdentifier:@"ContactCell"];
    [self.cv registerClass:[UICollectionReusableView class]
forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
       withReuseIdentifier:@"DupHeader"];

    [self.view addSubview:self.cv];

    [self setupMergeButton];
}

- (void)setupMergeButton {
    self.mergeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.mergeButton setTitle:@"合并联系人" forState:UIControlStateNormal];
    self.mergeButton.frame = CGRectMake(0, self.view.bounds.size.height - 50, self.view.bounds.size.width, 50);
    self.mergeButton.backgroundColor = [UIColor systemBlueColor];
    [self.mergeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.mergeButton addTarget:self action:@selector(mergeContacts) forControlEvents:UIControlEventTouchUpInside];
    self.mergeButton.alpha = 0.0;
    self.mergeButton.enabled = NO;
    [self.view addSubview:self.mergeButton];
}

- (void)didChangeSegment:(UISegmentedControl *)sender {
    self.currentTab = sender.selectedSegmentIndex;
    [self.selectedContactIds removeAllObjects];
    [self updateMergeButtonState];
    [self.cv reloadData];
}

#pragma mark - Data loading

- (void)setupContacts {
    __weak typeof(self) weakSelf = self;

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"通讯录权限失败: %@", error.localizedDescription);
            return;
        }

        [weakSelf.contactsManager fetchDuplicateContactsWithMode:CMDuplicateModeAll
                                                     completion:^(NSArray<CMDuplicateGroup *> * _Nullable groups,
                                                                  NSArray<CMDuplicateGroup *> * _Nullable nameGroups,
                                                                  NSArray<CMDuplicateGroup *> * _Nullable phoneGroups,
                                                                  NSError * _Nullable error2) {
            if (error2) {
                NSLog(@"获取重复联系人失败: %@", error2.localizedDescription);
                return;
            }

            weakSelf.nameGroups = nameGroups ?: @[];
            weakSelf.phoneGroups = phoneGroups ?: @[];
            weakSelf.allGroups = [(weakSelf.nameGroups ?: @[]) arrayByAddingObjectsFromArray:(weakSelf.phoneGroups ?: @[])];

            [weakSelf.selectedContactIds removeAllObjects];
            [weakSelf.cv reloadData];
            [weakSelf updateMergeButtonState];
        }];
    }];
}

#pragma mark - Helpers (displayed groups/ids)

- (NSArray<CMDuplicateGroup *> *)displayedGroups {
    if (self.currentTab == 1) return self.nameGroups ?: @[];
    if (self.currentTab == 2) return self.phoneGroups ?: @[];
    return self.allGroups ?: @[];
}

- (NSSet<NSString *> *)displayedIDsSet {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (CMDuplicateGroup *g in [self displayedGroups]) {
        for (CNContact *c in g.items) {
            if (c.identifier.length > 0) [set addObject:c.identifier];
        }
    }
    return set;
}

- (BOOL)isAllSelectedDisplayed {
    NSSet *displayed = [self displayedIDsSet];
    if (displayed.count == 0) return NO;
    return [displayed isSubsetOfSet:self.selectedContactIds];
}

- (void)selectAllDisplayed {
    [self.selectedContactIds unionSet:[self displayedIDsSet]];
}

- (void)deselectAllDisplayed {
    [self.selectedContactIds minusSet:[self displayedIDsSet]];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self displayedGroups].count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    CMDuplicateGroup *g = [self displayedGroups][section];
    return g.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ContactCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ContactCell" forIndexPath:indexPath];

    CMDuplicateGroup *g = [self displayedGroups][indexPath.section];
    CNContact *c = g.items[indexPath.item];

    NSString *name = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
    if (name.length == 0) name = @"(无姓名)";
    cell.nameLabel.text = name;

    NSString *phone = @"";
    if ([c isKeyAvailable:CNContactPhoneNumbersKey] && c.phoneNumbers.count > 0) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<CNPhoneNumber *> *lv in c.phoneNumbers) {
            NSString *p = lv.value.stringValue ?: @"";
            if (p.length > 0) [arr addObject:p];
        }
        phone = [arr componentsJoinedByString:@" · "];
    }
    cell.phoneLabel.text = phone;

    cell.checkButton.selected = [self.selectedContactIds containsObject:c.identifier];

    __weak typeof(self) weakSelf = self;
    cell.onSelect = ^{
        [weakSelf toggleSingleContact:c.identifier];
    };

    return cell;
}

#pragma mark - Section Header (重复组1/2/3...)

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) {
        return [UICollectionReusableView new];
    }

    UICollectionReusableView *v =
    [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                       withReuseIdentifier:@"DupHeader"
                                              forIndexPath:indexPath];

    [v.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, collectionView.bounds.size.width - 32, 34)];
    lab.font = [UIFont boldSystemFontOfSize:16];
    lab.textColor = [UIColor blackColor];
    lab.text = [NSString stringWithFormat:@"重复组%ld", (long)indexPath.section + 1];
    [v addSubview:lab];

    return v;
}

#pragma mark - Selection (single contact)

- (void)toggleSingleContact:(NSString *)identifier {
    if (identifier.length == 0) return;

    if ([self.selectedContactIds containsObject:identifier]) {
        [self.selectedContactIds removeObject:identifier];
    } else {
        [self.selectedContactIds addObject:identifier];
    }

    [self updateMergeButtonState];
    [self.cv reloadData];
}

#pragma mark - Merge button state (组内选中>=2才显示)

- (BOOL)hasMergeableGroupDisplayed {
    for (CMDuplicateGroup *g in [self displayedGroups]) {
        NSInteger cnt = 0;
        for (CNContact *c in g.items) {
            if ([self.selectedContactIds containsObject:c.identifier]) {
                cnt++;
                if (cnt >= 2) return YES;
            }
        }
    }
    return NO;
}

- (void)updateMergeButtonState {
    BOOL show = [self hasMergeableGroupDisplayed];
    self.mergeButton.alpha = show ? 1.0 : 0.0;
    self.mergeButton.enabled = show;
}

#pragma mark - Merge (按组逐组合并，避免跨组乱合并)

- (void)mergeContacts {
    NSArray<CMDuplicateGroup *> *groups = [self displayedGroups];
    NSMutableArray<NSArray<NSString *> *> *batches = [NSMutableArray array];

    for (CMDuplicateGroup *g in groups) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (CNContact *c in g.items) {
            if ([self.selectedContactIds containsObject:c.identifier]) {
                [ids addObject:c.identifier];
            }
        }
        if (ids.count >= 2) [batches addObject:ids];
    }

    if (batches.count == 0) return;

    __weak typeof(self) weakSelf = self;
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"通讯录权限失败: %@", error.localizedDescription);
            return;
        }
        [weakSelf mergeBatchesSequentially:batches index:0];
    }];
}

- (void)mergeBatchesSequentially:(NSArray<NSArray<NSString *> *> *)batches index:(NSInteger)idx {
    if (idx >= (NSInteger)batches.count) {
        // 全部完成：刷新
        [self.selectedContactIds removeAllObjects];
        [self updateMergeButtonState];
        [self setupContacts];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *ids = batches[idx];

    [self.contactsManager mergeContactsWithIdentifiers:ids preferredPrimary:nil completion:^(NSString * _Nullable mergedIdentifier, NSError * _Nullable error) {
        if (error) {
            NSLog(@"批次合并失败 idx=%ld error=%@", (long)idx, error.localizedDescription);
            // 失败也继续下一组（你想中断就 return）
        } else {
            NSLog(@"批次合并成功 idx=%ld merged=%@", (long)idx, mergedIdentifier);
        }
        [weakSelf mergeBatchesSequentially:batches index:idx + 1];
    }];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat navH = 44 + self.view.safeAreaInsets.top;
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    self.segmentedControl.frame = CGRectMake(16, navH + 8, self.view.bounds.size.width - 32, 34);

    CGFloat bottomH = 50;
    self.mergeButton.frame = CGRectMake(0, self.view.bounds.size.height - bottomH, self.view.bounds.size.width, bottomH);

    CGFloat top = navH + 8 + 34 + 8;
    self.cv.frame = CGRectMake(0, top, self.view.bounds.size.width, self.view.bounds.size.height - top - bottomH);
}

@end
