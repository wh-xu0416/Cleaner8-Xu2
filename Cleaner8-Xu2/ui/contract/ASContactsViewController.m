#import "ASContactsViewController.h"
#import "AllContactsViewController.h"      // 所有联系人列表
#import "DuplicateContactsViewController.h" // 重复联系人列表
#import "BackupContactsViewController.h"    // 备份联系人列表
#import "ASCustomNavBar.h"

@interface ASContactsViewController ()

@property (nonatomic, strong) ASCustomNavBar *navBar;  // 自定义导航栏
@property (nonatomic, strong) UIButton *allContactsButton;     // 所有联系人按钮
@property (nonatomic, strong) UIButton *duplicateContactsButton; // 重复联系人按钮
@property (nonatomic, strong) UIButton *backupContactsButton;    // 备份联系人按钮

@end

@implementation ASContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = UIColor.whiteColor;
    
    // 设置自定义导航栏
    [self setupNavBar];
    
    // 设置UI（按钮）
    [self setupButtons];
}

- (void)setupNavBar {
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:@"联系人"];
    
    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    
    // 隐藏右侧按钮
    [self.navBar setShowRightButton:NO];
    [self.view addSubview:self.navBar];
}

- (void)setupButtons {
    CGFloat buttonWidth = 200;
    CGFloat buttonHeight = 44;
    CGFloat spacing = 20;
    
    // 所有联系人按钮
    self.allContactsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.allContactsButton setTitle:@"所有联系人" forState:UIControlStateNormal];
    self.allContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, 100, buttonWidth, buttonHeight);
    [self.allContactsButton addTarget:self action:@selector(goToAllContacts) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.allContactsButton];
    
    // 重复联系人按钮
    self.duplicateContactsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.duplicateContactsButton setTitle:@"重复联系人" forState:UIControlStateNormal];
    self.duplicateContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, CGRectGetMaxY(self.allContactsButton.frame) + spacing, buttonWidth, buttonHeight);
    [self.duplicateContactsButton addTarget:self action:@selector(goToDuplicateContacts) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.duplicateContactsButton];
    
    // 备份联系人按钮
    self.backupContactsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backupContactsButton setTitle:@"备份联系人" forState:UIControlStateNormal];
    self.backupContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, CGRectGetMaxY(self.duplicateContactsButton.frame) + spacing, buttonWidth, buttonHeight);
    [self.backupContactsButton addTarget:self action:@selector(goToBackupContacts) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backupContactsButton];
}

// 跳转到所有联系人页面
- (void)goToAllContacts {
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeDelete backupId:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

// 跳转到重复联系人页面
- (void)goToDuplicateContacts {
    DuplicateContactsViewController *duplicateContactsVC = [[DuplicateContactsViewController alloc] init];
    [self.navigationController pushViewController:duplicateContactsVC animated:YES];
}

// 跳转到备份联系人页面
- (void)goToBackupContacts {
    BackupContactsViewController *backupContactsVC = [[BackupContactsViewController alloc] init];
    [self.navigationController pushViewController:backupContactsVC animated:YES];
}

// 调整布局，确保导航栏和底部栏不会遮挡内容
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    CGFloat navH = 44 + self.view.safeAreaInsets.top;  // 考虑安全区
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);
    
    // 调整按钮的位置
    CGFloat buttonWidth = 200;
    CGFloat buttonHeight = 44;
    CGFloat spacing = 20;
    
    self.allContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, navH + 20, buttonWidth, buttonHeight);
    self.duplicateContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, CGRectGetMaxY(self.allContactsButton.frame) + spacing, buttonWidth, buttonHeight);
    self.backupContactsButton.frame = CGRectMake((self.view.bounds.size.width - buttonWidth) / 2, CGRectGetMaxY(self.duplicateContactsButton.frame) + spacing, buttonWidth, buttonHeight);
}

@end
