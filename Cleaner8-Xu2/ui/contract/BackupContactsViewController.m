#import "BackupContactsViewController.h"
#import "ASCustomNavBar.h"
#import "ContactCell.h"
#import "ContactsManager.h"
#import "AllContactsViewController.h"

@interface BackupContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) ASCustomNavBar *navBar;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<CMBackupInfo *> *backups;
@property (nonatomic, strong) ContactsManager *contactsManager;

// 空态
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIButton *goBackupButton;
@end

@implementation BackupContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;
    self.contactsManager = [ContactsManager shared];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onBackupDidFinish)
                                                 name:@"CMBackupDidFinish"
                                               object:nil];

    [self setupNavBar];
    [self setupUI];
    [self setupEmptyView];
    [self loadBackups];
}

- (void)onBackupDidFinish {
    [self loadBackups];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从备份/恢复页返回后刷新列表
    [self loadBackups];
}

- (void)setupNavBar {
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:@"备份联系人"];
    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{ [weakSelf.navigationController popViewControllerAnimated:YES]; };
    [self.navBar setShowRightButton:NO];
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

    // ✅ 底部固定“去备份”按钮（无论是否有备份都显示）
    self.goBackupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.goBackupButton setTitle:@"去备份" forState:UIControlStateNormal];
    self.goBackupButton.backgroundColor = [UIColor systemBlueColor];
    [self.goBackupButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.goBackupButton.layer.cornerRadius = 12;
    self.goBackupButton.clipsToBounds = YES;
    [self.goBackupButton addTarget:self action:@selector(onGoBackup) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.goBackupButton];
}

- (void)setupEmptyView {
    self.emptyView = [[UIView alloc] initWithFrame:CGRectZero];
    self.emptyView.hidden = YES;

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectZero];
    tip.text = @"暂无备份";
    tip.textAlignment = NSTextAlignmentCenter;
    tip.textColor = [UIColor darkGrayColor];
    tip.font = [UIFont systemFontOfSize:16];

    [self.emptyView addSubview:tip];
    [self.view addSubview:self.emptyView];
}


- (void)onGoBackup {
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeBackup backupId:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)loadBackups {
    __weak typeof(self) weakSelf = self;
    [self.contactsManager fetchBackupList:^(NSArray<CMBackupInfo *> * _Nullable backups, NSError * _Nullable error) {
        if (error) {
            NSLog(@"读取备份列表失败: %@", error.localizedDescription);
            weakSelf.backups = @[];
            [weakSelf.cv reloadData];
            [weakSelf updateEmptyState];
            return;
        }
        weakSelf.backups = backups ?: @[];
        [weakSelf.cv reloadData];
        [weakSelf updateEmptyState];
    }];
}

- (void)updateEmptyState {
    BOOL empty = (self.backups.count == 0);
    self.cv.hidden = empty;
    self.emptyView.hidden = !empty;

    // ✅ “去备份”永远可用
    self.goBackupButton.hidden = NO;
    self.goBackupButton.enabled = YES;
    self.goBackupButton.alpha = 1.0;
}


#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.backups.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ContactCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ContactCell" forIndexPath:indexPath];

    CMBackupInfo *info = self.backups[indexPath.item];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    cell.nameLabel.text = [fmt stringFromDate:info.date ?: [NSDate date]];
    cell.phoneLabel.text = [NSString stringWithFormat:@"数量：%lu", (unsigned long)info.count];

    // 列表不需要勾选
    cell.checkButton.hidden = YES;
    cell.onSelect = nil;

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    CMBackupInfo *info = self.backups[indexPath.item];

    AllContactsViewController *vc = [[AllContactsViewController alloc] initWithMode:AllContactsModeRestore backupId:info.backupId];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat navH = 44 + self.view.safeAreaInsets.top;
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    // 底部按钮高度
    CGFloat btnH = 44;
    CGFloat bottomPadding = self.view.safeAreaInsets.bottom;
    CGFloat btnY = self.view.bounds.size.height - bottomPadding - btnH - 12;

    self.goBackupButton.frame = CGRectMake(16, btnY, self.view.bounds.size.width - 32, btnH);

    // collectionView 留出按钮空间
    CGFloat cvH = btnY - navH - 12;
    self.cv.frame = CGRectMake(0, navH, self.view.bounds.size.width, cvH);

    // emptyView 与 cv 同区域（按钮在下方）
    self.emptyView.frame = CGRectMake(0, navH, self.view.bounds.size.width, cvH);

    // 居中提示
    UILabel *tip = (UILabel *)self.emptyView.subviews.firstObject;
    tip.frame = CGRectMake(0, (self.emptyView.bounds.size.height - 30)/2.0,
                           self.emptyView.bounds.size.width, 30);
}

@end
