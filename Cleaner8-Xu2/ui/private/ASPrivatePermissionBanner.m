#import "ASPrivatePermissionBanner.h"
#import "ASColors.h"
#import "Common.h"

#pragma mark - Adapt Helpers

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
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }

@implementation ASPrivatePermissionBanner {
    UILabel *_title;
    UIButton *_btn;
    UIImageView *_arrow;

    NSLayoutConstraint *_cTitleTop;
    NSLayoutConstraint *_cBtnBottom;
    NSLayoutConstraint *_cBtnTopToTitle;
    NSLayoutConstraint *_cBtnMinH;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = AS(16);
        self.layer.masksToBounds = YES;

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.text = NSLocalizedString(@"Full Photo Access Required", nil);
        _title.textColor = UIColor.blackColor;
        _title.font = ASFontS(17, UIFontWeightMedium);
        _title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_title];

        _btn = [UIButton buttonWithType:UIButtonTypeCustom];
        _btn.translatesAutoresizingMaskIntoConstraints = NO;
        _btn.backgroundColor = ASBlue();
        _btn.layer.cornerRadius = AS(25);
        _btn.layer.masksToBounds = YES;
        [_btn addTarget:self action:@selector(go) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_btn];

        UILabel *t = [UILabel new];
        t.translatesAutoresizingMaskIntoConstraints = NO;
        t.text = NSLocalizedString(@"Go to Settings", nil);
        t.textColor = UIColor.whiteColor;
        t.font = ASFontS(20, UIFontWeightMedium);
        [_btn addSubview:t];

        _arrow = [UIImageView new];
        _arrow.translatesAutoresizingMaskIntoConstraints = NO;
        _arrow.contentMode = UIViewContentModeScaleAspectFit;
        _arrow.image = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [_btn addSubview:_arrow];

        _cTitleTop = [_title.topAnchor constraintEqualToAnchor:self.topAnchor constant:AS(27)];
        _cBtnBottom = [_btn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-AS(27)];
        _cBtnTopToTitle = [_btn.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:AS(20)];
        _cBtnMinH = [_btn.heightAnchor constraintGreaterThanOrEqualToConstant:AS(50)];

        _cTitleTop.priority = 999;
        _cBtnBottom.priority = 999;
        _cBtnTopToTitle.priority = 999;
        _cBtnMinH.priority = 999;
        
        [NSLayoutConstraint activateConstraints:@[
            _cTitleTop,
            [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AS(16)],
            [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AS(16)],

            _cBtnBottom,
            [_btn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            _cBtnMinH,
            _cBtnTopToTitle,

            [t.leadingAnchor constraintEqualToAnchor:_btn.leadingAnchor constant:AS(32)],
            [t.topAnchor constraintEqualToAnchor:_btn.topAnchor constant:AS(10)],
            [t.bottomAnchor constraintEqualToAnchor:_btn.bottomAnchor constant:-AS(10)],
            [t.centerYAnchor constraintEqualToAnchor:_btn.centerYAnchor],

            [_arrow.leadingAnchor constraintEqualToAnchor:t.trailingAnchor constant:AS(10)],
            [_arrow.centerYAnchor constraintEqualToAnchor:_btn.centerYAnchor],
            [_arrow.widthAnchor constraintEqualToConstant:AS(9)],
            [_arrow.heightAnchor constraintEqualToConstant:AS(15)],
            [_arrow.trailingAnchor constraintEqualToAnchor:_btn.trailingAnchor constant:-AS(32)],
        ]];
    }
    return self;
}

- (void)go {
    if (self.onGoSettings) self.onGoSettings();
}

@end
