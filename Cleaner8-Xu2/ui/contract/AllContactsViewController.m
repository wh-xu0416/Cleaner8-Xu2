#import "AllContactsViewController.h"
#import "ContactsManager.h"
#import "ASSelectTitleBar.h"
#import <Contacts/Contacts.h>
#import <UIKit/UIKit.h>
#import <ContactsUI/ContactsUI.h>
#import "Common.h"

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat ASScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

#pragma mark - UI Helpers

static inline UIColor *ASACRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASACBlue(void) {      // #024DFFFF
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
}
static inline UIColor *ASACRestoreBlue(void) { // #028BFFFF
    return [UIColor colorWithRed:0x02/255.0 green:0x8B/255.0 blue:0xFF/255.0 alpha:1.0];
}
static inline UIColor *ASACGray666(void) {   // #666666FF
    return [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];
}
static inline UIColor *ASACAvatarBG(void) {  // #D6E7FFFF
    return [UIColor colorWithRed:0xD6/255.0 green:0xE7/255.0 blue:0xFF/255.0 alpha:1.0];
}
static inline UIFont *ASACFont(CGFloat size, UIFontWeight weight) {
    return ASFontS(size, weight);
}

static inline NSString *ASACSectionKeyFromName(NSString *name) {
    if (name.length == 0) return @"#";

    NSString *trim = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trim.length == 0) return @"#";

    NSMutableString *m = [trim mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)m, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)m, NULL, kCFStringTransformStripDiacritics, false);

    NSString *t = [m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return @"#";

    unichar c = [[t uppercaseString] characterAtIndex:0];
    if (c >= 'A' && c <= 'Z') {
        return [NSString stringWithCharacters:&c length:1];
    }
    return @"#";
}

static inline NSString *ASACFirstCharForAvatar(NSString *s) {
    if (s.length == 0) return @"?";
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (![ws characterIsMember:c]) {
            return [[s substringWithRange:NSMakeRange(i, 1)] uppercaseString];
        }
    }
    return @"?";
}

@interface ASACSectionCardFlowLayout : UICollectionViewFlowLayout
@end

@implementation ASACSectionCardFlowLayout
- (instancetype)init {
    if (self = [super init]) {
        self.minimumLineSpacing = AS(10);
        self.minimumInteritemSpacing = AS(10);
        self.sectionInset = ASEdgeInsets(10, 20, 10, 20);
        self.sectionHeadersPinToVisibleBounds = YES;
    }
    return self;
}

@end

#pragma mark - Letter Header (sticky)

@interface ASACLetterHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *label;
- (void)config:(NSString *)title;
@end

@implementation ASACLetterHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;

        self.label = [UILabel new];
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.label.font = ASACFont(17, UIFontWeightSemibold);
        self.label.textColor = UIColor.blackColor;
        self.label.numberOfLines = 1;
        [self addSubview:self.label];

        [NSLayoutConstraint activateConstraints:@[
            [self.label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AS(30)],
            [self.label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-AS(20)],
        ]];
    }
    return self;
}

- (void)config:(NSString *)title {
    self.label.text = title ?: @"";
}

@end

#pragma mark - Contact Item Cell (same as “group item UI”)
@interface ASACContactCell : UICollectionViewCell
@property (nonatomic, copy) void (^onSelectTap)(void);
@property (nonatomic, strong) UIView *avatarView;
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *phoneLabel;
@property (nonatomic, strong) UIButton *selectButton;
- (void)configName:(NSString *)name
             phone:(NSString *)phone
           initial:(NSString *)initial
          selected:(BOOL)selected;
@end

@implementation ASACContactCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = AS(16);
        self.contentView.layer.masksToBounds = YES;

        self.avatarView = [UIView new];
        self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarView.backgroundColor = ASACAvatarBG();
        self.avatarView.layer.cornerRadius = AS(24);
        self.avatarView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.avatarView];

        self.avatarLabel = [UILabel new];
        self.avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarLabel.font = ASACFont(27, UIFontWeightMedium);
        self.avatarLabel.textColor = UIColor.whiteColor;
        self.avatarLabel.textAlignment = NSTextAlignmentCenter;
        [self.avatarView addSubview:self.avatarLabel];

        self.nameLabel = [UILabel new];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.font = ASACFont(20, UIFontWeightSemibold);
        self.nameLabel.textColor = UIColor.blackColor;
        [self.contentView addSubview:self.nameLabel];

        self.phoneLabel = [UILabel new];
        self.phoneLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.phoneLabel.font = ASACFont(12, UIFontWeightRegular);
        self.phoneLabel.textColor = [UIColor colorWithWhite:0 alpha:0.5];
        [self.contentView addSubview:self.phoneLabel];

        self.selectButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectButton.adjustsImageWhenHighlighted = NO;
        self.selectButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.selectButton.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
        [self.selectButton addTarget:self action:@selector(onSelectButtonTap) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.selectButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AS(18)],
            [self.avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.avatarView.widthAnchor constraintEqualToConstant:AS(48)],
            [self.avatarView.heightAnchor constraintEqualToConstant:AS(48)],

            [self.avatarLabel.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
            [self.avatarLabel.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],

            [self.selectButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AS(8)],
            [self.selectButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.selectButton.widthAnchor constraintEqualToConstant:AS(44)],
            [self.selectButton.heightAnchor constraintEqualToConstant:AS(44)],

            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:AS(10)],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectButton.leadingAnchor constant:-AS(10)],
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(11)],

            [self.phoneLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.phoneLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
            [self.phoneLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:AS(4)],
            [self.phoneLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-AS(11)],
        ]];
    }
    return self;
}

