#import "DuplicateContactsViewController.h"
#import "ContactsManager.h"
#import "ASSelectTitleBar.h"
#import <Contacts/Contacts.h>
#import <UIKit/UIKit.h>

#pragma mark - UI Helpers

static inline UIColor *ASDCRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static inline UIColor *ASDCBlue(void) {
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];   // #024DFFFF
}
static inline UIColor *ASDCBlue10(void) {
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:0.10]; // 10%
}
static inline UIColor *ASDCGray666(void) {
    return [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];  // #666666FF
}
static inline UIColor *ASDCAvatarBG(void) {
    return [UIColor colorWithRed:0xD6/255.0 green:0xE7/255.0 blue:0xFF/255.0 alpha:1.0];  // #D6E7FFFF
}
static inline UIFont *ASDCFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}
static inline NSString *ASDCFirstChar(NSString *s) {
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

#pragma mark - Decoration backgrounds (blue top + white body)

static NSString * const kASDCDupBlueBgKind  = @"kASDCDupBlueBgKind";
static NSString * const kASDCDupWhiteBgKind = @"kASDCDupWhiteBgKind";

@interface ASDCDupBgAttrs : UICollectionViewLayoutAttributes
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) NSUInteger maskedCorners;
@end

@implementation ASDCDupBgAttrs
- (id)copyWithZone:(NSZone *)zone {
    ASDCDupBgAttrs *a = [super copyWithZone:zone];
    a.fillColor = self.fillColor;
    a.cornerRadius = self.cornerRadius;
    a.maskedCorners = self.maskedCorners;
    return a;
}
@end

@interface ASDCDupBgView : UICollectionReusableView
@end

@implementation ASDCDupBgView
- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    [super applyLayoutAttributes:layoutAttributes];
    if (![layoutAttributes isKindOfClass:[ASDCDupBgAttrs class]]) return;

    ASDCDupBgAttrs *a = (ASDCDupBgAttrs *)layoutAttributes;
    self.backgroundColor = a.fillColor ?: UIColor.clearColor;
    self.layer.cornerRadius = a.cornerRadius;
    self.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        self.layer.maskedCorners = a.maskedCorners;
    }
}
@end

@interface ASDCDupCardFlowLayout : UICollectionViewFlowLayout
@property (nonatomic, strong) NSArray<ASDCDupBgAttrs *> *blueAttrs;
@property (nonatomic, strong) NSArray<ASDCDupBgAttrs *> *whiteAttrs;

// 关键参数：制造“蓝底在白色下面并向下延伸，白色向上盖住一截”的效果
@property (nonatomic, assign) CGFloat blueExtendDown; // 蓝底向下延伸
@property (nonatomic, assign) CGFloat whiteOverlap;   // 白底向上盖住蓝底
@end

@implementation ASDCDupCardFlowLayout

