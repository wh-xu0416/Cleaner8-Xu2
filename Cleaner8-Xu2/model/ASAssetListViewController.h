//
//  ASAssetListViewController.h
//  Cleaner8-Xu2
//
//  Created by 徐文豪 on 2025/12/16.
//


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
