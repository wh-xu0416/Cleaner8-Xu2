#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCustomNavBar : UIView

@property (nonatomic, strong, readonly) UIButton *backButton;
@property (nonatomic, strong, readonly) UILabel  *titleLabel;
@property (nonatomic, strong, readonly) UIButton *rightButton;

@property (nonatomic, assign) BOOL allSelected;
@property (nonatomic, assign) BOOL showRightButton;

@property (nonatomic, copy) void (^onBack)(void);
@property (nonatomic, copy) void (^onRight)(BOOL allSelected);

- (instancetype)initWithTitle:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
