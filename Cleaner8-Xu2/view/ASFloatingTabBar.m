#import "ASFloatingTabBar.h"
#import <objc/runtime.h>

static const void *kASIconViewKey = &kASIconViewKey;
static const void *kASTitleLabelKey = &kASTitleLabelKey;

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

        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        self.layer.masksToBounds = NO;

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, 6);

        NSMutableArray *arr = [NSMutableArray array];

        for (NSInteger i = 0; i < items.count; i++) {
            ASFloatingTabBarItem *it = items[i];

            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = i;
            [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];

            // 让按钮自己不渲染 title/image（避免 inset 问题）
            [b setTitle:nil forState:UIControlStateNormal];
            [b setImage:nil forState:UIControlStateNormal];

            UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:it.normalImageName]];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [iv.widthAnchor constraintEqualToConstant:22],
                [iv.heightAnchor constraintEqualToConstant:22],
            ]];

            UILabel *lb = [UILabel new];
            lb.text = it.title;
            lb.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
            lb.textAlignment = NSTextAlignmentCenter;
            lb.textColor = [UIColor colorWithWhite:1 alpha:0.55];

            UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iv, lb]];
            stack.axis = UILayoutConstraintAxisVertical;
            stack.alignment = UIStackViewAlignmentCenter;
            stack.spacing = 4;
            stack.userInteractionEnabled = NO;
            stack.translatesAutoresizingMaskIntoConstraints = NO;

            [b addSubview:stack];
            [NSLayoutConstraint activateConstraints:@[
                [stack.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
                [stack.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
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

    self.layer.cornerRadius = h / 2.0;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;

    CGFloat bw = w / c;

    for (NSInteger i = 0; i < c; i++) {
        UIButton *b = self.buttons[i];
        b.frame = CGRectMake(i * bw, 0, bw, h);

        // 关键：让图在上、字在下（手动算 inset）
        CGSize imgSize = CGSizeMake(22, 22);
        CGFloat spacing = 4;

        // 设置 imageView 大小（仅用于 inset 计算）
        b.imageEdgeInsets = UIEdgeInsetsZero;
        b.titleEdgeInsets = UIEdgeInsetsZero;
        b.contentEdgeInsets = UIEdgeInsetsZero;

        // 先确保 image/title 都有
        NSString *title = [b titleForState:UIControlStateNormal] ?: @"";
        CGSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName:b.titleLabel.font}];

        CGFloat totalH = imgSize.height + spacing + titleSize.height;

        CGFloat imgTop = (h - totalH) / 2.0;
        CGFloat titleTop = imgTop + imgSize.height + spacing;

        // 通过 inset 把 image/title 放到目标位置
        // 这里用“相对中心”偏移技巧
        CGFloat imgOffsetY = imgTop - (h - imgSize.height) / 2.0;
        CGFloat titleOffsetY = titleTop - (h - titleSize.height) / 2.0;

        b.imageEdgeInsets = UIEdgeInsetsMake(imgOffsetY, 0, -imgOffsetY, -titleSize.width);
        b.titleEdgeInsets = UIEdgeInsetsMake(titleOffsetY, -imgSize.width, -titleOffsetY, 0);
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
        lb.textColor = sel ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.55];
    }
}

- (void)tap:(UIButton *)sender {
    self.selectedIndex = sender.tag;
    if (self.onSelect) self.onSelect(sender.tag);
}

@end
