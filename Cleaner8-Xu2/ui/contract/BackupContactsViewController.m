#import "BackupContactsViewController.h"
#import "ContactsManager.h"
#import "AllContactsViewController.h"
#import "ASSelectTitleBar.h"
#import "Common.h"
#import <UIKit/UIKit.h>
#import "UIViewController+ASPrivateBackground.h"
#import "PaywallPresenter.h"
#import "ASReviewHelper.h"

#pragma mark - UI Helpers

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

static inline UIColor *ASACRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASACBlue(void) {
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
}
static inline UIColor *ASACGray666(void) {
    return [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];
}

static inline UIFont *ASACFont(CGFloat size, UIFontWeight weight) {
    return ASFontS(size, weight);
}

#pragma mark - Cell

@interface ASBackupInfoCell : UICollectionViewCell
@property (nonatomic, copy) void (^onSelectTap)(void);

@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UIButton *selectButton;

- (void)configDateText:(NSString *)dateText
               subText:(NSString *)subText
              selected:(BOOL)selected;
@end

@implementation ASBackupInfoCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = AS(16);
        self.contentView.layer.masksToBounds = YES;

        self.dateLabel = [UILabel new];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = ASACFont(24, UIFontWeightMedium);
        self.dateLabel.textColor = UIColor.blackColor;
        self.dateLabel.numberOfLines = 1;
        [self.contentView addSubview:self.dateLabel];

        self.subLabel = [UILabel new];
        self.subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subLabel.font = ASACFont(17, UIFontWeightRegular);
        self.subLabel.textColor = ASACGray666();
        self.subLabel.numberOfLines = 1;
        [self.contentView addSubview:self.subLabel];

        self.selectButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectButton.adjustsImageWhenHighlighted = NO;
        self.selectButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.selectButton.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
        self.selectButton.exclusiveTouch = YES;
        [self.selectButton addTarget:self action:@selector(onSelectButtonTap) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.selectButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AS(20)],
            [self.dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectButton.leadingAnchor constant:-AS(12)],
            [self.dateLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(18)],

            [self.subLabel.leadingAnchor constraintEqualToAnchor:self.dateLabel.leadingAnchor],
            [self.subLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.dateLabel.trailingAnchor],
            [self.subLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-AS(18)],
            [self.subLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.dateLabel.bottomAnchor constant:AS(7)],

            [self.selectButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AS(20)],
            [self.selectButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.selectButton.widthAnchor constraintEqualToConstant:AS(44)],
            [self.selectButton.heightAnchor constraintEqualToConstant:AS(44)],
        ]];
    }
    return self;
}

- (void)updateSelectedState:(BOOL)selected {
    NSString *iconName = selected ? @"ic_select_s" : @"ic_select_gray_n";
    UIImage *img = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

    [UIView performWithoutAnimation:^{
        [self.selectButton setImage:img forState:UIControlStateNormal];
        [self.selectButton layoutIfNeeded];
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onSelectTap = nil;
}

- (void)onSelectButtonTap {
    if (self.onSelectTap) self.onSelectTap();
}

- (void)configDateText:(NSString *)dateText
               subText:(NSString *)subText
              selected:(BOOL)selected {
    self.dateLabel.text = dateText ?: @"";
    self.subLabel.text = subText ?: @"";
    [self updateSelectedState:selected];
}

@end

#pragma mark - VC

@interface BackupContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) ContactsManager *contactsManager;
@property (nonatomic, strong) NSArray<CMBackupInfo *> *backups;

@property (nonatomic, strong) ASSelectTitleBar *titleBar;

@property (nonatomic, strong) UICollectionView *cv;

@property (nonatomic, strong) UIButton *addBackupsButton;

@property (nonatomic, strong) NSMutableSet<NSString *> *selectedBackupIds;

@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImage;
@property (nonatomic, strong) UILabel *emptyTitle;

@end

@implementation BackupContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self as_applyPrivateBackground];

    self.contactsManager = [ContactsManager shared];
    self.backups = @[];
    self.selectedBackupIds = [NSMutableSet set];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onBackupDidFinish)
                                                 name:@"CMBackupDidFinish"
                                               object:nil];

    [self setupTitleBar];
    [self setupCollectionView];
    [self setupBottomButton];
    [self setupEmptyView];

    [self loadBackups];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [self loadBackups];
}

- (void)onBackupDidFinish {
    [self loadBackups];
}

- (void)setupTitleBar {
    __weak typeof(self) weakSelf = self;

    self.titleBar = [[ASSelectTitleBar alloc] initWithTitle:NSLocalizedString(@"Backups", nil)];
    self.titleBar.showTitle = YES;
    self.titleBar.showSelectButton = YES;
    self.titleBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    
    self.titleBar.onToggleSelectAll = ^(BOOL __unused allSelected) {
        if ([weakSelf isAllSelectedInBackups]) {
            [weakSelf deselectAllBackups];
        } else {
            [weakSelf selectAllBackups];
        }
        [weakSelf syncTopSelectState];
        [weakSelf updateBottomButtonState];

        [UIView performWithoutAnimation:^{
            [weakSelf.cv reloadData];
        }];
    };

    [self.view addSubview:self.titleBar];
}

