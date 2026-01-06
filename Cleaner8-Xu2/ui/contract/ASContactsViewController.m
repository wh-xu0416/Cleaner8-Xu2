#import "ASContactsViewController.h"
#import "AllContactsViewController.h"
#import "DuplicateContactsViewController.h"
#import "BackupContactsViewController.h"
#import "ASCustomNavBar.h"
#import "ContactsManager.h"
#import <Contacts/Contacts.h>

#pragma mark - UI Helpers
static inline UIColor *ASRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIFont *ASFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

@interface ASContactsViewController ()
@property (nonatomic, strong) CNContactStore *contactStore;

@property (nonatomic, assign) BOOL refreshScheduled;
@property (nonatomic, assign) BOOL isRefreshing;

@property (nonatomic, strong) UIImageView *bgTop;
@property (nonatomic, strong) ASCustomNavBar *navBar;

// cards
@property (nonatomic, strong) UIControl *cardDuplicate;
@property (nonatomic, strong) UIControl *cardIncomplete;
@property (nonatomic, strong) UIControl *cardBackups;
@property (nonatomic, strong) UIControl *cardAll;

// subtitle labels (for counts)
@property (nonatomic, strong) UILabel *subDuplicate;
@property (nonatomic, strong) UILabel *subIncomplete;
@property (nonatomic, strong) UILabel *subBackups;
@property (nonatomic, strong) UILabel *subAll;

@end

@implementation ASContactsViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [self scheduleRefreshCounts];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scheduleRefreshCounts];
    [self requestContactsPermissionIfNeeded];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASRGB(246, 248, 251);

    [self buildBackground];
    [self setupNavBar];
    [self buildCards];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onContactsChanged:)
                                                 name:CNContactStoreDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onBackupsChanged:)
                                                 name:CMBackupsDidChangeNotification
                                               object:nil];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
  
    [self requestContactsPermissionIfNeeded];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onContactsChanged:(NSNotification *)n {
    [self scheduleRefreshCounts];
}

- (void)onBackupsChanged:(NSNotification *)n {
    [self scheduleRefreshCounts];
}

- (void)scheduleRefreshCounts {
    // 只在页面可见时刷新（避免后台浪费）
    if (!self.isViewLoaded || self.view.window == nil) return;

    // 防抖：0.35s 内多次变化只刷新一次
    if (self.refreshScheduled) return;
    self.refreshScheduled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.refreshScheduled = NO;
        [self refreshCounts];
    });
}

- (void)onEnterForeground:(NSNotification *)n {
    [self scheduleRefreshCounts];
}

#pragma mark - Contacts Permission

- (void)requestContactsPermissionIfNeeded {
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];

    switch (status) {
        case CNAuthorizationStatusAuthorized: {
            // 已授权：正常刷新
            [self scheduleRefreshCounts];
        } break;

        case CNAuthorizationStatusNotDetermined: {
            __weak typeof(self) weakSelf = self;
            [self.contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) {
                        [weakSelf scheduleRefreshCounts];
                    } else {
                    }
                });
            }];
        } break;

        case CNAuthorizationStatusDenied:
        case CNAuthorizationStatusRestricted: {
        } break;

        default: {
        } break;
    }
}

#pragma mark - Background

- (void)buildBackground {
    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    self.bgTop.userInteractionEnabled = NO;
    [self.view addSubview:self.bgTop];

    [NSLayoutConstraint activateConstraints:@[
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:360],
    ]];
}

#pragma mark - Nav

- (void)setupNavBar {
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:@"Contact"];

    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navBar setShowRightButton:NO];

    [self.view addSubview:self.navBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat navH = 44 + self.view.safeAreaInsets.top;
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);
    [self.view bringSubviewToFront:self.navBar];
}

#pragma mark - Cards UI