- (void)onSelectButtonTap {
    if (self.onSelectTap) self.onSelectTap();
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onSelectTap = nil;
}

- (void)configName:(NSString *)name
             phone:(NSString *)phone
           initial:(NSString *)initial
          selected:(BOOL)selected {

    self.nameLabel.text = name ?: @"";
    self.phoneLabel.text = phone ?: @"";
    self.avatarLabel.text = initial.length ? initial : @"?";

    NSString *iconName = selected ? @"ic_select_s" : @"ic_select_gray_n";
    UIImage *img = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.selectButton setImage:img forState:UIControlStateNormal];
}

@end

#pragma mark - VC

@interface AllContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UILabel *pageTitleLabel;
@property (nonatomic, strong) UILabel *countLabel;

@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImage;
@property (nonatomic, strong) UILabel *emptyTitle;

@property (nonatomic, assign) AllContactsMode mode;
@property (nonatomic, copy) NSString *backupId;

@property (nonatomic, strong) NSMutableArray<CNContact *> *contacts;

@property (nonatomic, strong) NSMutableSet<NSString *> *selectedContactIds;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selectedBackupIndices;

@property (nonatomic, strong) ContactsManager *contactsManager;

@property (nonatomic, strong) CAGradientLayer *topGradient;

@property (nonatomic, strong) ASSelectTitleBar *titleBar;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSNumber *> *> *sectionIndices;

@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *leftButton;
@property (nonatomic, strong) UIButton *rightButton;
@property (nonatomic, assign) BOOL hasContactsAccess;
@end

@implementation AllContactsViewController

- (instancetype)initWithMode:(AllContactsMode)mode backupId:(nullable NSString *)backupId {
    if (self = [super init]) {
        _mode = mode;
        _backupId = backupId ?: @"";
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) return UIStatusBarStyleDarkContent;
    return UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];
    
    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0];
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0];

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    self.hasContactsAccess = (self.mode == AllContactsModeRestore);

    self.contactsManager = [ContactsManager shared];
    self.contacts = [NSMutableArray array];
    self.selectedContactIds = [NSMutableSet set];
    self.selectedBackupIndices = [NSMutableSet set];
    
    [self setupEmptyViewIfNeeded];

    [self setupIncompleteTopTextsIfNeeded];

    [self setupTitleBar];
    [self setupCollectionView];
    [self setupBottomButtons];

    [self loadContacts];
}

- (void)updateEmptyStateIfNeeded {

    BOOL noData = (self.contacts.count == 0);

    BOOL needContactsPermission = (self.mode != AllContactsModeRestore);
    BOOL noPermission = (needContactsPermission && !self.hasContactsAccess);

    BOOL showEmpty = (noData || noPermission);

    self.emptyView.hidden = !showEmpty;
    self.cv.hidden = showEmpty;

    if (noPermission) {
        self.emptyTitle.text = NSLocalizedString(@"No Permission", nil);
        self.emptyImage.image = [UIImage imageNamed:@"ic_no_contact"];
    } else {
        self.emptyTitle.text = NSLocalizedString(@"No Content", nil);
        self.emptyImage.image = [UIImage imageNamed:@"ic_no_contact"];
    }

    if (self.mode == AllContactsModeIncomplete) {
        self.pageTitleLabel.hidden = showEmpty;
        self.countLabel.hidden = showEmpty;

        self.titleBar.showTitle = showEmpty;
        if (showEmpty) [self.titleBar setTitleText:NSLocalizedString(@"Incomplete Contacts", nil)];
    }

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

#pragma mark - Title Bar

- (NSString *)pageTitleText {
    NSString *title = NSLocalizedString(@"All", nil);
    if (self.mode == AllContactsModeBackup) title = NSLocalizedString(@"Backup Contacts", nil);
    if (self.mode == AllContactsModeRestore) title = NSLocalizedString(@"Restore Backup", nil);
    if (self.mode == AllContactsModeIncomplete) title = NSLocalizedString(@"Incomplete Contacts", nil);
    return title;
}

- (void)setupTitleBar {
    __weak typeof(self) weakSelf = self;

    self.titleBar = [[ASSelectTitleBar alloc] initWithTitle:[self pageTitleText]];

    if (self.mode == AllContactsModeIncomplete) {
        self.titleBar.showTitle = NO;
    } else {
        self.titleBar.showTitle = YES;
    }
    self.titleBar.showSelectButton = YES;

    self.titleBar.onBack = ^{ [weakSelf.navigationController popViewControllerAnimated:YES]; };

    self.titleBar.onToggleSelectAll = ^(BOOL __unused allSelected) {
        if (weakSelf.mode == AllContactsModeRestore) {
            if ([weakSelf isAllSelectedInBackup]) [weakSelf deselectAllInBackup];
            else [weakSelf selectAllInBackup];
        } else {
            if ([weakSelf isAllSelectedInSystem]) [weakSelf deselectAllInSystem];
            else [weakSelf selectAllInSystem];
        }
        [weakSelf syncTopSelectState];
        [weakSelf updateBottomState];
        [weakSelf.cv reloadData];
    };

    [self.view addSubview:self.titleBar];
}

- (void)setupIncompleteTopTextsIfNeeded {
    if (self.mode != AllContactsModeIncomplete) return;

    self.pageTitleLabel = [UILabel new];
    self.pageTitleLabel.text = NSLocalizedString(@"Incomplete Contacts", nil);
    self.pageTitleLabel.textColor = UIColor.blackColor;
    self.pageTitleLabel.font = ASACFont(28, UIFontWeightSemibold);
    [self.view addSubview:self.pageTitleLabel];

    self.countLabel = [UILabel new];
    [self.view addSubview:self.countLabel];
}

- (void)updateIncompleteCountLabel {
    if (self.mode != AllContactsModeIncomplete) return;

    NSInteger count = self.contacts.count;
    NSString *num = [NSString stringWithFormat:@"%ld", (long)count];
    NSString *full = [NSString stringWithFormat:NSLocalizedString(@"%@ Contacts", nil), num];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full];
    UIFont *f = ASACFont(16, UIFontWeightMedium);
    [att addAttribute:NSFontAttributeName value:f range:NSMakeRange(0, full.length)];

    NSRange nr = [full rangeOfString:num];
    if (nr.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:ASACBlue() range:nr];       // #024DFF
    }
    NSRange cr = [full rangeOfString:NSLocalizedString(@"Contacts", nil)];
    if (cr.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:ASACGray666() range:cr];    // #666666
    }
    self.countLabel.attributedText = att;
}

