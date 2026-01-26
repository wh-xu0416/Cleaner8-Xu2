#import "ASSelectTitleBar.h"

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

static inline CGFloat SWScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}

static inline UIColor *ASHexBlack(void) {
    // #000000FF
    return [UIColor colorWithRed:0 green:0 blue:0 alpha:1.0];
}

@interface ASSelectTitleBar ()
@property (nonatomic, strong, readwrite) UIButton *backButton;
@property (nonatomic, strong, readwrite) UILabel  *titleLabel;
@property (nonatomic, strong, readwrite) UIButton *selectAllButton;

@property (nonatomic, strong) UIImageView *selectIconView;
@property (nonatomic, strong) UILabel     *selectTextLabel;

@property (nonatomic, strong) NSLayoutConstraint *titleTrailingToSelectConstraint;
@end

@implementation ASSelectTitleBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.clearColor;

        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.backButton.backgroundColor = UIColor.clearColor;
        self.backButton.adjustsImageWhenHighlighted = NO;
        self.backButton.showsTouchWhenHighlighted = NO;

        UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.backButton setImage:backImg forState:UIControlStateNormal];
        self.backButton.contentEdgeInsets = UIEdgeInsetsZero;
        self.backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.backButton.imageEdgeInsets = SWInsets(10, 0, 10, 0);
        self.backButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.backButton];

        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.text = title;
        self.titleLabel.textAlignment = NSTextAlignmentLeft;
        self.titleLabel.font = SWFontS(20, UIFontWeightSemibold);
        self.titleLabel.textColor = ASHexBlack();
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.6;
        [self addSubview:self.titleLabel];

        self.selectAllButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectAllButton.backgroundColor = UIColor.whiteColor;
        self.selectAllButton.adjustsImageWhenHighlighted = NO;
        self.selectAllButton.showsTouchWhenHighlighted = NO;
        self.selectAllButton.layer.cornerRadius = SW(18);
        self.selectAllButton.layer.masksToBounds = YES;

        [self.selectAllButton addTarget:self action:@selector(selectAllTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.selectAllButton];

        self.selectIconView = [UIImageView new];
        self.selectIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectIconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.selectAllButton addSubview:self.selectIconView];

        self.selectTextLabel = [UILabel new];
        self.selectTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectTextLabel.font = SWFontS(14, UIFontWeightMedium);
        self.selectTextLabel.textColor = ASHexBlack();
        self.selectTextLabel.numberOfLines = 1;
        self.selectTextLabel.adjustsFontSizeToFitWidth = YES;
        self.selectTextLabel.minimumScaleFactor = 0.6;
        [self.selectAllButton addSubview:self.selectTextLabel];

        [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        [self.selectTextLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.selectAllButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:SW(20)],
            [self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.backButton.widthAnchor constraintEqualToConstant:SW(44)],
            [self.backButton.heightAnchor constraintEqualToConstant:SW(44)],

            [self.selectAllButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-SW(20)],
            [self.selectAllButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.selectAllButton.heightAnchor constraintEqualToConstant:SW(36)],
            [self.selectAllButton.widthAnchor constraintLessThanOrEqualToConstant:SW(140)],
            
            [self.selectIconView.leadingAnchor constraintEqualToAnchor:self.selectAllButton.leadingAnchor constant:SW(6)],
            [self.selectIconView.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],
            [self.selectIconView.widthAnchor constraintEqualToConstant:SW(24)],
            [self.selectIconView.heightAnchor constraintEqualToConstant:SW(24)],

            [self.selectTextLabel.leadingAnchor constraintEqualToAnchor:self.selectIconView.trailingAnchor constant:SW(6)],
            [self.selectTextLabel.trailingAnchor constraintEqualToAnchor:self.selectAllButton.trailingAnchor constant:-SW(15)],
            [self.selectTextLabel.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],

            [self.selectAllButton.widthAnchor constraintGreaterThanOrEqualToConstant:SW(36)],
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.backButton.imageView.trailingAnchor constant:SW(20)],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.titleLabel.heightAnchor constraintEqualToConstant:SW(44)],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-SW(20)],
        ]];

        self.titleTrailingToSelectConstraint =
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectAllButton.leadingAnchor constant:-SW(12)];
        self.titleTrailingToSelectConstraint.active = YES;

        self.showTitle = YES;
        self.showSelectButton = YES;
        self.allSelected = NO; // 会触发一次 update UI
    }
    return self;
}

#pragma mark - Public

- (void)setTitleText:(NSString *)title {
    self.titleLabel.text = title;
}

- (void)setAllSelected:(BOOL)allSelected {
    _allSelected = allSelected;
    [self updateSelectUI];
}

- (void)setShowTitle:(BOOL)showTitle {
    _showTitle = showTitle;
    self.titleLabel.hidden = !showTitle;
}

- (void)setShowSelectButton:(BOOL)showSelectButton {
    _showSelectButton = showSelectButton;
    self.selectAllButton.hidden = !showSelectButton;

    self.titleTrailingToSelectConstraint.active = showSelectButton;
}

#pragma mark - Actions

- (void)backTap {
    if (self.onBack) self.onBack();
}

- (void)selectAllTap {
    self.allSelected = !self.allSelected;

    if (self.onToggleSelectAll) {
        self.onToggleSelectAll(self.allSelected);
    }
}

#pragma mark - UI

- (void)updateSelectUI {
    NSString *iconName = self.allSelected ? @"ic_select_s" : @"ic_select_gray_n";
    NSString *text     = self.allSelected ? NSLocalizedString(@"Deselect All",nil) : NSLocalizedString(@"Select All",nil);

    self.selectIconView.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.selectTextLabel.text = text;
}

@end