- (instancetype)init {
    if (self = [super init]) {
        self.minimumLineSpacing = 8;

        // ✅ 白色部分顶部更“下”一点：把 top 从 20 提到 28
        self.sectionInset = UIEdgeInsetsMake(20, 15, 30, 15);

        self.headerReferenceSize = CGSizeMake(0, 54);

        // ✅ 蓝色部分往下延伸更多：18 -> 28
        self.blueExtendDown = 35;

        // ✅ 白色向上覆盖少一点（白色顶部往下）：14 -> 8
        self.whiteOverlap   = 0;

        [self registerClass:[ASDCDupBgView class] forDecorationViewOfKind:kASDCDupBlueBgKind];
        [self registerClass:[ASDCDupBgView class] forDecorationViewOfKind:kASDCDupWhiteBgKind];
    }
    return self;
}
- (void)prepareLayout {
    [super prepareLayout];
    if (!self.collectionView) return;

    CGFloat W = self.collectionView.bounds.size.width;
    self.headerReferenceSize = CGSizeMake(W, 54);

    NSInteger sections = [self.collectionView numberOfSections];
    NSMutableArray *blue = [NSMutableArray array];
    NSMutableArray *white = [NSMutableArray array];

    for (NSInteger s = 0; s < sections; s++) {
        NSIndexPath *ip0 = [NSIndexPath indexPathForItem:0 inSection:s];

        UICollectionViewLayoutAttributes *h =
        [super layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                              atIndexPath:ip0];
        if (!h) continue;

        // 蓝底：header 高度 + 向下延伸
        CGRect blueRect = h.frame;
        blueRect.origin.x = 0;
        blueRect.size.width = W;
        blueRect.size.height = CGRectGetHeight(h.frame) + self.blueExtendDown;

        ASDCDupBgAttrs *ba =
        [ASDCDupBgAttrs layoutAttributesForDecorationViewOfKind:kASDCDupBlueBgKind
                                                 withIndexPath:ip0];
        ba.frame = blueRect;
        ba.zIndex = -3;
        ba.fillColor = ASDCBlue10();
        ba.cornerRadius = 22.0;
        ba.maskedCorners = (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner); // 上圆角
        [blue addObject:ba];

        // 白底：从 header 底部往上盖住一截（whiteOverlap），到底部包含 item + bottom padding(20)
        NSInteger items = [self.collectionView numberOfItemsInSection:s];
        if (items <= 0) continue;

        UICollectionViewLayoutAttributes *first =
        [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:s]];
        UICollectionViewLayoutAttributes *last =
        [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:items-1 inSection:s]];
        if (!first || !last) continue;

        CGRect unionRect = CGRectUnion(first.frame, last.frame);

        CGFloat bottomPad = 20.0; // 白底内边距下 20
        CGFloat y0 = CGRectGetMaxY(h.frame) - self.whiteOverlap;
        CGFloat y1 = CGRectGetMaxY(unionRect) + bottomPad;

        CGRect whiteRect = CGRectMake(0, y0, W, MAX(0, y1 - y0));

        ASDCDupBgAttrs *wa =
        [ASDCDupBgAttrs layoutAttributesForDecorationViewOfKind:kASDCDupWhiteBgKind
                                                 withIndexPath:ip0];
        wa.frame = whiteRect;
        wa.zIndex = -2;
        wa.fillColor = UIColor.whiteColor;
        wa.cornerRadius = 16.0;
        wa.maskedCorners = (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner); // 四角
        [white addObject:wa];
    }

    self.blueAttrs = blue;
    self.whiteAttrs = white;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSArray *attrs = [super layoutAttributesForElementsInRect:rect] ?: @[];
    NSMutableArray *out = [attrs mutableCopy];

    for (ASDCDupBgAttrs *a in self.blueAttrs) {
        if (CGRectIntersectsRect(rect, a.frame)) [out addObject:a];
    }
    for (ASDCDupBgAttrs *a in self.whiteAttrs) {
        if (CGRectIntersectsRect(rect, a.frame)) [out addObject:a];
    }
    return out;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES;
}

@end

#pragma mark - Group Header (content only, background is decoration)

@interface ASDCDupGroupHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *selectBtn;
@property (nonatomic, copy) void (^onToggleSelectAll)(void);
- (void)configTitle:(NSString *)title allSelected:(BOOL)allSelected showSelect:(BOOL)showSelect;
@end

