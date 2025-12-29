#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASMediaPreviewViewController : UIViewController

/// assets: PHAsset（图片/视频/LivePhoto）
/// initialIndex: 初始显示下标
- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets initialIndex:(NSInteger)initialIndex;

/// 默认 bestIndex = 0
@property (nonatomic, assign) NSInteger bestIndex;

/// 是否展示 Best（默认 YES；当 assets.count==1 时会强制不显示）
@property (nonatomic, assign) BOOL showsBestBadge;

/// 选中结果回传（返回时触发）
/// selectedAssets：按原 assets 顺序过滤后的选中资源
/// selectedIndexes：选中下标集合
@property (nonatomic, copy, nullable) void(^onBack)(NSArray<PHAsset *> *selectedAssets, NSIndexSet *selectedIndexes);

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets
                  initialIndex:(NSInteger)initialIndex
               selectedIndexes:(NSIndexSet *)selectedIndexes;

@end

NS_ASSUME_NONNULL_END