- (void)setupEmptyViewIfNeeded {
    if (self.emptyView) return;

    self.emptyView = [UIView new];
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyImage = [UIImageView new];
    self.emptyImage.image = [UIImage imageNamed:@"ic_no_contact"];
    self.emptyImage.contentMode = UIViewContentModeScaleAspectFit;
    [self.emptyView addSubview:self.emptyImage];

    self.emptyTitle = [UILabel new];
    self.emptyTitle.text = NSLocalizedString(@"No Content", nil);
    self.emptyTitle.textColor = UIColor.blackColor;
    self.emptyTitle.font = ASACFont(24, UIFontWeightMedium);
    self.emptyTitle.textAlignment = NSTextAlignmentCenter;
    [self.emptyView addSubview:self.emptyTitle];
}

#pragma mark - Collection

- (void)setupCollectionView {
    ASACSectionCardFlowLayout *layout = [ASACSectionCardFlowLayout new];
    layout.sectionHeadersPinToVisibleBounds = (self.mode != AllContactsModeIncomplete);

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    self.cv.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [self.cv registerClass:[ASACContactCell class] forCellWithReuseIdentifier:@"ASACContactCell"];
    [self.cv registerClass:[ASACLetterHeaderView class]
forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
       withReuseIdentifier:@"ASACLetterHeaderView"];

    [self.view addSubview:self.cv];

    self.cv.contentInset = ASEdgeInsets(20, 0, 0, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;
}

#pragma mark - Bottom Buttons (Duplicate style)

- (UIButton *)buildPillButtonWithTitle:(NSString *)title bg:(UIColor *)bg {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.hidden = YES;
    b.backgroundColor = bg;

    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = ASACFont(20, UIFontWeightRegular);
    b.titleLabel.textAlignment = NSTextAlignmentCenter;

    b.contentEdgeInsets = ASEdgeInsets(22, 22, 22, 22);

    return b;
}

- (void)setupBottomButtons {
    if (self.mode == AllContactsModeRestore) {
        self.leftButton  = [self buildPillButtonWithTitle:NSLocalizedString(@"Delete", nil)  bg:ASACBlue()];
        self.rightButton = [self buildPillButtonWithTitle:NSLocalizedString(@"Restore", nil) bg:ASACRestoreBlue()];
        [self.leftButton addTarget:self action:@selector(onDeleteFromBackup) forControlEvents:UIControlEventTouchUpInside];
        [self.rightButton addTarget:self action:@selector(onRestore) forControlEvents:UIControlEventTouchUpInside];

        [self.view addSubview:self.leftButton];
        [self.view addSubview:self.rightButton];
    } else {
        NSString *t = NSLocalizedString(@"Delete 0 Contacts", nil);
        UIColor *bg = ASACBlue();

        if (self.mode == AllContactsModeBackup) {
            t = NSLocalizedString(@"Backup 0 Contacts", nil);
            bg = ASACBlue();
        }

        self.primaryButton = [self buildPillButtonWithTitle:t bg:bg];
        [self.primaryButton addTarget:self action:@selector(onSingleAction) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.primaryButton];
    }
}

- (void)updatePrimaryButtonTitleIfNeeded {
    if (!self.primaryButton) return;
    if (self.mode == AllContactsModeRestore) return;

    NSUInteger count = self.selectedContactIds.count;

    if (self.mode == AllContactsModeBackup) {
        NSString *t = [NSString stringWithFormat:NSLocalizedString(@"Backup %lu Contacts", nil), (unsigned long)count];
        [self.primaryButton setTitle:t forState:UIControlStateNormal];
        self.primaryButton.backgroundColor = ASACBlue();
        return;
    }

    NSString *t = [NSString stringWithFormat:NSLocalizedString(@"Delete %lu Contacts", nil), (unsigned long)count];
    [self.primaryButton setTitle:t forState:UIControlStateNormal];
    self.primaryButton.backgroundColor = ASACBlue();
}

#pragma mark - Load

- (void)loadContacts {
    __weak typeof(self) weakSelf = self;

    if (self.mode == AllContactsModeRestore) {
        [self.contactsManager fetchContactsInBackupId:self.backupId completion:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error) {
            if (error) { NSLog(@"读取备份失败: %@", error.localizedDescription); return; }

            weakSelf.contacts = [NSMutableArray arrayWithArray:contacts ?: @[]];
            [weakSelf.selectedBackupIndices removeAllObjects];

            [weakSelf rebuildSections];
            [weakSelf.cv reloadData];

            [weakSelf syncTopSelectState];
            [weakSelf updateBottomState];
            [weakSelf updateEmptyStateIfNeeded];
        }];
        return;
    }

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {

        weakSelf.hasContactsAccess = (error == nil);

        if (error) {
            NSLog(@"通讯录权限失败: %@", error.localizedDescription);

            // 保证数据为空
            [weakSelf.contacts removeAllObjects];
            [weakSelf.selectedContactIds removeAllObjects];
            [weakSelf rebuildSections];
            [weakSelf.cv reloadData];

            [weakSelf syncTopSelectState];
            [weakSelf updateBottomState];
            if (weakSelf.mode == AllContactsModeIncomplete) {
                [weakSelf updateIncompleteCountLabel];
            }
            [weakSelf updateEmptyStateIfNeeded];
            return;
        }
        
        // 不完整联系人
        if (weakSelf.mode == AllContactsModeIncomplete) {
            [weakSelf.contactsManager fetchIncompleteContacts:^(NSArray<CNContact *> * _Nullable allIncomplete,
                                                               NSArray<CMIncompleteGroup *> * _Nullable __unused groups,
                                                               NSError * _Nullable error2) {
                if (error2) { NSLog(@"获取不完整联系人失败: %@", error2.localizedDescription); return; }

                weakSelf.contacts = [NSMutableArray arrayWithArray:allIncomplete ?: @[]];
                [weakSelf.selectedContactIds removeAllObjects];

                [weakSelf rebuildSections];
                [weakSelf.cv reloadData];

                [weakSelf syncTopSelectState];
                [weakSelf updateBottomState];
                [weakSelf updateIncompleteCountLabel];
                [weakSelf updateEmptyStateIfNeeded];
                weakSelf.hasContactsAccess = YES;
            }];
            return;
        }

        // 系统全部联系人
        [weakSelf.contactsManager fetchAllContacts:^(NSArray<CNContact *> * _Nullable contacts, NSError * _Nullable error2) {
            if (error2) { NSLog(@"获取联系人失败: %@", error2.localizedDescription); return; }

            weakSelf.contacts = [NSMutableArray arrayWithArray:contacts ?: @[]];
            [weakSelf.selectedContactIds removeAllObjects];

            [weakSelf rebuildSections];
            [weakSelf.cv reloadData];

            [weakSelf syncTopSelectState];
            [weakSelf updateBottomState];
            [weakSelf updateEmptyStateIfNeeded];
            weakSelf.hasContactsAccess = YES;
        }];
    }];
}