@implementation ASDCDupGroupHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = ASDCFont(15, UIFontWeightSemibold);
        self.titleLabel.textColor = UIColor.blackColor;
        self.titleLabel.numberOfLines = 1;
        [self addSubview:self.titleLabel];

        // 确保上下 15 不被压缩
        [self.titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        self.selectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectBtn.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectBtn.backgroundColor = UIColor.clearColor;
        self.selectBtn.layer.cornerRadius = 16;
        self.selectBtn.layer.masksToBounds = YES;
        self.selectBtn.layer.borderWidth = 1.0;
        self.selectBtn.layer.borderColor = ASDCGray666().CGColor;
        self.selectBtn.titleLabel.font = ASDCFont(13, UIFontWeightMedium);
        [self.selectBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        self.selectBtn.contentEdgeInsets = UIEdgeInsetsMake(9, 20, 9, 20); // 左右20，上下9
        [self.selectBtn addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.selectBtn];

        [NSLayoutConstraint activateConstraints:@[
            // title: 左 18，右到按钮 10，上下 15 固定
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:15],
            [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-15],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectBtn.leadingAnchor constant:-10],

            // button: 右 10，垂直居中对齐 title
            [self.selectBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.selectBtn.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configTitle:(NSString *)title allSelected:(BOOL)allSelected showSelect:(BOOL)showSelect {
    self.titleLabel.text = title ?: @"";
    self.selectBtn.hidden = !showSelect;
    [self.selectBtn setTitle:(allSelected ? @"Deselect All" : @"Select All") forState:UIControlStateNormal];
}

- (void)tap { if (self.onToggleSelectAll) self.onToggleSelectAll(); }

@end

#pragma mark - Item Cell

@interface ASDCDupContactCell : UICollectionViewCell
@property (nonatomic, strong) UIView *borderView;
@property (nonatomic, strong) UIView *avatarView;
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *phoneLabel;
@property (nonatomic, strong) UIImageView *selectIcon;
@property (nonatomic, copy) void (^onTap)(void);
- (void)configName:(NSString *)name phone:(NSString *)phone initial:(NSString *)initial selected:(BOOL)selected showSelectIcon:(BOOL)showSelectIcon;
@end

@implementation ASDCDupContactCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.clearColor;

        self.borderView = [UIView new];
        self.borderView.translatesAutoresizingMaskIntoConstraints = NO;
        self.borderView.backgroundColor = UIColor.clearColor;
        self.borderView.layer.cornerRadius = 12;
        self.borderView.layer.borderWidth = 2.0;
        self.borderView.layer.borderColor = ASDCBlue().CGColor;
        [self.contentView addSubview:self.borderView];

        self.avatarView = [UIView new];
        self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarView.backgroundColor = ASDCAvatarBG();
        self.avatarView.layer.cornerRadius = 24;
        self.avatarView.layer.masksToBounds = YES;
        [self.borderView addSubview:self.avatarView];

        self.avatarLabel = [UILabel new];
        self.avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarLabel.font = ASDCFont(27, UIFontWeightMedium);
        self.avatarLabel.textColor = UIColor.whiteColor;
        self.avatarLabel.textAlignment = NSTextAlignmentCenter;
        [self.avatarView addSubview:self.avatarLabel];

        self.nameLabel = [UILabel new];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.font = ASDCFont(20, UIFontWeightSemibold);
        self.nameLabel.textColor = UIColor.blackColor;
        [self.borderView addSubview:self.nameLabel];

        self.phoneLabel = [UILabel new];
        self.phoneLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.phoneLabel.font = ASDCFont(12, UIFontWeightRegular);
        self.phoneLabel.textColor = [UIColor colorWithWhite:0 alpha:0.5];
        [self.borderView addSubview:self.phoneLabel];

        self.selectIcon = [UIImageView new];
        self.selectIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectIcon.contentMode = UIViewContentModeScaleAspectFit;
        [self.borderView addSubview:self.selectIcon];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapCell)];
        [self.contentView addGestureRecognizer:tap];

        [NSLayoutConstraint activateConstraints:@[
            [self.borderView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.borderView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.borderView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.borderView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            // content padding: 左右18，上下11
            [self.avatarView.leadingAnchor constraintEqualToAnchor:self.borderView.leadingAnchor constant:18],
            [self.avatarView.centerYAnchor constraintEqualToAnchor:self.borderView.centerYAnchor],
            [self.avatarView.widthAnchor constraintEqualToConstant:48],
            [self.avatarView.heightAnchor constraintEqualToConstant:48],

            [self.avatarLabel.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
            [self.avatarLabel.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],

            [self.selectIcon.trailingAnchor constraintEqualToAnchor:self.borderView.trailingAnchor constant:-18],
            [self.selectIcon.centerYAnchor constraintEqualToAnchor:self.borderView.centerYAnchor],
            [self.selectIcon.widthAnchor constraintEqualToConstant:24],
            [self.selectIcon.heightAnchor constraintEqualToConstant:24],

            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:10],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectIcon.leadingAnchor constant:-10],
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.borderView.topAnchor constant:11],

            [self.phoneLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.phoneLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
            [self.phoneLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
            [self.phoneLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.borderView.bottomAnchor constant:-11],
        ]];
    }
    return self;
}

- (void)tapCell { if (self.onTap) self.onTap(); }

- (void)configName:(NSString *)name phone:(NSString *)phone initial:(NSString *)initial selected:(BOOL)selected showSelectIcon:(BOOL)showSelectIcon {
    self.nameLabel.text = name ?: @"";
    self.phoneLabel.text = phone ?: @"";
    self.avatarLabel.text = initial.length ? initial : @"?";
    self.selectIcon.hidden = !showSelectIcon;
    NSString *iconName = selected ? @"ic_select_s" : @"ic_select_gray_n";
    self.selectIcon.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@end

#pragma mark - VC

@interface DuplicateContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UIImageView *bgTop;
@property (nonatomic, strong) ASSelectTitleBar *titleBar;

@property (nonatomic, strong) UILabel *pageTitleLabel;
@property (nonatomic, strong) UILabel *countLabel;

@property (nonatomic, strong) UICollectionView *cv;

@property (nonatomic, strong) UIButton *floatingButton;

@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImage;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptySubTitle;
@property (nonatomic, strong) UILabel *emptyHint;

@property (nonatomic, strong) NSArray<CMDuplicateGroup *> *allGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedContactIds;

@property (nonatomic, strong) ContactsManager *contactsManager;

@property (nonatomic, assign) BOOL previewMode;
@property (nonatomic, strong) NSArray<CMDuplicateGroup *> *previewGroups; // 进入预览时冻结
@property (nonatomic, assign) BOOL didMergeOnce;

@end

@implementation DuplicateContactsViewController

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

    self.view.backgroundColor = ASDCRGB(246, 248, 251);

    self.contactsManager = [ContactsManager shared];
    self.selectedContactIds = [NSMutableSet set];
    self.previewMode = NO;
    self.didMergeOnce = NO;

    [self buildBackground];
    [self setupUI];
    [self setupContacts];
}

