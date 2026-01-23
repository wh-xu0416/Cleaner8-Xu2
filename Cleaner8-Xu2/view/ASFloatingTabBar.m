#import "ASFloatingTabBar.h"
#import <objc/runtime.h>

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

static const void *kASIconViewKey = &kASIconViewKey;
static const void *kASTitleLabelKey = &kASTitleLabelKey;

static inline UIColor *ASColorHex(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8)  & 0xFF) / 255.0
                            blue:((rgb >> 0)  & 0xFF) / 255.0
                           alpha:alpha];
}

@implementation ASFloatingTabBarItem
+ (instancetype)itemWithTitle:(NSString *)title normal:(NSString *)n selected:(NSString *)s {
    ASFloatingTabBarItem *it = [ASFloatingTabBarItem new];
    it.title = title;
    it.normalImageName = n;
    it.selectedImageName = s;
    return it;
}
@end

@interface ASFloatingTabBar ()
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, strong) NSArray<ASFloatingTabBarItem *> *items;
@end

@implementation ASFloatingTabBar

- (instancetype)initWithItems:(NSArray<ASFloatingTabBarItem *> *)items {
    if (self = [super initWithFrame:CGRectZero]) {
        self.items = items;

        self.backgroundColor = UIColor.whiteColor;
        self.layer.masksToBounds = NO;

        self.layer.shadowColor = ASColorHex(0x000000, 0x1A / 255.0).CGColor;
        self.layer.shadowOpacity = 1.0;
        self.layer.shadowOffset = CGSizeMake(0, 0);
        self.layer.shadowRadius = SW(10.0);

        NSMutableArray *arr = [NSMutableArray array];

        for (NSInteger i = 0; i < items.count; i++) {
            ASFloatingTabBarItem *it = items[i];

            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = i;
            [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];

            [b setTitle:nil forState:UIControlStateNormal];
            [b setImage:nil forState:UIControlStateNormal];

            UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:it.normalImageName]];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [iv.widthAnchor constraintEqualToConstant:SW(31)],
                [iv.heightAnchor constraintEqualToConstant:SW(31)],
            ]];

            UILabel *lb = [UILabel new];
            lb.text = it.title;
            lb.font = SWFontS(10, UIFontWeightRegular);
            lb.textAlignment = NSTextAlignmentCenter;
            lb.textColor = ASColorHex(0x454545, 1.0);
            lb.numberOfLines = 1;
            lb.lineBreakMode = NSLineBreakByTruncatingTail;
            lb.adjustsFontSizeToFitWidth = YES;
            lb.minimumScaleFactor = 0.7;
            [lb setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                forAxis:UILayoutConstraintAxisHorizontal];


            lb.translatesAutoresizingMaskIntoConstraints = NO;

            [b addSubview:iv];
            [b addSubview:lb];

            CGFloat padLR = SW(10);
            CGFloat topPad = SW(10);
            CGFloat gap    = SW(4);
            CGFloat bottomPad = SW(8);

            [NSLayoutConstraint activateConstraints:@[
                [iv.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
                [iv.centerYAnchor constraintEqualToAnchor:b.centerYAnchor constant:-SW(8)],
                [iv.widthAnchor constraintEqualToConstant:SW(31)],
                [iv.heightAnchor constraintEqualToConstant:SW(31)],

                [lb.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:gap],
                [lb.leadingAnchor constraintGreaterThanOrEqualToAnchor:b.leadingAnchor constant:padLR],
                [lb.trailingAnchor constraintLessThanOrEqualToAnchor:b.trailingAnchor constant:-padLR],
                [lb.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
                [lb.bottomAnchor constraintLessThanOrEqualToAnchor:b.bottomAnchor constant:-bottomPad],
            ]];


            objc_setAssociatedObject(b, kASIconViewKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(b, kASTitleLabelKey, lb, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [self addSubview:b];
            [arr addObject:b];
        }

        self.buttons = arr;
        self.selectedIndex = 0;
        [self syncSelectionUI];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    NSInteger c = self.buttons.count;
    if (c <= 0) return;

    self.layer.cornerRadius = SW(40);

    self.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;

    CGFloat bw = w / c;
    for (NSInteger i = 0; i < c; i++) {
        UIButton *b = self.buttons[i];
        b.frame = CGRectMake(i * bw, 0, bw, h);
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self syncSelectionUI];
}

- (void)syncSelectionUI {
    for (UIButton *b in self.buttons) {
        NSInteger idx = b.tag;
        ASFloatingTabBarItem *it = self.items[idx];

        UIImageView *iv = (UIImageView *)objc_getAssociatedObject(b, kASIconViewKey);
        UILabel *lb = (UILabel *)objc_getAssociatedObject(b, kASTitleLabelKey);

        BOOL sel = (idx == self.selectedIndex);

        iv.image = [UIImage imageNamed:(sel ? it.selectedImageName : it.normalImageName)];
        lb.textColor = sel ? ASColorHex(0x000000, 1.0) : ASColorHex(0x454545, 0.5);
        lb.font = sel ? SWFontS(10, UIFontWeightSemibold) : SWFontS(10, UIFontWeightRegular);
    }
}

- (void)tap:(UIButton *)sender {
    self.selectedIndex = sender.tag;
    if (self.onSelect) self.onSelect(sender.tag);
}

@end
