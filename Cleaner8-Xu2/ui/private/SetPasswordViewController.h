#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ASPasswordFlow) {
    ASPasswordFlowSet = 0,       // 设置并二次确认
    ASPasswordFlowVerify = 1,    // 验证通过后进入详情
    ASPasswordFlowDisable = 2,   // 验证通过后关闭密码
};

@interface SetPasswordViewController : UIViewController
@property (nonatomic, assign) ASPasswordFlow flow;
@property (nonatomic, copy) void(^onSuccess)(void);
@end