- (void)updateBottomButtonState {
    NSUInteger n = self.selectedBackupIds.count;
    if (n == 0) {
        [self.addBackupsButton setTitle:NSLocalizedString(@"Add Backups", nil) forState:UIControlStateNormal];
    } else {
        NSString *t = [NSString stringWithFormat:NSLocalizedString(@"Delete %lu Backups", nil), (unsigned long)n];
        [self.addBackupsButton setTitle:t forState:UIControlStateNormal];
    }
}

- (NSSet<NSString *> *)allBackupIdsSet {
    NSMutableSet *set = [NSMutableSet set];
    for (CMBackupInfo *i in self.backups) {
        if (i.backupId.length) [set addObject:i.backupId];
    }
    return set;
}

- (BOOL)isAllSelectedInBackups {
    NSSet *all = [self allBackupIdsSet];
    return (all.count > 0) && (self.selectedBackupIds.count == all.count);
}

- (void)selectAllBackups {
    [self.selectedBackupIds removeAllObjects];
    [self.selectedBackupIds unionSet:[self allBackupIdsSet]];
}

- (void)deselectAllBackups {
    [self.selectedBackupIds removeAllObjects];
}

- (void)syncTopSelectState {
    BOOL hasBackups = (self.backups.count > 0);
    self.titleBar.showSelectButton = hasBackups;
    self.titleBar.allSelected = hasBackups ? [self isAllSelectedInBackups] : NO;
}

- (void)setupCollectionView {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = AS(10);
    layout.minimumInteritemSpacing = AS(10);
    layout.sectionInset = ASEdgeInsets(10, 20, 10, 20);
    
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    self.cv.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [self.cv registerClass:[ASBackupInfoCell class] forCellWithReuseIdentifier:@"ASBackupInfoCell"];
    [self.view addSubview:self.cv];

    self.cv.contentInset = ASEdgeInsets(20, 0, 0, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;
}

- (UIButton *)buildPillButtonWithTitle:(NSString *)title bg:(UIColor *)bg {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = bg;
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = ASACFont(20, UIFontWeightRegular);
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.contentEdgeInsets = ASEdgeInsets(22, 22, 22, 22);
    return b;
}

- (void)setupBottomButton {
    self.addBackupsButton = [self buildPillButtonWithTitle:NSLocalizedString(@"Add Backups", nil) bg:ASACBlue()];
    [self.addBackupsButton addTarget:self action:@selector(onBottomButtonTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.addBackupsButton];
}

- (void)onBottomButtonTap {
    if (self.selectedBackupIds.count == 0) {
        [self onAddBackups];
        return;
    }
    
    if (![PaywallPresenter shared].isProActive) {
        [[PaywallPresenter shared] showSubscriptionPageWithSource:@"contact"];
        return;
    }
    [self confirmDeleteSelectedBackups];
}

- (void)confirmDeleteSelectedBackups {
    NSUInteger n = self.selectedBackupIds.count;
    if (n == 0) return;

    __weak typeof(self) weakSelf = self;
    NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete %lu backups?", nil), (unsigned long)n];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Backups", nil)
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil) style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction * _Nonnull action) {

        NSArray<NSString *> *ids = weakSelf.selectedBackupIds.allObjects;
        [weakSelf.contactsManager deleteBackupsWithIds:ids completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"delete backups failed: %@", error.localizedDescription);
                return;
            }
            [ASReviewHelper requestReviewOnceFromViewController:self source:AppConstants.abKeyPaidRateRate];
            [weakSelf.selectedBackupIds removeAllObjects];
            [weakSelf loadBackups]; 
        }];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)setupEmptyView {
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
    self.emptyTitle.numberOfLines = 1;
    [self.emptyView addSubview:self.emptyTitle];
}

#pragma mark - Data

- (void)onAddBackups {
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeBackup backupId:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)loadBackups {
    __weak typeof(self) weakSelf = self;
    [self.contactsManager fetchBackupList:^(NSArray<CMBackupInfo *> * _Nullable backups, NSError * _Nullable error) {
        if (error) {
            weakSelf.backups = @[];
            [weakSelf.selectedBackupIds removeAllObjects];
            [weakSelf.cv reloadData];
            [weakSelf updateEmptyState];
            [weakSelf syncTopSelectState];
            [weakSelf updateBottomButtonState];
            return;
        }
        weakSelf.backups = backups ?: @[];
        NSMutableSet *valid = [NSMutableSet set];
        for (CMBackupInfo *i in weakSelf.backups) {
            if (i.backupId.length) [valid addObject:i.backupId];
        }
        [weakSelf.selectedBackupIds intersectSet:valid];

        [weakSelf.cv reloadData];
        [weakSelf updateEmptyState];
        [weakSelf syncTopSelectState];
        [weakSelf updateBottomButtonState];
    }];
}

