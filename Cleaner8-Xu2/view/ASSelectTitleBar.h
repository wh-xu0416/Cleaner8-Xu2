#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASSelectTitleBar : UIView

@property (nonatomic, strong, readonly) UIButton *backButton;
@property (nonatomic, strong, readonly) UILabel  *titleLabel;
@property (nonatomic, strong, readonly) UIButton *selectAllButton;

@property (nonatomic, assign) BOOL allSelected;        // 控制右侧 UI：Select All / Deselect All + icon
@property (nonatomic, assign) BOOL showTitle;          // 外部控制标题显示隐藏
@property (nonatomic, assign) BOOL showSelectButton;   // 外部控制右侧按钮显示隐藏

@property (nonatomic, copy, nullable) void (^onBack)(void);
@property (nonatomic, copy, nullable) void (^onToggleSelectAll)(BOOL allSelected);

- (instancetype)initWithTitle:(NSString *)title;
- (void)setTitleText:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
