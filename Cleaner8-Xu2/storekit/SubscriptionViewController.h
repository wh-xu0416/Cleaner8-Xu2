#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SubscriptionPaywallMode) {
    SubscriptionPaywallModeWeekly = 0, // 订阅列表默认周费
    SubscriptionPaywallModeYearly = 1, // 订阅列表默认年费
    SubscriptionPaywallModeGateWeekly   = 2, // 无订阅列表栏门周费
    SubscriptionPaywallModeGateYearly   = 3, // 无订阅列表栏门年费
};

typedef NS_ENUM(NSInteger, SubProgressPhase) {
    SubProgressPhaseMove = 0,
    SubProgressPhaseFade = 1,
};

@interface SubscriptionViewController : UIViewController
@property (nonatomic, copy) NSString *source;
- (instancetype)initWithMode:(SubscriptionPaywallMode)mode;
@end
