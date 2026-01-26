#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "ImageCompressionManager.h"

typedef void(^ASImageSelectionChangedBlock)(NSArray<PHAsset *> *selectedAssets);

@interface ImageCompressionQualityViewController : UIViewController
@property (nonatomic, copy) ASImageSelectionChangedBlock onSelectionChanged;

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets;
@end