#pragma mark - Section Build (A/B/...)

- (NSString *)displayNameForContact:(CNContact *)c {
    NSString *name = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
    if (name.length == 0) name = NSLocalizedString(@"No name", nil);
    return name;
}

- (void)rebuildSections {
    // 不完整联系人：不要首字母分组/吸顶，只做单 section
    if (self.mode == AllContactsModeIncomplete) {
        NSMutableArray<NSNumber *> *idxs = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)self.contacts.count; i++) [idxs addObject:@(i)];

        [idxs sortUsingComparator:^NSComparisonResult(NSNumber *n1, NSNumber *n2) {
            CNContact *c1 = self.contacts[n1.integerValue];
            CNContact *c2 = self.contacts[n2.integerValue];
            NSString *s1 = [self displayNameForContact:c1];
            NSString *s2 = [self displayNameForContact:c2];
            return [s1 localizedCaseInsensitiveCompare:s2];
        }];

        self.sectionTitles = @[@""];
        self.sectionIndices = @[[idxs copy]];
        return;
    }
 
    // buckets: key -> indices
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *dict = [NSMutableDictionary dictionary];

    for (NSInteger i = 0; i < (NSInteger)self.contacts.count; i++) {
        CNContact *c = self.contacts[i];
        NSString *name = [self displayNameForContact:c];
        NSString *k = ASACSectionKeyFromName(name);

        NSMutableArray *arr = dict[k];
        if (!arr) { arr = [NSMutableArray array]; dict[k] = arr; }
        [arr addObject:@(i)];
    }

    // sort keys: A-Z, then #
    NSArray<NSString *> *keys = [dict allKeys];
    keys = [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:@"#"] && ![b isEqualToString:@"#"]) return NSOrderedDescending;
        if (![a isEqualToString:@"#"] && [b isEqualToString:@"#"]) return NSOrderedAscending;
        return [a compare:b options:NSCaseInsensitiveSearch];
    }];

    NSMutableArray *sectionTitles = [NSMutableArray array];
    NSMutableArray *sectionIndices = [NSMutableArray array];

    for (NSString *k in keys) {
        NSMutableArray<NSNumber *> *idxs = dict[k];
        if (idxs.count == 0) continue;

        // sort contacts inside section by display name
        [idxs sortUsingComparator:^NSComparisonResult(NSNumber *n1, NSNumber *n2) {
            CNContact *c1 = self.contacts[n1.integerValue];
            CNContact *c2 = self.contacts[n2.integerValue];
            NSString *s1 = [self displayNameForContact:c1];
            NSString *s2 = [self displayNameForContact:c2];
            return [s1 localizedCaseInsensitiveCompare:s2];
        }];

        [sectionTitles addObject:k];
        [sectionIndices addObject:[idxs copy]];
    }

    self.sectionTitles = [sectionTitles copy];
    self.sectionIndices = [sectionIndices copy];
}

