#import <UIKit/UIKit.h>

@interface ASCustomNavBar : UIView

@property (nonatomic, strong, readonly) UIButton *backButton;
@property (nonatomic, strong, readonly) UILabel  *titleLabel;
@property (nonatomic, strong, readonly) UIButton *rightButton;

@property (nonatomic, copy) void (^onBack)(void);
@property (nonatomic, copy) void (^onRight)(BOOL isSelectedAll);

/// 是否处于“全选”状态
@property (nonatomic, assign, getter=isAllSelected) BOOL allSelected;

- (instancetype)initWithTitle:(NSString *)title;

@end
