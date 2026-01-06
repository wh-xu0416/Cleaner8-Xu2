#import "UIViewController+ASPrivateBackground.h"
#import <objc/runtime.h>
#import "ASColors.h"

static const void *kASBGViewKey = &kASBGViewKey;
static const void *kASGradientKey = &kASGradientKey;

@implementation UIViewController (ASPrivateBackground)

- (void)as_applyPrivateBackground {
    self.view.backgroundColor = ASBG();

    UIView *bg = objc_getAssociatedObject(self, kASBGViewKey);
    if (!bg) {
        bg = [UIView new];
        bg.translatesAutoresizingMaskIntoConstraints = NO;
        bg.userInteractionEnabled = NO;
        bg.backgroundColor = UIColor.clearColor;

        [self.view insertSubview:bg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bg.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [bg.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [bg.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [bg.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];

        CAGradientLayer *g = [CAGradientLayer layer];
        g.colors = @[(id)ASTopGray().CGColor, (id)ASBlueTransparent().CGColor];
        g.startPoint = CGPointMake(0.5, 0.0);
        g.endPoint   = CGPointMake(0.5, 1.0);

        [bg.layer addSublayer:g];

        objc_setAssociatedObject(self, kASBGViewKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kASGradientKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [self as_updatePrivateBackgroundLayout];
}

- (void)as_updatePrivateBackgroundLayout {
    UIView *bg = objc_getAssociatedObject(self, kASBGViewKey);
    CAGradientLayer *g = objc_getAssociatedObject(self, kASGradientKey);
    if (!bg || !g) return;

    // 渐变只覆盖顶部 402 高度
    CGFloat width = self.view.bounds.size.width;
    g.frame = CGRectMake(0, 0, width, 402.0);
}

@end