#pragma mark - Background

- (void)buildBackground {
    self.bgTop = [UIImageView new];
    self.bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    self.bgTop.contentMode = UIViewContentModeScaleAspectFill;
    self.bgTop.clipsToBounds = YES;
    self.bgTop.userInteractionEnabled = NO;
    [self.view insertSubview:self.bgTop atIndex:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgTop.heightAnchor constraintEqualToConstant:360],
    ]];
}

#pragma mark - UI

- (void)setupUI {
    __weak typeof(self) weakSelf = self;

    self.titleBar = [[ASSelectTitleBar alloc] initWithTitle:@"Duplicate"];
    self.titleBar.showTitle = NO;
    self.titleBar.showSelectButton = YES;

    self.titleBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    self.titleBar.onToggleSelectAll = ^(BOOL allSelected) {
        if (weakSelf.previewMode) return;

        if ([weakSelf isAllSelectedDisplayed]) {
            [weakSelf deselectAllDisplayed];
        } else {
            [weakSelf selectAllDisplayed];
        }
        [weakSelf syncTopSelectState];
        [weakSelf updateFloatingButtonState];
        [weakSelf.cv reloadData];
    };
    [self.view addSubview:self.titleBar];

    // page title
    self.pageTitleLabel = [UILabel new];
    self.pageTitleLabel.text = @"Duplicate";
    self.pageTitleLabel.textColor = UIColor.blackColor;
    self.pageTitleLabel.font = ASDCFont(28, UIFontWeightSemibold);
    [self.view addSubview:self.pageTitleLabel];

    // count label
    self.countLabel = [UILabel new];
    [self.view addSubview:self.countLabel];

    // collection
    ASDCDupCardFlowLayout *layout = [ASDCDupCardFlowLayout new];

    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    self.cv.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.cv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [self.cv registerClass:[ASDCDupContactCell class] forCellWithReuseIdentifier:@"ASDCDupContactCell"];
    [self.cv registerClass:[ASDCDupGroupHeaderView class]
forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
       withReuseIdentifier:@"ASDCDupGroupHeaderView"];

    [self.view addSubview:self.cv];

    // floating button
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.hidden = YES;
    self.floatingButton.backgroundColor = ASDCBlue();
    [self.floatingButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = ASDCFont(20, UIFontWeightRegular);
    self.floatingButton.contentEdgeInsets = UIEdgeInsetsMake(22, 22, 22, 22);
    [self.floatingButton addTarget:self action:@selector(floatingTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.floatingButton];

    // empty view
    self.emptyView = [UIView new];
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyImage = [UIImageView new];
    self.emptyImage.contentMode = UIViewContentModeScaleAspectFit;
    [self.emptyView addSubview:self.emptyImage];

    self.emptyTitle = [UILabel new];
    self.emptyTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyTitle.textColor = UIColor.blackColor;
    [self.emptyView addSubview:self.emptyTitle];

    self.emptySubTitle = [UILabel new];
    self.emptySubTitle.textAlignment = NSTextAlignmentCenter;
    self.emptySubTitle.textColor = UIColor.blackColor;
    [self.emptyView addSubview:self.emptySubTitle];

    self.emptyHint = [UILabel new];
    self.emptyHint.textAlignment = NSTextAlignmentCenter;
    self.emptyHint.textColor = ASDCGray666();
    self.emptyHint.font = ASDCFont(12, UIFontWeightMedium);
    self.emptyHint.numberOfLines = 0;
    [self.emptyView addSubview:self.emptyHint];
}

#pragma mark - Data

- (void)setupContacts {
    __weak typeof(self) weakSelf = self;

    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) { return; }

        [weakSelf.contactsManager fetchDuplicateContactsWithMode:CMDuplicateModeAll
                                                     completion:^(NSArray<CMDuplicateGroup *> * _Nullable groups,
                                                                  NSArray<CMDuplicateGroup *> * _Nullable nameGroups,
                                                                  NSArray<CMDuplicateGroup *> * _Nullable phoneGroups,
                                                                  NSError * _Nullable error2) {
            if (error2) { return; }

            // 默认显示所有：nameGroups + phoneGroups
            NSArray *ng = nameGroups ?: @[];
            NSArray *pg = phoneGroups ?: @[];
            weakSelf.allGroups = [ng arrayByAddingObjectsFromArray:pg];

            weakSelf.previewMode = NO;
            weakSelf.previewGroups = nil;
            [weakSelf.selectedContactIds removeAllObjects];

            [weakSelf updateTopCountLabel];
            [weakSelf updateEmptyStateIfNeeded];
            [weakSelf updateFloatingButtonState];
            [weakSelf syncTopSelectState];

            [weakSelf.cv reloadData];
            [weakSelf.view setNeedsLayout];
        }];
    }];
}

