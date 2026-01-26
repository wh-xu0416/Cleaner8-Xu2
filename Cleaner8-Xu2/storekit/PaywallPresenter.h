#import <Foundation/Foundation.h>
#import "Cleaner8_Xu2-Swift.h"
#import <UIKit/UIKit.h> 

typedef void(^PaywallContinueBlock)(void);

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PaywallPresenterStateChanged;

@interface PaywallPresenter : NSObject

+ (instancetype)shared;

- (void)start;

@property (nonatomic, assign, readonly) SubscriptionState subscriptionState;

@property (nonatomic, assign, readonly) BOOL isProActive;

- (void)showPaywallIfNeededWithSource:(NSString * _Nullable)source;
- (void)showPaywallWithSource:(NSString * _Nullable)source;
- (void)showSubscriptionPageWithSource:(NSString * _Nullable)source;
- (void)dismissIfPresent;

typedef void(^PaywallContinueBlock)(void);

- (void)showPaywallIfNeededWithSource:(NSString * _Nullable)source
                           completion:(PaywallContinueBlock _Nullable)completion;

@end

NS_ASSUME_NONNULL_END