#pragma mark - DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    (void)collectionView;
    return self.sectionTitles.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    return self.sectionIndices[section].count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASACContactCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASACContactCell" forIndexPath:indexPath];

    NSNumber *originIndexNum = self.sectionIndices[indexPath.section][indexPath.item];
    NSInteger originIndex = originIndexNum.integerValue;

    CNContact *c = self.contacts[originIndex];
    NSString *name = [self displayNameForContact:c];

    // phone
    NSString *phone = @"";
    if ([c isKeyAvailable:CNContactPhoneNumbersKey] && c.phoneNumbers.count > 0) {
        // 为了和 Duplicate 一样：拼接全部号码
        NSMutableArray *arr = [NSMutableArray array];
        for (CNLabeledValue<CNPhoneNumber *> *lv in c.phoneNumbers) {
            NSString *p = lv.value.stringValue ?: @"";
            if (p.length > 0) [arr addObject:p];
        }
        phone = [arr componentsJoinedByString:@" · "];
    }
    if (phone.length == 0) phone = NSLocalizedString(@"No phone number", nil);

    BOOL selected = NO;
    if (self.mode == AllContactsModeRestore) {
        selected = [self.selectedBackupIndices containsObject:@(originIndex)];
    } else {
        selected = (c.identifier.length > 0) && [self.selectedContactIds containsObject:c.identifier];
    }

    [cell configName:name phone:phone initial:ASACFirstCharForAvatar(name) selected:selected];

    __weak typeof(self) weakSelf = self;
    cell.onSelectTap = ^{
        [weakSelf toggleSelectionAtOriginalIndex:originIndex];
    };

    return cell;
}

#pragma mark - Header (sticky letter)

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) return [UICollectionReusableView new];

    if (self.mode == AllContactsModeIncomplete) {
        return [UICollectionReusableView new];
    }

    ASACLetterHeaderView *v =
    [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                       withReuseIdentifier:@"ASACLetterHeaderView"
                                              forIndexPath:indexPath];
    [v config:self.sectionTitles[indexPath.section] ?: @""];
    return v;
}

#pragma mark - Layout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
referenceSizeForHeaderInSection:(NSInteger)section {
    (void)collectionViewLayout; (void)section;

    if (self.mode == AllContactsModeIncomplete) {
        return CGSizeZero;
    }
    return CGSizeMake(collectionView.bounds.size.width, AS(24));
}


- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout*)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    (void)collectionView;
    (void)collectionViewLayout;
    (void)section;
    return ASEdgeInsets(10, 20, 10, 20);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    (void)collectionViewLayout;
    (void)indexPath;
    return CGSizeMake(collectionView.bounds.size.width - AS(40), AS(72));
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    (void)collectionView;
    (void)collectionViewLayout;
    (void)section;
    return AS(10);
}

#pragma mark - Tap Select

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    NSNumber *originIndexNum = self.sectionIndices[indexPath.section][indexPath.item];
    NSInteger originIndex = originIndexNum.integerValue;

    [self openSystemPreviewAtOriginalIndex:originIndex];
}

- (void)toggleSelectionAtOriginalIndex:(NSInteger)originIndex {
    if (originIndex < 0 || originIndex >= (NSInteger)self.contacts.count) return;

    if (self.mode == AllContactsModeRestore) {
        NSNumber *k = @(originIndex);
        if ([self.selectedBackupIndices containsObject:k]) [self.selectedBackupIndices removeObject:k];
        else [self.selectedBackupIndices addObject:k];
    } else {
        CNContact *c = self.contacts[originIndex];
        NSString *cid = c.identifier ?: @"";
        if (cid.length == 0) return;

        if ([self.selectedContactIds containsObject:cid]) [self.selectedContactIds removeObject:cid];
        else [self.selectedContactIds addObject:cid];
    }

    [self syncTopSelectState];
    [self updateBottomState];
    [self.cv reloadData];
}

#pragma mark - Select All / Deselect All

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

- (void)deselectAllInSystem { [self.selectedContactIds removeAllObjects]; }

- (BOOL)isAllSelectedInBackup {
    if (self.contacts.count == 0) return NO;
    return self.selectedBackupIndices.count == self.contacts.count;
}

- (void)selectAllInBackup {
    [self.selectedBackupIndices removeAllObjects];
    for (NSInteger i = 0; i < (NSInteger)self.contacts.count; i++) {
        [self.selectedBackupIndices addObject:@(i)];
    }
}
- (void)deselectAllInBackup { [self.selectedBackupIndices removeAllObjects]; }

#pragma mark - Sync Top State / Bottom State

- (void)syncTopSelectState {

    if (self.mode != AllContactsModeIncomplete) {
        [self.titleBar setTitleText:[self pageTitleText]];
        self.titleBar.showTitle = YES;
    } else {
        [self.titleBar setTitleText:[self pageTitleText]];
    }
    
    BOOL hasContacts = (self.contacts.count > 0);
    self.titleBar.showSelectButton = hasContacts;

    if (!hasContacts) {
        self.titleBar.allSelected = NO;
        return;
    }

    self.titleBar.allSelected = (self.mode == AllContactsModeRestore)
        ? [self isAllSelectedInBackup]
        : [self isAllSelectedInSystem];
}

- (void)updateBottomState {
    BOOL hasSelected = NO;

    if (self.mode == AllContactsModeRestore) {
        hasSelected = (self.selectedBackupIndices.count > 0);
        self.leftButton.hidden = !hasSelected;
        self.rightButton.hidden = !hasSelected;
        self.leftButton.enabled = hasSelected;
        self.rightButton.enabled = hasSelected;
    } else {
        hasSelected = (self.selectedContactIds.count > 0);
        self.primaryButton.hidden = !hasSelected;
        self.primaryButton.enabled = hasSelected;

        if (hasSelected) {
            [self updatePrimaryButtonTitleIfNeeded];
        }
    }

    [self.view setNeedsLayout];
}

