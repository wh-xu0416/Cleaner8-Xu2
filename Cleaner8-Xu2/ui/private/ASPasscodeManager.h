#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString * const ASPasscodeChangedNotification;

@interface ASPasscodeManager : NSObject
+ (BOOL)isEnabled;
+ (BOOL)verify:(NSString *)code;       // 4位
+ (void)enableWithCode:(NSString *)code;
+ (void)disable;
@end
