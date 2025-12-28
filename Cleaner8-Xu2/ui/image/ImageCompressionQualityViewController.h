#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "ImageCompressionManager.h"

@interface ImageCompressionQualityViewController : UIViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets;
@end
