#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "ImageCompressionManager.h"

@interface ImageCompressionProgressViewController : UIViewController
- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets
                       quality:(ASImageCompressionQuality)quality
               totalBeforeBytes:(uint64_t)beforeBytes
            estimatedAfterBytes:(uint64_t)afterBytes;
@end
