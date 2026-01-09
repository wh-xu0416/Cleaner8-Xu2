#import "ASCustomNavBar.h"

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
}

@interface ASCustomNavBar ()
@property (nonatomic, strong, readwrite) UIButton *backButton;
@property (nonatomic, strong, readwrite) UILabel  *titleLabel;
@property (nonatomic, strong, readwrite) UIButton *rightButton;

@property (nonatomic, strong) UIImageView *backIconView;
@property (nonatomic, strong) UIImageView *rightIconView;

@property (nonatomic, strong) UIView *contentView;
@end

@implementation ASCustomNavBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.whiteColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        // ------- contentView（高度固定 44，贴 safeArea 顶部）-------
        self.contentView = [UIView new];
        self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentView.backgroundColor = UIColor.clearColor;
        [self addSubview:self.contentView];

        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.contentView.topAnchor constraintEqualToAnchor:safe.topAnchor],
            [self.contentView.heightAnchor constraintEqualToConstant:44.0],

            // 关键：让 self 的底部 = contentView 底部
            // 这样 self 的总高度 = safeAreaInsets.top + 44
            [self.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];

        // back button
        self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.backButton.tintColor = ASBlue();
        self.backButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];

        self.backIconView = [[UIImageView alloc] init];
        self.backIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.backIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.backIconView.tintColor = ASBlue();

        UIImage *img = nil;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:22
                                                           weight:UIImageSymbolWeightRegular
                                                            scale:UIImageSymbolScaleMedium];
            img = [[UIImage systemImageNamed:@"chevron.left"] imageWithConfiguration:cfg];
        } else {
            img = [UIImage imageNamed:@"chevron.left"];
        }
        self.backIconView.image = img;

        // title
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.text = title;
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = [UIColor colorWithWhite:0 alpha:1.0];

        // 建议：长标题在小屏/横屏更稳
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.75;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        // right button (Home)
        self.rightButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.rightButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.rightButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
        [self.rightButton addTarget:self action:@selector(rightTap) forControlEvents:UIControlEventTouchUpInside];

        self.rightIconView = [UIImageView new];
        self.rightIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.rightIconView.contentMode = UIViewContentModeScaleAspectFit;

        UIImage *home = [UIImage imageNamed:@"ic_home"];
        self.rightIconView.image = [home imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

        // 注意：都加到 contentView（不要加到 self）
        [self.contentView addSubview:self.backButton];
        [self.backButton addSubview:self.backIconView];
        [self.contentView addSubview:self.titleLabel];

        [self.contentView addSubview:self.rightButton];
        [self.rightButton addSubview:self.rightIconView];

        [NSLayoutConstraint activateConstraints:@[
            // back 44x44
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [self.backButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.backButton.widthAnchor constraintEqualToConstant:44],
            [self.backButton.heightAnchor constraintEqualToConstant:44],

            [self.backIconView.centerXAnchor constraintEqualToAnchor:self.backButton.centerXAnchor],
            [self.backIconView.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.backIconView.widthAnchor constraintEqualToConstant:13],
            [self.backIconView.heightAnchor constraintEqualToConstant:22],

            // right 44x44
            [self.rightButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [self.rightButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.rightButton.widthAnchor constraintEqualToConstant:44],
            [self.rightButton.heightAnchor constraintEqualToConstant:44],

            // home icon 24x24
            [self.rightIconView.centerXAnchor constraintEqualToAnchor:self.rightButton.centerXAnchor],
            [self.rightIconView.centerYAnchor constraintEqualToAnchor:self.rightButton.centerYAnchor],
            [self.rightIconView.widthAnchor constraintEqualToConstant:24],
            [self.rightIconView.heightAnchor constraintEqualToConstant:24],

            // title（以 contentView 为基准更准确）
            [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.titleLabel.heightAnchor constraintEqualToConstant:44],
            [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:72],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-72],
        ]];

        self.showRightButton = YES;
    }
    return self;
}

#pragma mark - 自适应高度（关键）

- (CGSize)intrinsicContentSize {
    // 总高度 = safeArea 顶部（刘海/状态栏高度） + 内容高度 44
    return CGSizeMake(UIViewNoIntrinsicMetric, self.safeAreaInsets.top + 44.0);
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self invalidateIntrinsicContentSize];
}

#pragma mark - Public

- (void)setShowRightButton:(BOOL)showRightButton {
    _showRightButton = showRightButton;
    self.rightButton.hidden = !showRightButton;
}

#pragma mark - Actions

- (void)backTap {
    if (self.onBack) self.onBack();
}

- (void)rightTap {
    if (self.onRight) self.onRight(self.allSelected);
}

@end
