#import "ASCustomNavBar.h"

@interface ASCustomNavBar ()
@property (nonatomic, strong, readwrite) UIButton *backButton;
@property (nonatomic, strong, readwrite) UILabel  *titleLabel;
@property (nonatomic, strong) UIImageView *backIconView;
@end

@implementation ASCustomNavBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.whiteColor;

        // back button
        self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.backButton.tintColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];

        // icon
        self.backIconView = [[UIImageView alloc] init];
        self.backIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.backIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.backIconView.tintColor = self.backButton.tintColor;

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

        [self addSubview:self.backButton];
        [self.backButton addSubview:self.backIconView];
        [self addSubview:self.titleLabel];

        // ✅ 用 safeAreaLayoutGuide，不要自己算 statusH
        UILayoutGuide *safe = self.safeAreaLayoutGuide;

        [NSLayoutConstraint activateConstraints:@[
            // back button 44x44，贴 safeArea 顶部
            [self.backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.backButton.widthAnchor constraintEqualToConstant:44],
            [self.backButton.heightAnchor constraintEqualToConstant:44],

            // icon inside button
            [self.backIconView.centerXAnchor constraintEqualToAnchor:self.backButton.centerXAnchor],
            [self.backIconView.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
            [self.backIconView.widthAnchor constraintEqualToConstant:13],
            [self.backIconView.heightAnchor constraintEqualToConstant:22],

            // title
            [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0],
            [self.titleLabel.heightAnchor constraintEqualToConstant:44],

            [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:72],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-72],
        ]];
    }
    return self;
}

- (void)backTap {
    if (self.onBack) self.onBack();
}

@end
