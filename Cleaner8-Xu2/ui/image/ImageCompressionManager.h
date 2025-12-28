#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

typedef NS_ENUM(NSInteger, ASImageCompressionQuality) {
    ASImageCompressionQualitySmall,
    ASImageCompressionQualityMedium,
    ASImageCompressionQualityLarge,
};

@interface ASImageCompressionSummary : NSObject
@property (nonatomic) NSInteger inputCount;
@property (nonatomic) uint64_t beforeBytes;
@property (nonatomic) uint64_t afterBytes;
@property (nonatomic) uint64_t savedBytes;
@property (nonatomic, strong) NSArray<PHAsset *> *originalAssets;
@end

@interface ImageCompressionManager : NSObject
@property (atomic, readonly) BOOL isRunning;

- (void)cancel;

- (void)compressAssets:(NSArray<PHAsset *> *)assets
               quality:(ASImageCompressionQuality)quality
              progress:(void(^)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset))progress
            completion:(void(^)(ASImageCompressionSummary * _Nullable summary, NSError * _Nullable error))completion;

@end
