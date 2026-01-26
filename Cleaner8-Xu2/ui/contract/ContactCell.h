#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactCell : UICollectionViewCell

@property (nonatomic, strong) UILabel *nameLabel; // 显示姓名
@property (nonatomic, strong) UILabel *phoneLabel; // 显示电话
@property (nonatomic, strong) UIButton *checkButton; // 选择按钮
@property (nonatomic, copy) void (^onSelect)(void); // 选择按钮的点击事件

@end

NS_ASSUME_NONNULL_END
