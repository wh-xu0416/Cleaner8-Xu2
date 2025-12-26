#import "ASCustomNavBar.h"

@interface ASCustomNavBar ()

@property (nonatomic, strong, readwrite) UIButton *backButton;
@property (nonatomic, strong, readwrite) UILabel  *titleLabel;

@property (nonatomic, assign) CGFloat statusH;

@end

@implementation ASCustomNavBar

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = UIColor.whiteColor;

        if (@available(iOS 13.0, *)) {
            self.statusH = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets.top;
        } else {
            self.statusH = 20;
        }

        // 返回按钮
        self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
        [self.backButton addTarget:self action:@selector(backTap) forControlEvents:UIControlEventTouchUpInside];

        // 标题
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;

        [self addSubview:self.backButton];
        [self addSubview:self.titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat h = 44;
    CGFloat y = self.statusH;
    CGFloat w = self.bounds.size.width;

    self.backButton.frame  = CGRectMake(12, y, 44, h);
    self.titleLabel.frame  = CGRectMake(72, y, w - 144, h);
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.statusH + 44);
}

- (void)backTap {
    if (self.onBack) {
        self.onBack();
    }
}

@end
