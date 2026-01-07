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

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFFFF
}
static inline UIColor *ASAccent(void) {
    return ASRGB(9, 255, 243); // #09FFF3FF
}

@interface ASContactsViewController ()
@property (nonatomic, strong) UIStackView *cardsStack;

@property (nonatomic, strong) UIControl *permissionBanner;   // limited 权限提示条
@property (nonatomic, strong) UIView *noAuthView;            // 无权限占位

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
    CNAuthorizationStatus status = [self currentContactsAuthStatus];
    if (status == CNAuthorizationStatusNotDetermined) {
        [self requestContactsPermissionIfNeeded];
    } else {
        [self applyContactsAuthStatus:status];
    }
    
    [self scheduleRefreshCounts];
    [self requestContactsPermissionIfNeeded];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASRGB(246, 248, 251);
    self.contactStore = [CNContactStore new];

    [self buildBackground];
    [self setupNavBar];
    [self buildCards];
    [self buildNoAuthPlaceholder];

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

    [self applyContactsAuthStatusIfDetermined];
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
    if (!self.isViewLoaded || self.view.window == nil) return;

    CNAuthorizationStatus status = [self currentContactsAuthStatus];

    BOOL deniedOrRestricted = (status == CNAuthorizationStatusDenied ||
                              status == CNAuthorizationStatusRestricted);

    if (deniedOrRestricted || status == CNAuthorizationStatusNotDetermined) return;

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