#pragma mark - Helpers

- (NSSet<NSString *> *)allDuplicateIDsSet {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (CMDuplicateGroup *g in (self.allGroups ?: @[])) {
        for (CNContact *c in g.items) {
            if (c.identifier.length > 0) [set addObject:c.identifier];
        }
    }
    return set;
}

- (void)updateTopCountLabel {
    NSInteger count = [self allDuplicateIDsSet].count;
    NSString *num = [NSString stringWithFormat:@"%ld", (long)count];
    NSString *full = [NSString stringWithFormat:@"%@ Contacts", num];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full];
    UIFont *font = ASDCFont(16, UIFontWeightMedium);
    [att addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, full.length)];

    NSRange nr = [full rangeOfString:num];
    if (nr.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:ASDCBlue() range:nr];
    }
    NSRange cr = [full rangeOfString:@"Contacts"];
    if (cr.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:ASDCGray666() range:cr];
    }
    self.countLabel.attributedText = att;
}

#pragma mark - Top Select All

- (BOOL)isAllSelectedDisplayed {
    NSSet *displayed = [self allDuplicateIDsSet];
    if (displayed.count == 0) return NO;
    return [displayed isSubsetOfSet:self.selectedContactIds];
}
- (void)selectAllDisplayed { [self.selectedContactIds unionSet:[self allDuplicateIDsSet]]; }
- (void)deselectAllDisplayed { [self.selectedContactIds minusSet:[self allDuplicateIDsSet]]; }

- (void)syncTopSelectState {
    BOOL isEmpty = !self.emptyView.hidden;
    
    if (isEmpty) {
        self.titleBar.showSelectButton = NO;
        return;
    }
    
    self.titleBar.showSelectButton = (!self.previewMode);
    self.titleBar.allSelected = [self isAllSelectedDisplayed];
}


#pragma mark - Group Select

- (BOOL)isGroupAllSelected:(CMDuplicateGroup *)g {
    if (g.items.count == 0) return NO;
    for (CNContact *c in g.items) {
        if (c.identifier.length == 0) continue;
        if (![self.selectedContactIds containsObject:c.identifier]) return NO;
    }
    return YES;
}
- (void)selectAllInGroup:(CMDuplicateGroup *)g {
    for (CNContact *c in g.items) if (c.identifier.length > 0) [self.selectedContactIds addObject:c.identifier];
}
- (void)deselectAllInGroup:(CMDuplicateGroup *)g {
    for (CNContact *c in g.items) if (c.identifier.length > 0) [self.selectedContactIds removeObject:c.identifier];
}
- (NSArray<NSString *> *)selectedIdentifiersInGroup:(CMDuplicateGroup *)g {
    NSMutableArray *ids = [NSMutableArray array];
    for (CNContact *c in g.items) {
        if (c.identifier.length == 0) continue;
        if ([self.selectedContactIds containsObject:c.identifier]) [ids addObject:c.identifier];
    }
    return ids;
}

#pragma mark - Mergeable

- (NSArray<CMDuplicateGroup *> *)mergeableGroupsFrom:(NSArray<CMDuplicateGroup *> *)sourceShownGroups {
    NSMutableArray *arr = [NSMutableArray array];
    for (CMDuplicateGroup *g in (sourceShownGroups ?: @[])) {
        NSInteger cnt = 0;
        for (CNContact *c in g.items) {
            if ([self.selectedContactIds containsObject:c.identifier]) {
                cnt++;
                if (cnt >= 2) break;
            }
        }
        if (cnt >= 2) [arr addObject:g];
    }
    return arr;
}

- (NSArray<CMDuplicateGroup *> *)currentMergeableGroups {
    return [self mergeableGroupsFrom:self.allGroups];
}

