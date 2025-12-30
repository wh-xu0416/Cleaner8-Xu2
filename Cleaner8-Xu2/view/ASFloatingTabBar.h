#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASFloatingTabBarItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *normalImageName;
@property (nonatomic, copy) NSString *selectedImageName;
+ (instancetype)itemWithTitle:(NSString *)title normal:(NSString *)n selected:(NSString *)s;
@end

@interface ASFloatingTabBar : UIView
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger idx);
- (instancetype)initWithItems:(NSArray<ASFloatingTabBarItem *> *)items;
@end

NS_ASSUME_NONNULL_END
