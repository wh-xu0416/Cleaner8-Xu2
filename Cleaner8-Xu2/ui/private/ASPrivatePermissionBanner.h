#import <UIKit/UIKit.h>

@interface ASPrivatePermissionBanner : UIControl
@property (nonatomic, copy) void(^onGoSettings)(void);
@end
