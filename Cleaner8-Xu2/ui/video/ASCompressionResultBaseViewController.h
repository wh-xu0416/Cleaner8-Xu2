#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@protocol ASCompressionResultSummary <NSObject>
@property (nonatomic, readonly) NSInteger inputCount;
@property (nonatomic, readonly) uint64_t beforeBytes;
@property (nonatomic, readonly) uint64_t afterBytes;
@property (nonatomic, readonly) uint64_t savedBytes;
@property (nonatomic, strong, readonly) NSArray<PHAsset *> *originalAssets; // 用于删原图/原视频、也可用来取封面
@end

@interface ASCompressionResultBaseViewController : UIViewController
- (instancetype)initWithSummary:(id<ASCompressionResultSummary>)summary;
@end
