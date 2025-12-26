#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "VideoCompressionManager.h"

@interface VideoCompressionProgressViewController : UIViewController
- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets quality:(ASCompressionQuality)quality;
@end
