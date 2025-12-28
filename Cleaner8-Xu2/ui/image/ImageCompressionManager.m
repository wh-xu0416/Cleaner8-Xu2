#import "ImageCompressionManager.h"
#import <UIKit/UIKit.h>

#import "ASStudioAlbumManager.h"
#import "ASStudioStore.h"
#import "ASStudioUtils.h"

@implementation ASImageCompressionSummary
@end

double ASImageRemainRatioForQuality(ASImageCompressionQuality q) {
    switch (q) {
        case ASImageCompressionQualitySmall:  return 0.20;
        case ASImageCompressionQualityMedium: return 0.50;
        case ASImageCompressionQualityLarge:  return 0.80;
    }
}

static NSString *ASQualitySuffix(ASImageCompressionQuality q) {
    switch (q) {
        case ASImageCompressionQualitySmall:  return @"S";
        case ASImageCompressionQualityMedium: return @"M";
        case ASImageCompressionQualityLarge:  return @"L";
    }
}

static CGFloat ASJPEGQualityForQuality(ASImageCompressionQuality q) {
    // 真正 JPEG re-encode 的压缩强度（不等于 remain ratio，只用于输出数据）
    switch (q) {
        case ASImageCompressionQualitySmall:  return 0.35;
        case ASImageCompressionQualityMedium: return 0.60;
        case ASImageCompressionQualityLarge:  return 0.80;
    }
}

static uint64_t ASAssetFileSize(PHAsset *asset) {
    PHAssetResource *r = [PHAssetResource assetResourcesForAsset:asset].firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

@interface ImageCompressionManager ()
@property (atomic) BOOL cancelFlag;
@property (atomic, readwrite) BOOL isRunning;
@property (atomic) PHImageRequestID currentRequestID;
@property (nonatomic, strong) dispatch_queue_t workQ;
@end

@implementation ImageCompressionManager

- (instancetype)init {
    if (self = [super init]) {
        _workQ = dispatch_queue_create("img.compress.workQ", DISPATCH_QUEUE_SERIAL);
        _currentRequestID = PHInvalidImageRequestID;
    }
    return self;
}

- (void)cancel {
    self.cancelFlag = YES;
    PHImageRequestID rid = self.currentRequestID;
    if (rid != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:rid];
    }
}

- (void)compressAssets:(NSArray<PHAsset *> *)assets
               quality:(ASImageCompressionQuality)quality
              progress:(void(^)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset))progress
            completion:(void(^)(ASImageCompressionSummary * _Nullable summary, NSError * _Nullable error))completion {

    if (self.isRunning) return;
    self.isRunning = YES;
    self.cancelFlag = NO;

    NSArray<PHAsset *> *input = assets ?: @[];
    NSInteger total = input.count;

    dispatch_async(self.workQ, ^{
        uint64_t beforeSum = 0;
        uint64_t afterSum = 0;

        for (PHAsset *a in input) beforeSum += ASAssetFileSize(a);

        // 先确保 album
        __block PHAssetCollection *studioAlbum = nil;
        dispatch_semaphore_t albumSema = dispatch_semaphore_create(0);
        [[ASStudioAlbumManager shared] fetchOrCreateAlbum:^(PHAssetCollection * _Nullable album, NSError * _Nullable error) {
            studioAlbum = album;
            dispatch_semaphore_signal(albumSema);
        }];
        dispatch_semaphore_wait(albumSema, DISPATCH_TIME_FOREVER);

        for (NSInteger i = 0; i < total; i++) {
            if (self.cancelFlag) break;

            PHAsset *asset = input[i];
            if (progress) progress(i, total, (float)i / MAX(total, 1), asset);

            __block NSData *imageData = nil;

            PHImageRequestOptions *opt = [PHImageRequestOptions new];
            opt.networkAccessAllowed = YES;
            opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            opt.resizeMode = PHImageRequestOptionsResizeModeNone;
            opt.synchronous = NO;

            dispatch_semaphore_t sema = dispatch_semaphore_create(0);

            PHImageRequestID rid = PHInvalidImageRequestID;
            if (@available(iOS 13.0, *)) {
                rid = [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset
                                                                                     options:opt
                                                                               resultHandler:^(NSData * _Nullable data, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
                    NSNumber *degraded = info[PHImageResultIsDegradedKey];
                    if (degraded.boolValue) return;
                    imageData = data;
                    dispatch_semaphore_signal(sema);
                }];
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                rid = [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                                       options:opt
                                                                 resultHandler:^(NSData * _Nullable data, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
                    NSNumber *degraded = info[PHImageResultIsDegradedKey];
                    if (degraded.boolValue) return;
                    imageData = data;
                    dispatch_semaphore_signal(sema);
                }];
#pragma clang diagnostic pop
            }

            self.currentRequestID = rid;
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
            self.currentRequestID = PHInvalidImageRequestID;

            if (self.cancelFlag) break;
            if (!imageData) continue;

            UIImage *img = [UIImage imageWithData:imageData];
            if (!img) continue;

            NSData *jpg = UIImageJPEGRepresentation(img, ASJPEGQualityForQuality(quality));
            if (!jpg) continue;

            afterSum += (uint64_t)jpg.length;

            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"imgc_%@.jpg", NSUUID.UUID.UUIDString]];
            NSURL *url = [NSURL fileURLWithPath:tmp];
            [jpg writeToURL:url atomically:YES];

            // ✅ 保存到系统相册 + 加入 My Studio album + 拿到 assetId
            dispatch_semaphore_t saveSema = dispatch_semaphore_create(0);
            __block BOOL saveOK = NO;
            __block NSString *createdAssetId = nil;

            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetChangeRequest *req =
                [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
                PHObjectPlaceholder *ph = req.placeholderForCreatedAsset;
                createdAssetId = ph.localIdentifier;

                if (studioAlbum) {
                    [ASStudioAlbumManager addPlaceholder:ph toAlbum:studioAlbum];
                }
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                saveOK = success;
                dispatch_semaphore_signal(saveSema);
            }];

            dispatch_semaphore_wait(saveSema, DISPATCH_TIME_FOREVER);
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

            if (saveOK && createdAssetId.length > 0) {
                // ✅ 写入索引（历史记录）
                ASStudioItem *item = [ASStudioItem new];
                item.assetId = createdAssetId;
                item.type = ASStudioMediaTypePhoto;
                item.afterBytes = (int64_t)jpg.length;
                item.beforeBytes = (int64_t)ASAssetFileSize(asset);
                item.compressedAt = [NSDate date];
                item.duration = 0;
                item.displayName = [ASStudioUtils makeDisplayNameForPhotoWithQualitySuffix:ASQualitySuffix(quality)];
                [[ASStudioStore shared] upsertItem:item];
            }

            if (progress) progress(i+1, total, (float)(i+1) / MAX(total, 1), asset);
        }

        self.isRunning = NO;

        if (self.cancelFlag) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain code:-999 userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, err);
            });
            return;
        }

        ASImageCompressionSummary *sum = [ASImageCompressionSummary new];
        sum.inputCount = total;
        sum.beforeBytes = beforeSum;
        sum.afterBytes = afterSum;
        sum.savedBytes = (beforeSum > afterSum) ? (beforeSum - afterSum) : 0;
        sum.originalAssets = input;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(sum, nil);
        });
    });
}

@end