- (void)buildCards {
    // 四个卡片：Duplicate / Incomplete / Backups / All
    self.cardDuplicate = [self buildCardWithTitle:@"Duplicate Contacts"
                                      subtitleLab:&_subDuplicate
                                          action:@selector(tapDuplicate)];

    self.cardIncomplete = [self buildCardWithTitle:@"Incomplete Contacts"
                                       subtitleLab:&_subIncomplete
                                           action:@selector(tapIncomplete)];

    self.cardBackups = [self buildCardWithTitle:@"Backups"
                                    subtitleLab:&_subBackups
                                        action:@selector(tapBackups)];

    self.cardAll = [self buildCardWithTitle:@"All Contacts"
                                subtitleLab:&_subAll
                                    action:@selector(tapAll)];

    [self.view addSubview:self.cardDuplicate];
    [self.view addSubview:self.cardIncomplete];
    [self.view addSubview:self.cardBackups];
    [self.view addSubview:self.cardAll];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // 统一：左右边距 20，卡片之间间距 20
    [NSLayoutConstraint activateConstraints:@[
        [self.cardDuplicate.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.cardDuplicate.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.cardDuplicate.topAnchor constraintEqualToAnchor:safe.topAnchor constant:88],

        [self.cardIncomplete.leadingAnchor constraintEqualToAnchor:self.cardDuplicate.leadingAnchor],
        [self.cardIncomplete.trailingAnchor constraintEqualToAnchor:self.cardDuplicate.trailingAnchor],
        [self.cardIncomplete.topAnchor constraintEqualToAnchor:self.cardDuplicate.bottomAnchor constant:20],

        [self.cardBackups.leadingAnchor constraintEqualToAnchor:self.cardDuplicate.leadingAnchor],
        [self.cardBackups.trailingAnchor constraintEqualToAnchor:self.cardDuplicate.trailingAnchor],
        [self.cardBackups.topAnchor constraintEqualToAnchor:self.cardIncomplete.bottomAnchor constant:20],

        [self.cardAll.leadingAnchor constraintEqualToAnchor:self.cardDuplicate.leadingAnchor],
        [self.cardAll.trailingAnchor constraintEqualToAnchor:self.cardDuplicate.trailingAnchor],
        [self.cardAll.topAnchor constraintEqualToAnchor:self.cardBackups.bottomAnchor constant:20],

        // 底部不强行贴死，避免小屏顶到下面
        [self.cardAll.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-24],
    ]];
}

// 卡片规范：白底、圆角16、内边距 左右20 上下18
// 左：title(24 Medium 黑)；下方7pt subtitle(17 Regular 黑)；右：ic_todo_small 40x24 垂直居中
- (UIControl *)buildCardWithTitle:(NSString *)title
                      subtitleLab:(UILabel * __strong *)subtitleOut
                          action:(SEL)sel {

    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 16;
    card.layer.masksToBounds = NO;

    if (sel) {
        [card addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    }

    UILabel *titleLab = [UILabel new];
    titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    titleLab.text = title;
    titleLab.textColor = UIColor.blackColor;
    titleLab.font = ASFont(24, UIFontWeightMedium);
    [card addSubview:titleLab];

    UILabel *subLab = [UILabel new];
    subLab.translatesAutoresizingMaskIntoConstraints = NO;
    subLab.text = [NSString stringWithFormat:@"0 %@", title];
    subLab.textColor = UIColor.blackColor;
    subLab.font = ASFont(17, UIFontWeightRegular);
    [card addSubview:subLab];

    UIImageView *rightImg = [UIImageView new];
    rightImg.translatesAutoresizingMaskIntoConstraints = NO;
    rightImg.image = [[UIImage imageNamed:@"ic_todo_small"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    rightImg.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:rightImg];

    [NSLayoutConstraint activateConstraints:@[
        // right image
        [rightImg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [rightImg.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [rightImg.widthAnchor constraintEqualToConstant:40],
        [rightImg.heightAnchor constraintEqualToConstant:24],

        // title
        [titleLab.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [titleLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightImg.leadingAnchor constant:-12],

        // subtitle
        [subLab.leadingAnchor constraintEqualToAnchor:titleLab.leadingAnchor],
        [subLab.topAnchor constraintEqualToAnchor:titleLab.bottomAnchor constant:7],
        [subLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightImg.leadingAnchor constant:-12],
        [subLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
    ]];

    if (subtitleOut) *subtitleOut = subLab;
    return card;
}

#pragma mark - Count Refresh

- (void)refreshCounts {
    if (self.isRefreshing) return;
    self.isRefreshing = YES;

    __weak typeof(self) weakSelf = self;
    [[ContactsManager shared] fetchDashboardCounts:^(NSUInteger allCount,
                                                    NSUInteger incompleteCount,
                                                    NSUInteger duplicateCount,
                                                    NSUInteger backupCount,
                                                    NSError * _Nullable error) {
        weakSelf.isRefreshing = NO;

        if (error) {
            weakSelf.subDuplicate.text  = @"0 Duplicate Contacts";
            weakSelf.subIncomplete.text = @"0 Incomplete Contacts";
            weakSelf.subAll.text        = @"0 All Contacts";
            weakSelf.subBackups.text    = [NSString stringWithFormat:@"%lu Backups", (unsigned long)backupCount];
            return;
        }

        weakSelf.subDuplicate.text  = [NSString stringWithFormat:@"%lu Duplicate Contacts", (unsigned long)duplicateCount];
        weakSelf.subIncomplete.text = [NSString stringWithFormat:@"%lu Incomplete Contacts", (unsigned long)incompleteCount];
        weakSelf.subBackups.text    = [NSString stringWithFormat:@"%lu Backups", (unsigned long)backupCount];
        weakSelf.subAll.text        = [NSString stringWithFormat:@"%lu All Contacts", (unsigned long)allCount];
    }];
}

#pragma mark - Actions

- (void)tapDuplicate {
    DuplicateContactsViewController *vc = [DuplicateContactsViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tapIncomplete {
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeIncomplete backupId:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tapBackups {
    BackupContactsViewController *vc = [BackupContactsViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tapAll {
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeDelete backupId:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
