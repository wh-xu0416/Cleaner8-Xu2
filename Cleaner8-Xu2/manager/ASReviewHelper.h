#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASReviewHelper : NSObject

+ (void)requestReviewOnceFromViewController:(nullable UIViewController *)vc
                                     source:(NSString *)source;

@end

NS_ASSUME_NONNULL_END
