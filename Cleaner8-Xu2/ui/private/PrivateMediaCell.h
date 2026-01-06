#import <UIKit/UIKit.h>

@interface PrivateMediaCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UIImageView *check;
@property (nonatomic, strong) UIButton *checkButton;
@property (nonatomic, copy) void(^onTapCheck)(void);
@property (nonatomic, copy) NSString *representedId;
- (void)setSelectedMark:(BOOL)selected;
@end
