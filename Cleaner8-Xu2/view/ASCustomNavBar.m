#import "ASCustomNavBar.h"

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
}

@interface ASCustomNavBar ()
@property (nonatomic, strong, readwrite) UIButton *backButton;
@property (nonatomic, strong, readwrite) UILabel  *titleLabel;
@property (nonatomic, strong, readwrite) UIButton *rightButton;

@property (nonatomic, strong) UIImageView *rightIconView;
@end

@implementation ASCustomNavBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.clearColor;
        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        // back button
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.backButton.backgroundColor = UIColor.clearColor;
        self.backButton.adjustsImageWhenHighlighted = NO;
        self.backButton.showsTouchWhenHighlighted = NO;

        UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [self.backButton setImage:backImg forState:UIControlStateNormal];
        self.backButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10); // 44里放24
        self.backButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.backButton];

        // title
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.text = title;
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = [UIColor colorWithWhite:0 alpha:1.0];
        [self addSubview:self.titleLabel];

        // right button
        self.rightButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.rightButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.rightButton.backgroundColor = UIColor.clearColor;
        self.rightButton.adjustsImageWhenHighlighted = NO;
        self.rightButton.showsTouchWhenHighlighted = NO;
        self.rightButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
        [self.rightButton addTarget:self action:@selector(rightTap) forControlEvents:UIControlEventTouchUpInside];

        self.rightIconView = [UIImageView new];
        self.rightIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.rightIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.rightIconView.image = [[UIImage imageNamed:@"ic_home"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

        [self addSubview:self.rightButton];
        [self.rightButton addSubview:self.rightIconView];

        [NSLayoutConstraint activateConstraints:@[
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.backButton.widthAnchor constraintEqualToConstant:44],
            [self.backButton.heightAnchor constraintEqualToConstant:44],

            [self.rightButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [self.rightButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.rightButton.widthAnchor constraintEqualToConstant:44],
            [self.rightButton.heightAnchor constraintEqualToConstant:44],

            [self.rightIconView.centerXAnchor constraintEqualToAnchor:self.rightButton.centerXAnchor],
            [self.rightIconView.centerYAnchor constraintEqualToAnchor:self.rightButton.centerYAnchor],
            [self.rightIconView.widthAnchor constraintEqualToConstant:24],
            [self.rightIconView.heightAnchor constraintEqualToConstant:24],

            [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.titleLabel.heightAnchor constraintEqualToConstant:44],
            [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:72],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-72],
        ]];

        self.showRightButton = YES;
    }
    return self;
}

- (void)setShowRightButton:(BOOL)showRightButton {
    _showRightButton = showRightButton;
    self.rightButton.hidden = !showRightButton;
}

- (void)backTap {
    if (self.onBack) self.onBack();
}

- (void)rightTap {
    if (self.onRight) self.onRight(self.allSelected);
}

@end
