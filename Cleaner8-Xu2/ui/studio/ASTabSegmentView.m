#import "ASTabSegmentView.h"

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline CGFloat ASDesignWidth(void) { return 402.0; }
static inline CGFloat ASScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / ASDesignWidth());
}
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) {
    return [UIFont systemFontOfSize:round(s * ASScale()) weight:w];
}
@interface ASTabSegmentView ()
@property (nonatomic, strong) UIButton *photosBtn;
@property (nonatomic, strong) UIButton *videoBtn;
@property (nonatomic, strong) UIView *underline;
@property (nonatomic, strong) UIView *bottomLine;
@end

@implementation ASTabSegmentView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        self.backgroundColor = UIColor.whiteColor;

        _photosBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _videoBtn  = [UIButton buttonWithType:UIButtonTypeSystem];

        _photosBtn.translatesAutoresizingMaskIntoConstraints = NO;
        _videoBtn.translatesAutoresizingMaskIntoConstraints  = NO;

        [_photosBtn setTitle:@"Photos" forState:UIControlStateNormal];
        [_videoBtn  setTitle:@"Video"  forState:UIControlStateNormal];

        _photosBtn.titleLabel.font = ASFontS(24, UIFontWeightSemibold);
        _videoBtn.titleLabel.font  = ASFontS(24, UIFontWeightSemibold);

        _photosBtn.tag = 0;
        _videoBtn.tag  = 1;
        [_photosBtn addTarget:self action:@selector(onTap:) forControlEvents:UIControlEventTouchUpInside];
        [_videoBtn addTarget:self action:@selector(onTap:) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:_photosBtn];
        [self addSubview:_videoBtn];

        _underline = [UIView new];
        _underline.backgroundColor = ASBlue();
        [self addSubview:_underline];

        _bottomLine = [UIView new];
        _bottomLine.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
        _bottomLine.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_bottomLine];

        [NSLayoutConstraint activateConstraints:@[
            [_photosBtn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_photosBtn.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_photosBtn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_photosBtn.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5],

            [_videoBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_videoBtn.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_videoBtn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_videoBtn.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5],

            [_bottomLine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_bottomLine.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_bottomLine.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_bottomLine.heightAnchor constraintEqualToConstant:1],
        ]];

        self.selectedIndex = 0;
        [self applyStyle];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;

    CGFloat ulW = w * 0.34;

    CGFloat x = (self.selectedIndex == 0)
        ? (w * 0.5 - ulW) * 0.5
        : (w * 0.5) + (w * 0.5 - ulW) * 0.5;

    CGFloat h = 5.0;
    CGFloat y = self.bounds.size.height - h;

    self.underline.frame = CGRectMake(x, y, ulW, h);
    self.underline.layer.cornerRadius = 3.0;
    self.underline.layer.masksToBounds = YES;
}

- (void)onTap:(UIButton *)btn {
    [self setSelectedIndex:btn.tag animated:YES];
    if (self.onChange) self.onChange(btn.tag);
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    [self setSelectedIndex:selectedIndex animated:NO];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated {
    if (selectedIndex < 0) selectedIndex = 0;
    if (selectedIndex > 1) selectedIndex = 1;

    _selectedIndex = selectedIndex;
    [self applyStyle];

    if (!animated) { [self setNeedsLayout]; return; }

    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)applyStyle {
    UIColor *sel = ASBlue();
    UIColor *nor = [UIColor colorWithWhite:0 alpha:0.85];

    [self.photosBtn setTitleColor:(self.selectedIndex == 0 ? sel : nor) forState:UIControlStateNormal];
    [self.videoBtn  setTitleColor:(self.selectedIndex == 1 ? sel : nor) forState:UIControlStateNormal];
}

@end
