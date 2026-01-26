#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASTabSegmentView : UIView
@property (nonatomic, assign) NSInteger selectedIndex; // 0 Photos, 1 Video
@property (nonatomic, copy) void(^onChange)(NSInteger idx);
- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
