#import "PrivateMediaCell.h"

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

@implementation PrivateMediaCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        self.contentView.clipsToBounds = YES;

        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        [self.contentView addSubview:_thumb];

        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
        self.thumb.clipsToBounds = YES;
        self.thumb.layer.magnificationFilter = kCAFilterTrilinear; 
        self.thumb.layer.minificationFilter  = kCAFilterTrilinear;

        _check = [UIImageView new];
        _check.translatesAutoresizingMaskIntoConstraints = NO;
        _check.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_check];

        self.checkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.checkButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.checkButton.backgroundColor = UIColor.clearColor;
        [self.checkButton addTarget:self action:@selector(checkTap) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.checkButton];

        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_check.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(8)],
            [_check.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AS(8)],
            [_check.widthAnchor constraintEqualToConstant:AS(20)],
            [_check.heightAnchor constraintEqualToConstant:AS(20)],

            [self.checkButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.checkButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.checkButton.widthAnchor constraintEqualToConstant:AS(44)],
            [self.checkButton.heightAnchor constraintEqualToConstant:AS(44)],
        ]];
    }
    return self;
}

- (void)setSelectedMark:(BOOL)selected {
    NSString *icon = selected ? @"ic_select_s" : @"ic_select_n";
    self.check.image = [[UIImage imageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)checkTap {
    if (self.onTapCheck) self.onTapCheck();
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedId = nil;
    self.thumb.image = nil;
    [self setSelectedMark:NO];
}

@end