#pragma mark - Actions (keep your original logic)

- (void)onSingleAction {
    if (self.mode == AllContactsModeBackup) {
        [self doBackupSelected];
    } else if (self.mode == AllContactsModeIncomplete) {
        [self confirmDeleteIncompleteThenRun];
    } else {
        [self confirmDeleteAllContactsWithBackupOption];
    }
}

- (void)confirmDeleteAllContactsWithBackupOption {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;

    NSString *title = NSLocalizedString(@"Would you like to back up your contacts before making any changes?", nil);
    NSString *msg = NSLocalizedString(@"Changes cannot be reversed if you do not back up your contacts.", nil);

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No", nil) style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.primaryButton.enabled = NO;
        weakSelf.primaryButton.alpha = 0.7;
        [weakSelf doDeleteSelectedFromSystem];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Back up", nil) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.primaryButton.enabled = NO;
        weakSelf.primaryButton.alpha = 0.7;
        [weakSelf doBackupThenDeleteSelectedFromSystem];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)doBackupThenDeleteSelectedFromSystem {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *backupName = [NSString stringWithFormat:NSLocalizedString(@"Backup %@", nil), [fmt stringFromDate:[NSDate date]]];

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            weakSelf.primaryButton.enabled = YES;
            weakSelf.primaryButton.alpha = 1.0;
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Unable to access the address book.", nil) message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager backupContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                     backupName:backupName
                                                     completion:^(NSString * _Nullable backupId, NSError * _Nullable error2) {
            (void)backupId;

            if (error2) {
                weakSelf.primaryButton.enabled = YES;
                weakSelf.primaryButton.alpha = 1.0;
                [weakSelf showAlertWithTitle:NSLocalizedString(@"Backup failed.", nil) message:error2.localizedDescription];
                return;
            }

            [[NSNotificationCenter defaultCenter] postNotificationName:@"CMBackupDidFinish" object:nil];

            [weakSelf.contactsManager deleteContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                        completion:^(NSError * _Nullable error3) {
                if (error3) {
                    weakSelf.primaryButton.enabled = YES;
                    weakSelf.primaryButton.alpha = 1.0;
                    [weakSelf showAlertWithTitle:NSLocalizedString(@"Delete failed.", nil) message:error3.localizedDescription];
                    return;
                }

                NSIndexSet *rm = [weakSelf.contacts indexesOfObjectsPassingTest:^BOOL(CNContact *obj, NSUInteger idx, BOOL *stop) {
                    (void)idx; (void)stop;
                    return [weakSelf.selectedContactIds containsObject:obj.identifier];
                }];
                [weakSelf.contacts removeObjectsAtIndexes:rm];
                [weakSelf.selectedContactIds removeAllObjects];

                [weakSelf rebuildSections];
                [weakSelf.cv reloadData];
                [weakSelf syncTopSelectState];
                [weakSelf updateBottomState];
                [weakSelf updateEmptyStateIfNeeded];

                weakSelf.primaryButton.enabled = YES;
                weakSelf.primaryButton.alpha = 1.0;

                BOOL emptyAfter = (weakSelf.contacts.count == 0);
                [weakSelf showDoneThenMaybePopIfEmpty:emptyAfter];
            }];
        }];
    }];
}

- (void)confirmDeleteIncompleteThenRun {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;

    NSString *title = NSLocalizedString(@"Are you sure?", nil);
    NSString *msg = NSLocalizedString(@"All your old contacts will be removed from your iPhone and iCloud. This process cannot be reversed.", nil);

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", nil) style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.primaryButton.enabled = NO;
        weakSelf.primaryButton.alpha = 0.7;
        [weakSelf doDeleteIncompleteSelectedFromSystem];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)doDeleteIncompleteSelectedFromSystem {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Unable to access the address book.", nil) message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager deleteContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                    completion:^(NSError * _Nullable error2) {
            if (error2) {
                [weakSelf showAlertWithTitle:NSLocalizedString(@"Delete failed", nil) message:error2.localizedDescription];
                return;
            }

            NSIndexSet *rm = [weakSelf.contacts indexesOfObjectsPassingTest:^BOOL(CNContact *obj, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                return [weakSelf.selectedContactIds containsObject:obj.identifier];
            }];
            [weakSelf.contacts removeObjectsAtIndexes:rm];

            [weakSelf.selectedContactIds removeAllObjects];

            [weakSelf rebuildSections];
            [weakSelf.cv reloadData];

            [weakSelf syncTopSelectState];
            [weakSelf updateBottomState];

            [weakSelf updateIncompleteCountLabel];
            [weakSelf updateEmptyStateIfNeeded];

            weakSelf.primaryButton.enabled = YES;
            weakSelf.primaryButton.alpha = 1.0;

            BOOL emptyAfter = (weakSelf.contacts.count == 0);
            [weakSelf showDoneThenMaybePopIfEmpty:emptyAfter];
        }];
    }];
}

- (void)doBackupSelected {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *backupName = [NSString stringWithFormat:NSLocalizedString(@"Backup %@", nil), [fmt stringFromDate:[NSDate date]]];

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Unable to access the address book.", nil) message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager backupContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                     backupName:backupName
                                                     completion:^(NSString * _Nullable backupId, NSError * _Nullable error2) {
            (void)backupId;
            if (error2) {
                [weakSelf showAlertWithTitle:NSLocalizedString(@"Backup failed.", nil) message:error2.localizedDescription];
                return;
            }

            [[NSNotificationCenter defaultCenter] postNotificationName:@"CMBackupDidFinish" object:nil];

            [weakSelf showToastText:NSLocalizedString(@"Backup completed", nil)];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf.navigationController popViewControllerAnimated:YES];
            });
        }];
    }];
}