- (NSInteger)selectedMergeableContactCount {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (CMDuplicateGroup *g in [self currentMergeableGroups]) {
        for (CNContact *c in g.items) {
            if (c.identifier.length == 0) continue;
            if ([self.selectedContactIds containsObject:c.identifier]) [set addObject:c.identifier];
        }
    }
    return set.count;
}

- (BOOL)hasMergeableGroup {
    return [self currentMergeableGroups].count > 0;
}

#pragma mark - Floating Button

- (void)updateFloatingButtonState {
    BOOL show = [self hasMergeableGroup];
    self.floatingButton.hidden = !show;
    if (!show) return;

    if (!self.previewMode) {
        [self.floatingButton setTitle:@"See Merge Preview" forState:UIControlStateNormal];
    } else {
        NSInteger n = [self selectedMergeableContactCount];
        [self.floatingButton setTitle:[NSString stringWithFormat:@"Merge %ld contacts", (long)n]
                             forState:UIControlStateNormal];
    }
}

- (void)floatingTap {
    if (![self hasMergeableGroup]) return;

    if (!self.previewMode) {
        self.previewMode = YES;
        self.previewGroups = [self currentMergeableGroups]; // 冻结预览内容
        [self syncTopSelectState];
        [self updateFloatingButtonState];
        [self.cv reloadData];
        return;
    }

    // previewMode == YES
    [self confirmMergeForPreviewGroups];
}

#pragma mark - Merge Implementation

