#import <UIKit/UIKit.h>

@interface ASStudioCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIImageView *playBadge;   // 视频显示
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;       // size 或 size • duration
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIButton *deleteButton;

- (void)showVideoBadge:(BOOL)show;
@end
