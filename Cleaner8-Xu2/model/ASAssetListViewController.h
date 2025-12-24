#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, ASAssetListMode) {
    ASAssetListModeSimilarImage = 0,
    ASAssetListModeSimilarVideo,
    ASAssetListModeDuplicateImage,
    ASAssetListModeDuplicateVideo,
    ASAssetListModeScreenshots,
    ASAssetListModeScreenRecordings,
    ASAssetListModeBigVideos,
    ASAssetListModeBlurryPhotos,
    ASAssetListModeOtherPhotos,
};

@interface ASAssetListViewController : UIViewController
- (instancetype)initWithMode:(ASAssetListMode)mode;
@end
