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
@end

@implementation ASCustomNavBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.whiteColor;

        UILayoutGuide *safe = self.safeAreaLayoutGuide;

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

        [self addSubview:self.backButton];
        [self.backButton addSubview:self.backIconView];
        [self addSubview:self.titleLabel];

        [self addSubview:self.rightButton];
        [self.rightButton addSubview:self.rightIconView];

        [NSLayoutConstraint activateConstraints:@[
            // back 44x44
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.backButton.widthAnchor constraintEqualToConstant:44],
            [self.backButton.heightAnchor constraintEqualToConstant:44],

            [self.backIconView.centerXAnchor constraintEqualToAnchor:self.backButton.centerXAnchor],
            [self.backIconView.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.backIconView.widthAnchor constraintEqualToConstant:13],
            [self.backIconView.heightAnchor constraintEqualToConstant:22],

            // right 44x44
            [self.rightButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [self.rightButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.rightButton.widthAnchor constraintEqualToConstant:44],
            [self.rightButton.heightAnchor constraintEqualToConstant:44],

            // home icon 24x24
            [self.rightIconView.centerXAnchor constraintEqualToAnchor:self.rightButton.centerXAnchor],
            [self.rightIconView.centerYAnchor constraintEqualToAnchor:self.rightButton.centerYAnchor],
            [self.rightIconView.widthAnchor constraintEqualToConstant:24],
            [self.rightIconView.heightAnchor constraintEqualToConstant:24],

            // title 44 high
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
