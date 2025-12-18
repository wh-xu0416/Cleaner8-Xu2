#import <UIKit/UIKit.h>


typedef NS_ENUM(NSUInteger, ASAssetListMode) {
    ASAssetListModeSimilarImage = 0,
    ASAssetListModeSimilarVideo,
    ASAssetListModeDuplicateImage,
    ASAssetListModeDuplicateVideo,
    ASAssetListModeScreenshots,
    ASAssetListModeScreenRecordings,
    ASAssetListModeBigVideos,
};

@interface ASAssetListViewController : UIViewController
- (instancetype)initWithMode:(ASAssetListMode)mode;
@end