- (void)openSystemPreviewAtOriginalIndex:(NSInteger)originIndex {
    if (originIndex < 0 || originIndex >= (NSInteger)self.contacts.count) return;

    CNContact *c = self.contacts[originIndex];

    CNContactStore *store = [CNContactStore new];
    CNContact *showContact = c;

    if (c.identifier.length > 0) {
        NSError *err = nil;
        showContact = [store unifiedContactWithIdentifier:c.identifier
                                               keysToFetch:@[[CNContactViewController descriptorForRequiredKeys]]
                                                     error:&err] ?: c;
    }

    CNContactViewController *vc = nil;

    if (showContact.identifier.length > 0) {
        vc = [CNContactViewController viewControllerForContact:showContact];
        vc.contactStore = store;
        vc.allowsEditing = NO;
        vc.allowsActions = YES;
    } else {
        vc = [CNContactViewController viewControllerForUnknownContact:showContact];
        vc.contactStore = store;
        vc.allowsEditing = NO;
        vc.allowsActions = YES;
    }

    // Show the navigation bar before pushing the contact view controller
    self.navigationController.navigationBarHidden = NO; // Ensure navigation bar is visible

    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)doDeleteSelectedFromSystem {
    if (self.selectedContactIds.count == 0) return;

    __weak typeof(self) weakSelf = self;
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Unable to access the address book.", nil) message:error.localizedDescription];
            return;
        }

        [weakSelf.contactsManager deleteContactsWithIdentifiers:weakSelf.selectedContactIds.allObjects
                                                    completion:^(NSError * _Nullable error2) {
            if (error2) {
                [weakSelf showAlertWithTitle:NSLocalizedString(@"Delete failed.", nil) message:error2.localizedDescription];
                return;
            }

            NSIndexSet *rm = [weakSelf.contacts indexesOfObjectsPassingTest:^BOOL(CNContact *obj, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                return [weakSelf.selectedContactIds containsObject:obj.identifier];
            }];
            [weakSelf.contacts removeObjectsAtIndexes:rm];

            [weakSelf.selectedContactIds removeAllObjects];

            [weakSelf rebuildSections];
            [weakSelf.cv reloadData];

            [weakSelf syncTopSelectState];
            [weakSelf updateBottomState];
            [weakSelf updateEmptyStateIfNeeded];

            weakSelf.primaryButton.enabled = YES;
            weakSelf.primaryButton.alpha = 1.0;

            BOOL emptyAfter = (weakSelf.contacts.count == 0);
            [weakSelf showDoneThenMaybePopIfEmpty:emptyAfter];
        }];
    }];
}

- (void)onRestore {
    if (self.selectedBackupIndices.count == 0) return;

    __weak typeof(self) weakSelf = self;
    NSArray<NSNumber *> *indices = self.selectedBackupIndices.allObjects;

    [self.contactsManager restoreContactsOverwriteAllFromBackupId:self.backupId
                                         contactIndicesInBackup:indices
                                                     completion:^(NSError * _Nullable error) {
        if (error) {
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Failed to Resotre", nil) message:error.localizedDescription];
            return;
        }

        [weakSelf.selectedBackupIndices removeAllObjects];
        [weakSelf syncTopSelectState];
        [weakSelf updateBottomState];
        [weakSelf.cv reloadData];

        [weakSelf showToastText:NSLocalizedString(@"Restore Complete", nil)];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
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
            [weakSelf showAlertWithTitle:NSLocalizedString(@"Delete failed", nil) message:error.localizedDescription];
            return;
        }

        NSMutableIndexSet *rm = [NSMutableIndexSet indexSet];
        for (NSNumber *n in indices) {
            NSInteger i = n.integerValue;
            if (i >= 0 && i < (NSInteger)weakSelf.contacts.count) [rm addIndex:(NSUInteger)i];
        }
        [weakSelf.contacts removeObjectsAtIndexes:rm];

        [weakSelf.selectedBackupIndices removeAllObjects];

        [weakSelf rebuildSections];
        [weakSelf.cv reloadData];

        [weakSelf syncTopSelectState];
        [weakSelf updateBottomState];
        [weakSelf updateEmptyStateIfNeeded];

        if (weakSelf.contacts.count == 0) {
            BOOL emptyAfter = (weakSelf.contacts.count == 0);
            [weakSelf showDoneThenMaybePopIfEmpty:emptyAfter];
            return;
        }

        BOOL emptyAfter = (weakSelf.contacts.count == 0);
        [weakSelf showDoneThenMaybePopIfEmpty:emptyAfter];
    }];
}

#pragma mark - Done + Maybe Pop

- (void)showDoneThenMaybePopIfEmpty:(BOOL)isEmptyAfterDelete {
    [self showToastDone];

    if (!isEmptyAfterDelete) return;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    });
}

#pragma mark - Toast

