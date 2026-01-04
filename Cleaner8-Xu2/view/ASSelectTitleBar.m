#import "ASSelectTitleBar.h"

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

        // ===== Back Button =====
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.backButton.backgroundColor = UIColor.clearColor;
        self.backButton.adjustsImageWhenHighlighted = NO;
        self.backButton.showsTouchWhenHighlighted = NO;

        UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.backButton setImage:backImg forState:UIControlStateNormal];
        self.backButton.contentEdgeInsets = UIEdgeInsetsZero;
        self.backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.backButton.imageEdgeInsets = UIEdgeInsetsMake(10, 0, 10, 0);
        self.backButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.backButton];

        // ===== Title =====
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.text = title;
        self.titleLabel.textAlignment = NSTextAlignmentLeft;
        self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = ASHexBlack();
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.titleLabel];

        // ===== Select All Button (white, rounded) =====
        self.selectAllButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectAllButton.backgroundColor = UIColor.whiteColor;
        self.selectAllButton.adjustsImageWhenHighlighted = NO;
        self.selectAllButton.showsTouchWhenHighlighted = NO;
        self.selectAllButton.layer.cornerRadius = 18; // 配合高度36
        self.selectAllButton.layer.masksToBounds = YES;

        [self.selectAllButton addTarget:self action:@selector(selectAllTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.selectAllButton];

        // inside: icon + text
        self.selectIconView = [UIImageView new];
        self.selectIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectIconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.selectAllButton addSubview:self.selectIconView];

        self.selectTextLabel = [UILabel new];
        self.selectTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.selectTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        self.selectTextLabel.textColor = ASHexBlack();
        self.selectTextLabel.numberOfLines = 1;
        [self.selectAllButton addSubview:self.selectTextLabel];

        // ===== Layout =====
        [NSLayoutConstraint activateConstraints:@[
            // back: left inset 20
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.backButton.widthAnchor constraintEqualToConstant:44],
            [self.backButton.heightAnchor constraintEqualToConstant:44],

            // select: right inset 20
            [self.selectAllButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [self.selectAllButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.selectAllButton.heightAnchor constraintEqualToConstant:36],

            // inner padding = 6, spacing between icon/text = 6
            [self.selectIconView.leadingAnchor constraintEqualToAnchor:self.selectAllButton.leadingAnchor constant:6],
            [self.selectIconView.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],
            [self.selectIconView.widthAnchor constraintEqualToConstant:24],
            [self.selectIconView.heightAnchor constraintEqualToConstant:24],

            [self.selectTextLabel.leadingAnchor constraintEqualToAnchor:self.selectIconView.trailingAnchor constant:6],
            [self.selectTextLabel.trailingAnchor constraintEqualToAnchor:self.selectAllButton.trailingAnchor constant:-15],
            [self.selectTextLabel.centerYAnchor constraintEqualToAnchor:self.selectAllButton.centerYAnchor],

            [self.selectAllButton.widthAnchor constraintGreaterThanOrEqualToConstant:36],
        ]];

        // title: 20pt from back button
        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.backButton.imageView.trailingAnchor constant:20],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.titleLabel.heightAnchor constraintEqualToConstant:44],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20],
        ]];

        self.titleTrailingToSelectConstraint =
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectAllButton.leadingAnchor constant:-12];
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

    // 右按钮隐藏时，让 title 不再受 “靠左到 selectButton” 的限制
    self.titleTrailingToSelectConstraint.active = showSelectButton;
}

#pragma mark - Actions

- (void)backTap {
    if (self.onBack) self.onBack();
}

- (void)selectAllTap {
    // 这里默认内部切换状态；如果你想“只通知不切换”，删掉下一行即可
    self.allSelected = !self.allSelected;

    if (self.onToggleSelectAll) {
        self.onToggleSelectAll(self.allSelected);
    }
}

#pragma mark - UI

- (void)updateSelectUI {
    NSString *iconName = self.allSelected ? @"ic_select_s" : @"ic_select_gray_n";
    NSString *text     = self.allSelected ? @"Deselect All" : @"Select All";

    self.selectIconView.image = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.selectTextLabel.text = text;
}

@end