- (CNAuthorizationStatus)currentContactsAuthStatus {
    return [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
}

// iOS 18+ 才有 Contacts Limited（如果你项目 SDK 没到 iOS 18，这段不会编译进来）
- (BOOL)isContactsLimitedStatus:(CNAuthorizationStatus)status {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
    if (@available(iOS 18.0, *)) {
        return status == CNAuthorizationStatusLimited;
    }
#endif
    return NO;
}

- (void)applyContactsAuthStatusIfDetermined {
    CNAuthorizationStatus status = [self currentContactsAuthStatus];
    if (status != CNAuthorizationStatusNotDetermined) {
        [self applyContactsAuthStatus:status];
    }
}

- (void)applyContactsAuthStatus:(CNAuthorizationStatus)status {
    BOOL deniedOrRestricted = (status == CNAuthorizationStatusDenied ||
                              status == CNAuthorizationStatusRestricted);
    BOOL limited = (!deniedOrRestricted && [self isContactsLimitedStatus:status]);

    self.noAuthView.hidden = !deniedOrRestricted;
    self.cardsStack.hidden = deniedOrRestricted;
    self.permissionBanner.hidden = !limited;

    if (!deniedOrRestricted && status != CNAuthorizationStatusNotDetermined) {
        [self scheduleRefreshCounts];
    }

    [UIView performWithoutAnimation:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)requestContactsPermissionIfNeeded {
    CNAuthorizationStatus status = [self currentContactsAuthStatus];

    switch (status) {
        case CNAuthorizationStatusAuthorized: {
            [self applyContactsAuthStatus:status];
        } break;

        case CNAuthorizationStatusNotDetermined: {
            __weak typeof(self) weakSelf = self;
            [self.contactStore requestAccessForEntityType:CNEntityTypeContacts
                                       completionHandler:^(BOOL granted, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    CNAuthorizationStatus newStatus = [weakSelf currentContactsAuthStatus];
                    [weakSelf applyContactsAuthStatus:newStatus];
                });
            }];
        } break;

        case CNAuthorizationStatusDenied:
        case CNAuthorizationStatusRestricted: {
            [self applyContactsAuthStatus:status];
        } break;

        default: {
            [self applyContactsAuthStatus:status];
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

    self.permissionBanner = [self buildContactsPermissionBanner];
    self.permissionBanner.hidden = YES;

    self.cardsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.cardDuplicate,
        self.cardIncomplete,
        self.cardBackups,
        self.cardAll,
        self.permissionBanner
    ]];
    self.cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardsStack.axis = UILayoutConstraintAxisVertical;
    self.cardsStack.alignment = UIStackViewAlignmentFill;
    self.cardsStack.distribution = UIStackViewDistributionFill;
    self.cardsStack.spacing = 20;

    [self.view addSubview:self.cardsStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.cardsStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.cardsStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.cardsStack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:88],
        [self.cardsStack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-24],
    ]];
}

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
        [rightImg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [rightImg.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [rightImg.widthAnchor constraintEqualToConstant:40],
        [rightImg.heightAnchor constraintEqualToConstant:24],

        [titleLab.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLab.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [titleLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightImg.leadingAnchor constant:-12],

        [subLab.leadingAnchor constraintEqualToAnchor:titleLab.leadingAnchor],
        [subLab.topAnchor constraintEqualToAnchor:titleLab.bottomAnchor constant:7],
        [subLab.trailingAnchor constraintLessThanOrEqualToAnchor:rightImg.leadingAnchor constant:-12],
        [subLab.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
    ]];

    if (subtitleOut) *subtitleOut = subLab;
    return card;
}

- (UIControl *)buildContactsPermissionBanner {
    UIControl *bar = [UIControl new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = ASBlue(); // #024DFFFF
    bar.layer.cornerRadius = 20;
    bar.layer.masksToBounds = YES;
    [bar addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

    UILabel *tip = [UILabel new];
    tip.translatesAutoresizingMaskIntoConstraints = NO;
    tip.text = @"Contacts Access Is Limited.";
    tip.textColor = UIColor.whiteColor;
    tip.font = ASFont(15, UIFontWeightMedium);
    [bar addSubview:tip];

    UILabel *settingTextLab = [UILabel new];
    settingTextLab.translatesAutoresizingMaskIntoConstraints = NO;
    settingTextLab.text = @"Setting";
    settingTextLab.textColor = ASAccent();
    settingTextLab.font = ASFont(15, UIFontWeightMedium);

    UIImageView *moreIcon = [UIImageView new];
    moreIcon.translatesAutoresizingMaskIntoConstraints = NO;
    moreIcon.image = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    moreIcon.tintColor = ASAccent();
    moreIcon.contentMode = UIViewContentModeScaleAspectFit;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[settingTextLab, moreIcon]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisHorizontal;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.spacing = 10;
    [bar addSubview:rightStack];

    [tip setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                        forAxis:UILayoutConstraintAxisHorizontal];
    [tip setContentHuggingPriority:UILayoutPriorityDefaultLow
                           forAxis:UILayoutConstraintAxisHorizontal];

    [rightStack setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                forAxis:UILayoutConstraintAxisHorizontal];
    [rightStack setContentHuggingPriority:UILayoutPriorityRequired
                                  forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [tip.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:20],
        [tip.topAnchor constraintEqualToAnchor:bar.topAnchor constant:16],
        [tip.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-16],
        [tip.trailingAnchor constraintLessThanOrEqualToAnchor:rightStack.leadingAnchor constant:-12],

        [rightStack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-20],
        [rightStack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [moreIcon.widthAnchor constraintEqualToConstant:16],
        [moreIcon.heightAnchor constraintEqualToConstant:16],
    ]];

    return bar;
}

- (void)buildNoAuthPlaceholder {
    self.noAuthView = [UIView new];
    self.noAuthView.translatesAutoresizingMaskIntoConstraints = NO;
    self.noAuthView.backgroundColor = UIColor.clearColor;
    self.noAuthView.hidden = YES;
    [self.view addSubview:self.noAuthView];

    UIImageView *img = [UIImageView new];
    img.translatesAutoresizingMaskIntoConstraints = NO;
    img.image = [UIImage imageNamed:@"ic_no_contact"];
    img.contentMode = UIViewContentModeScaleAspectFit;
    [self.noAuthView addSubview:img];

    UILabel *t1 = [UILabel new];
    t1.translatesAutoresizingMaskIntoConstraints = NO;
    t1.text = @"Allow Contacts Access";
    t1.textColor = UIColor.blackColor;
    t1.font = ASFont(20, UIFontWeightMedium);
    t1.textAlignment = NSTextAlignmentCenter;
    [self.noAuthView addSubview:t1];

    UILabel *t2 = [UILabel new];
    t2.translatesAutoresizingMaskIntoConstraints = NO;
    t2.text = @"To manage duplicates, incomplete contacts,\nand backups, please allow access to your contacts.";
    t2.textColor = ASRGB(102, 102, 102);
    t2.font = ASFont(13, UIFontWeightRegular);
    t2.numberOfLines = 0;
    t2.textAlignment = NSTextAlignmentCenter;
    [self.noAuthView addSubview:t2];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = ASBlue();
    btn.layer.cornerRadius = 35;
    btn.layer.masksToBounds = YES;
    [btn setTitle:@"Go to Settings" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = ASFont(20, UIFontWeightRegular);
    btn.contentEdgeInsets = UIEdgeInsetsMake(23, 0, 23, 0);
    [btn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.noAuthView addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [self.noAuthView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.noAuthView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.noAuthView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.noAuthView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [img.topAnchor constraintEqualToAnchor:self.noAuthView.topAnchor],
        [img.centerXAnchor constraintEqualToAnchor:self.noAuthView.centerXAnchor],
        [img.widthAnchor constraintEqualToConstant:96],
        [img.heightAnchor constraintEqualToConstant:96],

        [t1.topAnchor constraintEqualToAnchor:img.bottomAnchor constant:20],
        [t1.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:30],
        [t1.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-30],

        [t2.topAnchor constraintEqualToAnchor:t1.bottomAnchor constant:10],
        [t2.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:45],
        [t2.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-45],

        [btn.topAnchor constraintEqualToAnchor:t2.bottomAnchor constant:60],
        [btn.leadingAnchor constraintEqualToAnchor:self.noAuthView.leadingAnchor constant:45],
        [btn.trailingAnchor constraintEqualToAnchor:self.noAuthView.trailingAnchor constant:-45],
        [btn.bottomAnchor constraintEqualToAnchor:self.noAuthView.bottomAnchor],
    ]];
}


#pragma mark - Count Refresh

- (void)refreshCounts {
    CNAuthorizationStatus status = [self currentContactsAuthStatus];
    BOOL deniedOrRestricted = (status == CNAuthorizationStatusDenied ||
                              status == CNAuthorizationStatusRestricted);
    if (deniedOrRestricted || status == CNAuthorizationStatusNotDetermined) return;

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

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

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