- (void)showToastText:(NSString *)text {
    UIView *host = self.view.window ?: self.view;
    if (!host) return;

    NSInteger tag = 909090;
    UIView *old = [host viewWithTag:tag];
    if (old) [old removeFromSuperview];

    UILabel *lab = [UILabel new];
    lab.text = text ?: @"";
    lab.textColor = UIColor.whiteColor;
    lab.font = ASACFont(16, UIFontWeightMedium);
    lab.textAlignment = NSTextAlignmentCenter;
    lab.numberOfLines = 1;

    UIView *toast = [UIView new];
    toast.tag = tag;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
    toast.layer.cornerRadius = AS(12);
    toast.layer.masksToBounds = YES;

    [toast addSubview:lab];
    [host addSubview:toast];

    CGFloat maxW = host.bounds.size.width - AS(80);
    CGSize textSize = [lab sizeThatFits:CGSizeMake(maxW, 999)];
    CGFloat padX = AS(22), padY = AS(12);

    CGFloat w = MIN(maxW, textSize.width) + padX * 2;
    CGFloat h = textSize.height + padY * 2;

    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = host.safeAreaInsets.bottom;

    CGFloat x = (host.bounds.size.width - w) * 0.5;
    CGFloat y = host.bounds.size.height - safeBottom - h - AS(110);
    toast.frame = CGRectMake(x, y, w, h);
    lab.frame = CGRectMake(padX, padY, w - padX * 2, h - padY * 2);

    toast.alpha = 0.0;
    toast.transform = CGAffineTransformMakeScale(0.98, 0.98);

    [UIView animateWithDuration:0.18 animations:^{
        toast.alpha = 1.0;
        toast.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.18 animations:^{
                toast.alpha = 0.0;
            } completion:^(__unused BOOL finished2) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

- (void)showToastDone {
    [self showToastText:@"Done!"];
}

#pragma mark - Alerts

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showAlertPopBackWithTitle:(NSString *)title message:(NSString *)message {
    __weak typeof(self) weakSelf = self;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;

    CGFloat gradientH = AS(402.0);
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    CGFloat navH = AS(44) + safeTop;
    self.titleBar.frame = CGRectMake(0, 0, W, navH);

    CGFloat pagePad = AS(20.0);
    CGFloat btnH = AS(64);
    CGFloat btnY = H - safeBottom - btnH;

    BOOL showBottom = NO;
    if (self.mode == AllContactsModeRestore) {
        showBottom = (self.selectedBackupIndices.count > 0);
        if (showBottom) {
            CGFloat gap = AS(20.0);
            CGFloat eachW = (W - pagePad*2 - gap) / 2.0;
            self.leftButton.frame = CGRectMake(pagePad, btnY, eachW, btnH);
            self.rightButton.frame = CGRectMake(pagePad + eachW + gap, btnY, eachW, btnH);
            self.leftButton.layer.cornerRadius  = btnH * 0.5;
            self.rightButton.layer.cornerRadius = btnH * 0.5;
        }
    } else {
        showBottom = (self.selectedContactIds.count > 0);
        if (showBottom) {
            self.primaryButton.frame = CGRectMake(pagePad, btnY, W - pagePad*2, btnH);
            self.primaryButton.layer.cornerRadius = btnH * 0.5;
        }
    }

    CGFloat extraBottom = showBottom ? (btnH + AS(20.0)) : AS(20.0);

    if (self.mode == AllContactsModeIncomplete) {
        CGFloat x = AS(20.0);

        CGFloat y = navH + AS(16);
        self.pageTitleLabel.frame = CGRectMake(x, y, W - x*2, AS(34));
        y += AS(34) + AS(10);
        
        self.countLabel.frame = CGRectMake(x, y, W - x*2, AS(20));
        y += AS(20) + AS(20);
        
        CGFloat listY = y;

        self.cv.frame = CGRectMake(0, listY, W, H - listY);
        self.cv.contentInset = ASEdgeInsets(0, 0, safeBottom + extraBottom, 0);
        self.cv.scrollIndicatorInsets = self.cv.contentInset;

        CGFloat emptyH = H - navH - safeBottom - extraBottom;
        self.emptyView.frame = CGRectMake(0, listY, W, H - listY - (btnH + safeBottom));

        if (!self.emptyView.hidden) {
            CGSize img = CGSizeMake(AS(182), AS(168));
            CGFloat centerY = self.emptyView.bounds.size.height * 0.5;

            CGFloat imgY = centerY - img.height * 0.5 - AS(60);
            self.emptyImage.frame = CGRectMake((W - img.width) * 0.5,
                                               imgY,
                                               img.width,
                                               img.height);

            CGFloat titleY = CGRectGetMaxY(self.emptyImage.frame) + AS(2);
            self.emptyTitle.frame = CGRectMake(AS(20),
                                               titleY,
                                               W - AS(40),
                                               AS(40));
        }

        return;
    }

    CGFloat listY = navH;
    self.cv.frame = CGRectMake(0, listY, W, H - listY);

    CGFloat emptyH = H - navH - safeBottom - extraBottom;
    self.emptyView.frame = CGRectMake(0, listY, W, H - listY - (btnH + safeBottom));

    if (!self.emptyView.hidden) {
        CGSize img = CGSizeMake(AS(182), AS(168));
        CGFloat centerY = self.emptyView.bounds.size.height * 0.5;

        CGFloat imgY = centerY - img.height * 0.5 - AS(60);
        self.emptyImage.frame = CGRectMake((W - img.width) * 0.5,
                                           imgY,
                                           img.width,
                                           img.height);

        CGFloat titleY = CGRectGetMaxY(self.emptyImage.frame) + AS(2);
        self.emptyTitle.frame = CGRectMake(AS(20),
                                           titleY,
                                           W - AS(40),
                                           AS(40));
    }

    UIEdgeInsets insets = self.cv.contentInset;
    insets.top = AS(20.0);
    insets.bottom = safeBottom + extraBottom;
    self.cv.contentInset = insets;
    self.cv.scrollIndicatorInsets = insets;
}

@end
