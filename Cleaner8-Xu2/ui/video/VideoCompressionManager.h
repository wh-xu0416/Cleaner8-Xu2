#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

typedef NS_ENUM(NSInteger, ASCompressionQuality) {
    ASCompressionQualitySmall = 0,
    ASCompressionQualityMedium,
    ASCompressionQualityLarge
};

@interface ASCompressionItemResult : NSObject
@property (nonatomic, strong) PHAsset *originalAsset;
@property (nonatomic) uint64_t beforeBytes;
@property (nonatomic) uint64_t afterBytes;
@property (nonatomic, strong) NSURL *outputURL; // temp file URL
@end

@interface ASCompressionSummary : NSObject
@property (nonatomic, strong) NSArray<ASCompressionItemResult *> *items;
@property (nonatomic) uint64_t totalBeforeBytes;
@property (nonatomic) uint64_t totalAfterBytes;
@property (nonatomic) uint64_t totalSavedBytes;
@end

@interface VideoCompressionManager : NSObject

@property (nonatomic, readonly) BOOL isRunning;

- (void)compressAssets:(NSArray<PHAsset *> *)assets
               quality:(ASCompressionQuality)quality
              progress:(void(^)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset))progress
            completion:(void(^)(ASCompressionSummary * _Nullable summary, NSError * _Nullable error))completion;

- (void)cancel;

@end