- (void)confirmMergeForPreviewGroups {
    NSInteger n = [self selectedMergeableContactCount];
    if (n < 2) return;

    __weak typeof(self) weakSelf = self;

    NSString *msg = [NSString stringWithFormat:@"This will merge %ld contacts. Continue?", (long)n];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Merge Contacts"
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Merge" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.floatingButton.enabled = NO;
        weakSelf.floatingButton.alpha = 0.7;

        [weakSelf performMergeForPreviewGroups];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showToastDone {
    UIView *host = self.view.window ?: self.view;
    if (!host) return;

    NSInteger tag = 909090;
    UIView *old = [host viewWithTag:tag];
    if (old) [old removeFromSuperview];

    UILabel *lab = [UILabel new];
    lab.text = @"Done!";
    lab.textColor = UIColor.whiteColor;
    lab.font = ASDCFont(16, UIFontWeightMedium);
    lab.textAlignment = NSTextAlignmentCenter;
    lab.numberOfLines = 1;

    UIView *toast = [UIView new];
    toast.tag = tag;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
    toast.layer.cornerRadius = 12;
    toast.layer.masksToBounds = YES;

    [toast addSubview:lab];
    [host addSubview:toast];

    CGFloat maxW = host.bounds.size.width - 80;
    CGSize textSize = [lab sizeThatFits:CGSizeMake(maxW, 999)];
    CGFloat padX = 22, padY = 12;

    CGFloat w = MIN(maxW, textSize.width) + padX * 2;
    CGFloat h = textSize.height + padY * 2;

    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = host.safeAreaInsets.bottom;

    CGFloat x = (host.bounds.size.width - w) * 0.5;
    CGFloat y = host.bounds.size.height - safeBottom - h - 110;
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

- (void)performMergeForPreviewGroups {
    NSArray<CMDuplicateGroup *> *groups = self.previewGroups ?: @[];
    if (groups.count == 0) return;

    // 组内只合并选中的 identifiers（>=2 才会在 previewGroups 里）
    NSMutableArray<NSArray<NSString *> *> *batches = [NSMutableArray array];
    for (CMDuplicateGroup *g in groups) {
        NSArray<NSString *> *ids = [self selectedIdentifiersInGroup:g];
        if (ids.count >= 2) [batches addObject:ids];
    }
    if (batches.count == 0) return;

    __weak typeof(self) weakSelf = self;
    [self.contactsManager requestContactsAccess:^(NSError * _Nullable error) {
        if (error) return;
        [weakSelf mergeBatchesSequentially:batches index:0];
    }];
}

- (void)mergeBatchesSequentially:(NSArray<NSArray<NSString *> *> *)batches index:(NSInteger)idx {
    if (idx >= (NSInteger)batches.count) {
        [self showToastDone];

        self.floatingButton.enabled = YES;
        self.floatingButton.alpha = 1.0;

        self.didMergeOnce = YES;
        self.previewMode = NO;
        self.previewGroups = nil;
        [self.selectedContactIds removeAllObjects];
        [self setupContacts];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *ids = batches[idx];

    [self.contactsManager mergeContactsWithIdentifiers:ids
                                     preferredPrimary:nil
                                           completion:^(NSString * _Nullable mergedIdentifier, NSError * _Nullable error) {
        // 失败也继续下一组，避免阻断
        (void)mergedIdentifier;
        (void)error;
        [weakSelf mergeBatchesSequentially:batches index:idx + 1];
    }];
}

#pragma mark - Empty State

- (void)updateEmptyStateIfNeeded {
    BOOL noGroups = ((self.allGroups ?: @[]).count == 0);

    if (!noGroups) {
        self.emptyView.hidden = YES;
        self.cv.hidden = NO;
        return;
    }

    self.cv.hidden = YES;
    self.emptyView.hidden = NO;

    if (self.didMergeOnce) {
        self.emptyImage.image = [UIImage imageNamed:@"ic_contact_success"];
        self.emptyTitle.text = @"Done!";
        self.emptyTitle.font = ASDCFont(34, UIFontWeightMedium);

        self.emptySubTitle.text = @"No Preview Available";
        self.emptySubTitle.font = ASDCFont(20, UIFontWeightMedium);

        self.emptyHint.text = @"Go Back And Select Duplicates To See a Preview";
        self.emptyHint.hidden = NO;
        self.emptySubTitle.hidden = NO;
    } else {
        self.pageTitleLabel.hidden = YES;
        self.countLabel.hidden = YES;

        self.emptyImage.image = [UIImage imageNamed:@"ic_no_contact"];
        self.emptyTitle.text = @"No Content";
        self.emptyTitle.font = ASDCFont(24, UIFontWeightMedium);

        self.emptySubTitle.hidden = YES;
        self.emptyHint.hidden = YES;
    }
    [self.cv reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    if (self.previewMode) return (self.previewGroups ?: @[]).count;
    return (self.allGroups ?: @[]).count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (!self.previewMode) {
        CMDuplicateGroup *g = self.allGroups[section];
        return g.items.count;
    }
    // preview：每组显示 1 个合并预览 cell
    return 1;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASDCDupContactCell *cell =
    [collectionView dequeueReusableCellWithReuseIdentifier:@"ASDCDupContactCell" forIndexPath:indexPath];

    __weak typeof(self) weakSelf = self;

    if (!self.previewMode) {
        CMDuplicateGroup *g = self.allGroups[indexPath.section];
        CNContact *c = g.items[indexPath.item];

        NSString *name = [CNContactFormatter stringFromContact:c style:CNContactFormatterStyleFullName];
        if (name.length == 0) name = @"(No Name)";

        NSString *phone = @"";
        if ([c isKeyAvailable:CNContactPhoneNumbersKey] && c.phoneNumbers.count > 0) {
            NSMutableArray *arr = [NSMutableArray array];
            for (CNLabeledValue<CNPhoneNumber *> *lv in c.phoneNumbers) {
                NSString *p = lv.value.stringValue ?: @"";
                if (p.length > 0) [arr addObject:p];
            }
            phone = [arr componentsJoinedByString:@" · "];
        }

        BOOL selected = [self.selectedContactIds containsObject:c.identifier];

        cell.onTap = ^{
            if (weakSelf.previewMode) return;
            if (c.identifier.length == 0) return;

            if ([weakSelf.selectedContactIds containsObject:c.identifier]) {
                [weakSelf.selectedContactIds removeObject:c.identifier];
            } else {
                [weakSelf.selectedContactIds addObject:c.identifier];
            }

            [weakSelf updateFloatingButtonState];
            [weakSelf syncTopSelectState];
            [weakSelf.cv reloadData];
        };

        [cell configName:name
                  phone:phone
                initial:ASDCFirstChar(name)
               selected:selected
          showSelectIcon:YES];
        return cell;
    }

    // ===== preview cell =====
    CMDuplicateGroup *g = self.previewGroups[indexPath.section];
    NSArray<NSString *> *selIds = [self selectedIdentifiersInGroup:g];

    // primary：取第一个选中的 contact
    CNContact *primary = nil;
    for (CNContact *c in g.items) {
        if ([selIds containsObject:c.identifier]) { primary = c; break; }
    }
    if (!primary) primary = g.items.firstObject;

    NSString *name = [CNContactFormatter stringFromContact:primary style:CNContactFormatterStyleFullName];
    if (name.length == 0) name = @"(No Name)";

    // 合并展示电话（去重）
    NSMutableOrderedSet<NSString *> *phones = [NSMutableOrderedSet orderedSet];
    for (CNContact *c in g.items) {
        if (![selIds containsObject:c.identifier]) continue;
        if ([c isKeyAvailable:CNContactPhoneNumbersKey]) {
            for (CNLabeledValue<CNPhoneNumber *> *lv in c.phoneNumbers) {
                NSString *p = lv.value.stringValue ?: @"";
                if (p.length > 0) [phones addObject:p];
            }
        }
    }
    NSString *phone = (phones.count > 0) ? [phones.array componentsJoinedByString:@" · "] : @"";

    cell.onTap = nil;
    [cell configName:name
              phone:phone
            initial:ASDCFirstChar(name)
           selected:NO
      showSelectIcon:NO];
    return cell;
}

#pragma mark - Header

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) return [UICollectionReusableView new];

    ASDCDupGroupHeaderView *v =
    [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                       withReuseIdentifier:@"ASDCDupGroupHeaderView"
                                              forIndexPath:indexPath];

    CMDuplicateGroup *g = self.previewMode ? self.previewGroups[indexPath.section] : self.allGroups[indexPath.section];

    BOOL showSelect = !self.previewMode;
    BOOL allSel = [self isGroupAllSelected:g];

    NSInteger countToShow = g.items.count;
    if (self.previewMode) {
        // 预览里更贴近“合并了多少个”
        countToShow = [self selectedIdentifiersInGroup:g].count;
    }

    NSString *title = [NSString stringWithFormat:@"%ld Duplicate Contacts", (long)countToShow];
    [v configTitle:title allSelected:allSel showSelect:showSelect];

    __weak typeof(self) weakSelf = self;
    v.onToggleSelectAll = ^{
        if (weakSelf.previewMode) return;

        if ([weakSelf isGroupAllSelected:g]) {
            [weakSelf deselectAllInGroup:g];
        } else {
            [weakSelf selectAllInGroup:g];
        }
        [weakSelf updateFloatingButtonState];
        [weakSelf syncTopSelectState];
        [weakSelf.cv reloadData];
    };

    return v;
}

#pragma mark - Layout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // sectionInset.left/right = 15，所以 cell 宽 = W - 30
    return CGSizeMake(collectionView.bounds.size.width - 30, 72);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    CGFloat navH = 44 + safeTop;
    self.titleBar.frame = CGRectMake(0, 0, W, navH);

    CGFloat pagePad = 20.0;

    CGFloat y = navH + 16;
    self.pageTitleLabel.frame = CGRectMake(pagePad, y, W - pagePad * 2, 34);

    y += 34 + 6;
    self.countLabel.frame = CGRectMake(pagePad, y, W - pagePad * 2, 20);

    y += 40;

    // floating button
    CGFloat btnH = 64;
    CGFloat btnW = W - pagePad * 2;
    CGFloat btnY = H - safeBottom - btnH;
    self.floatingButton.frame = CGRectMake(pagePad, btnY, btnW, btnH);
    self.floatingButton.layer.cornerRadius = btnH * 0.5;

    // 列表：左右离屏幕 20；底部延伸到屏幕底（不减 safeBottom）
    self.cv.frame = CGRectMake(pagePad, y, W - pagePad * 2, H - y);

    // 防止被浮动按钮挡住（只改 contentInset，不给“列表背景内边距”）
    CGFloat extraBottom = self.floatingButton.hidden ? 20.0 : (btnH + 20.0);
    self.cv.contentInset = UIEdgeInsetsMake(0, 0, safeBottom + extraBottom, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;

    // empty
    self.emptyView.frame = CGRectMake(0, navH, W, H - navH);
    if (!self.emptyView.hidden) {
        CGSize imgSize = self.didMergeOnce ? CGSizeMake(181, 172) : CGSizeMake(182, 168);
        CGFloat centerY = self.emptyView.bounds.size.height * 0.45;

        self.emptyImage.frame = CGRectMake((W - imgSize.width)/2.0,
                                           centerY - imgSize.height,
                                           imgSize.width,
                                           imgSize.height);

        if (self.didMergeOnce) {
            self.emptyTitle.frame = CGRectMake(pagePad, CGRectGetMaxY(self.emptyImage.frame) + 20, W - pagePad*2, 40);
            self.emptySubTitle.frame = CGRectMake(pagePad, CGRectGetMaxY(self.emptyTitle.frame) + 10, W - pagePad*2, 28);
            self.emptyHint.frame = CGRectMake(pagePad, CGRectGetMaxY(self.emptySubTitle.frame) + 10, W - pagePad*2, 44);
        } else {
            self.emptyTitle.frame = CGRectMake(pagePad, CGRectGetMaxY(self.emptyImage.frame) + 2, W - pagePad*2, 32);
        }
    }

    [self updateTopCountLabel];
    [self updateFloatingButtonState];
    [self syncTopSelectState];
}

@end
