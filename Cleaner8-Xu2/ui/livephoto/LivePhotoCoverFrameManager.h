#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "ImageCompressionManager.h" 

NS_ASSUME_NONNULL_BEGIN

@interface LivePhotoCoverFrameManager : NSObject
@property (atomic, readonly) BOOL isRunning;
- (void)cancel;

/// Live Photo -> Cover still (key photo)；可选删除原 Live（真省空间）
- (void)convertLiveAssets:(NSArray<PHAsset *> *)assets
           deleteOriginal:(BOOL)deleteOriginal
                 progress:(void(^)(NSInteger currentIndex,
                                   NSInteger totalCount,
                                   float overallProgress,
                                   PHAsset *currentAsset))progress
               completion:(void(^)(ASImageCompressionSummary * _Nullable summary,
                                   NSError * _Nullable error))completion;

/// 预估：before = live(photo+video)；after≈photo；saved≈pairedVideo
+ (void)estimateForAssets:(NSArray<PHAsset *> *)assets
          totalBeforeBytes:(uint64_t *)outBefore
       estimatedAfterBytes:(uint64_t *)outAfter
       estimatedSavedBytes:(uint64_t *)outSaved;

@end

NS_ASSUME_NONNULL_END