- (void)updateEmptyState {
    BOOL empty = (self.backups.count == 0);
    self.cv.hidden = empty;
    self.emptyView.hidden = !empty;

    self.addBackupsButton.hidden = NO;
    self.addBackupsButton.enabled = YES;
    self.addBackupsButton.alpha = 1.0;
    [self syncTopSelectState];
    [self updateBottomButtonState];
}

#pragma mark - Format

- (NSString *)dateStringForBackup:(CMBackupInfo *)info {
    NSDate *d = info.date ?: [NSDate date];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"MMM dd,yyyy"; // Dec 24,2025
    return [fmt stringFromDate:d];
}

- (NSString *)timeStringForBackup:(CMBackupInfo *)info {
    NSDate *d = info.date ?: [NSDate date];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"h:mma";       // 10:10AM
    return [[fmt stringFromDate:d] lowercaseString]; // 10:10am
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView; (void)section;
    return self.backups.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASBackupInfoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASBackupInfoCell" forIndexPath:indexPath];

    CMBackupInfo *info = self.backups[indexPath.item];
    NSString *dateText = [self dateStringForBackup:info];

    NSString *timeText = [self timeStringForBackup:info];
    NSString *subText = [NSString stringWithFormat:NSLocalizedString(@"%lu Contacts | %@", nil), (unsigned long)info.count, timeText];

    BOOL selected = (info.backupId.length > 0) && [self.selectedBackupIds containsObject:info.backupId];
    [cell configDateText:dateText subText:subText selected:selected];

    __weak typeof(self) weakSelf = self;
    __weak typeof(cell) weakCell = cell;

    cell.onSelectTap = ^{
        __strong typeof(weakSelf) self2 = weakSelf;
        if (!self2) return;

        NSIndexPath *ip = [self2.cv indexPathForCell:weakCell];
        if (!ip || ip.item >= self2.backups.count) return;

        CMBackupInfo *info2 = self2.backups[ip.item];
        if (info2.backupId.length == 0) return;

        BOOL nowSelected = NO;
        if ([self2.selectedBackupIds containsObject:info2.backupId]) {
            [self2.selectedBackupIds removeObject:info2.backupId];
            nowSelected = NO;
        } else {
            [self2.selectedBackupIds addObject:info2.backupId];
            nowSelected = YES;
        }

        ASBackupInfoCell *visibleCell = (ASBackupInfoCell *)[self2.cv cellForItemAtIndexPath:ip];
        [visibleCell updateSelectedState:nowSelected];

        [self2 syncTopSelectState];
        [self2 updateBottomButtonState];
    };

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    CMBackupInfo *info = self.backups[indexPath.item];
    AllContactsViewController *vc =
    [[AllContactsViewController alloc] initWithMode:AllContactsModeRestore backupId:info.backupId];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - FlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    (void)collectionViewLayout; (void)indexPath;
    CGFloat w = collectionView.bounds.size.width - AS(40);
    return CGSizeMake(w, AS(84));
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    CGFloat navH = AS(44) + safeTop;
    self.titleBar.frame = CGRectMake(0, 0, W, navH);

    CGFloat pagePad = AS(20.0);
    CGFloat btnH = AS(64);
    CGFloat btnY = H - safeBottom - btnH;
    self.addBackupsButton.frame = CGRectMake(pagePad, btnY, W - pagePad * 2, btnH);
    self.addBackupsButton.layer.cornerRadius = btnH * 0.5;

    CGFloat listY = navH;
    self.cv.frame = CGRectMake(0, listY, W, H - listY);

    UIEdgeInsets insets = self.cv.contentInset;
    insets.top = AS(20.0);
    insets.bottom = safeBottom + btnH + AS(20.0);
    self.cv.contentInset = insets;
    self.cv.scrollIndicatorInsets = insets;

    self.emptyView.frame = CGRectMake(0, listY, W, H - listY - (btnH + safeBottom));

    if (!self.emptyView.hidden) {
        CGSize img = CGSizeMake(AS(182), AS(168));
        CGFloat centerY = self.emptyView.bounds.size.height * 0.5;

        CGFloat imgY = centerY - img.height * 0.5 - AS(18);
        self.emptyImage.frame = CGRectMake((W - img.width) * 0.5,
                                           imgY,
                                           img.width,
                                           img.height);

        CGFloat titleY = CGRectGetMaxY(self.emptyImage.frame) + AS(2);
        self.emptyTitle.frame = CGRectMake(AS(20), titleY, W - AS(40), AS(30));
    }
}

@end
