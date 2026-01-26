#import "LivePhotoCoverFrameManager.h"
#import <UIKit/UIKit.h>

#import "ASStudioAlbumManager.h"
#import "ASStudioStore.h"
#import "ASStudioUtils.h"

static uint64_t ASResourceFileSize(PHAssetResource *r) {
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; }
    @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

/// 统计 Live Photo：photo bytes & pairedVideo bytes
static void ASLiveBytes(PHAsset *asset, uint64_t *outPhoto, uint64_t *outVideo) {
    uint64_t p = 0, v = 0;
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypePhoto ||
            r.type == PHAssetResourceTypeFullSizePhoto) {
            p += ASResourceFileSize(r);
        } else if (r.type == PHAssetResourceTypePairedVideo) {
            v += ASResourceFileSize(r);
        }
    }
    if (outPhoto) *outPhoto = p;
    if (outVideo) *outVideo = v;
}

static BOOL ASIsLiveAsset(PHAsset *a) {
    return (a.mediaType == PHAssetMediaTypeImage) &&
           ((a.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0);
}

/// UTI -> extension（尽量保留原编码）
static NSString *ASExtForUTI(NSString *uti) {
    if ([uti containsString:@"heic"] || [uti containsString:@"heif"]) return @"heic";
    if ([uti containsString:@"jpeg"] || [uti containsString:@"jpg"]) return @"jpg";
    if ([uti containsString:@"png"]) return @"png";
    return @"jpg";
}

@interface LivePhotoCoverFrameManager ()
@property (atomic) BOOL cancelFlag;
@property (atomic, readwrite) BOOL isRunning;
@property (atomic) PHImageRequestID currentRequestID;
@property (nonatomic, strong) dispatch_queue_t workQ;
@end

@implementation LivePhotoCoverFrameManager

- (instancetype)init {
    if (self = [super init]) {
        _workQ = dispatch_queue_create("live.cover.convert.workQ", DISPATCH_QUEUE_SERIAL);
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

+ (void)estimateForAssets:(NSArray<PHAsset *> *)assets
          totalBeforeBytes:(uint64_t *)outBefore
       estimatedAfterBytes:(uint64_t *)outAfter
       estimatedSavedBytes:(uint64_t *)outSaved {

    uint64_t before = 0, after = 0, saved = 0;

    for (PHAsset *a in assets) {
        if (!ASIsLiveAsset(a)) continue;
        uint64_t p = 0, v = 0;
        ASLiveBytes(a, &p, &v);
        before += (p + v);
        after  += p;
        saved  += v;
    }

    if (outBefore) *outBefore = before;
    if (outAfter)  *outAfter  = after;
    if (outSaved)  *outSaved  = saved;
}

- (void)convertLiveAssets:(NSArray<PHAsset *> *)assets
           deleteOriginal:(BOOL)deleteOriginal
                 progress:(void(^)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset))progress
               completion:(void(^)(ASImageCompressionSummary * _Nullable summary, NSError * _Nullable error))completion {

    if (self.isRunning) return;
    self.isRunning = YES;
    self.cancelFlag = NO;

    NSArray<PHAsset *> *input = assets ?: @[];
    NSInteger total = input.count;

    dispatch_async(self.workQ, ^{
        uint64_t beforeSum = 0;
        uint64_t afterSum  = 0;

        // 统计 before（live photo+paired video）
        for (PHAsset *a in input) {
            if (!ASIsLiveAsset(a)) continue;
            uint64_t p=0,v=0; ASLiveBytes(a,&p,&v);
            beforeSum += (p+v);
        }

        // 先确保 album
        __block PHAssetCollection *studioAlbum = nil;
        dispatch_semaphore_t albumSema = dispatch_semaphore_create(0);
        [[ASStudioAlbumManager shared] fetchOrCreateAlbum:^(PHAssetCollection * _Nullable album, NSError * _Nullable error) {
            studioAlbum = album;
            dispatch_semaphore_signal(albumSema);
        }];
        dispatch_semaphore_wait(albumSema, DISPATCH_TIME_FOREVER);

        for (NSInteger i = 0; i < total; i++) {
            @autoreleasepool {
                if (self.cancelFlag) break;

                PHAsset *asset = input[i];
                if (!ASIsLiveAsset(asset)) {
                    if (progress) progress(i+1, total, (float)(i+1)/MAX(total,1), asset);
                    continue;
                }

                if (progress) progress(i, total, (float)i / MAX(total, 1), asset);

                __block NSData *stillData = nil;
                __block NSString *uti = nil;

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
                                                                                   resultHandler:^(NSData * _Nullable data,
                                                                                                   NSString * _Nullable dataUTI,
                                                                                                   CGImagePropertyOrientation orientation,
                                                                                                   NSDictionary * _Nullable info) {
                        if ([info[PHImageCancelledKey] boolValue]) return;
                        if ([info[PHImageResultIsDegradedKey] boolValue]) return;
                        stillData = data;
                        uti = dataUTI;
                        dispatch_semaphore_signal(sema);
                    }];
                } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    rid = [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                                           options:opt
                                                                     resultHandler:^(NSData * _Nullable data,
                                                                                     NSString * _Nullable dataUTI,
                                                                                     UIImageOrientation orientation,
                                                                                     NSDictionary * _Nullable info) {
                        if ([info[PHImageCancelledKey] boolValue]) return;
                        if ([info[PHImageResultIsDegradedKey] boolValue]) return;
                        stillData = data;
                        uti = dataUTI;
                        dispatch_semaphore_signal(sema);
                    }];
#pragma clang diagnostic pop
                }

                self.currentRequestID = rid;
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                self.currentRequestID = PHInvalidImageRequestID;

                if (self.cancelFlag) break;
                if (!stillData.length) {
                    if (progress) progress(i+1, total, (float)(i+1)/MAX(total,1), asset);
                    continue;
                }

                // 写临时文件（尽量保留原编码 HEIC/JPEG）
                NSString *ext = ASExtForUTI(uti ?: @"");
                NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"livecover_%@.%@", NSUUID.UUID.UUIDString, ext]];
                NSURL *url = [NSURL fileURLWithPath:tmp];

                BOOL wrote = [stillData writeToURL:url atomically:YES];
                if (!wrote) {
                    // fallback：decode -> jpeg
                    UIImage *img = [UIImage imageWithData:stillData];
                    NSData *jpg = img ? UIImageJPEGRepresentation(img, 0.92) : nil;
                    if (!jpg.length) {
                        if (progress) progress(i+1, total, (float)(i+1)/MAX(total,1), asset);
                        continue;
                    }
                    afterSum += (uint64_t)jpg.length;
                    NSString *tmp2 = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"livecover_%@.jpg", NSUUID.UUID.UUIDString]];
                    NSURL *url2 = [NSURL fileURLWithPath:tmp2];
                    [jpg writeToURL:url2 atomically:YES];
                    url = url2;
                    stillData = jpg;
                    ext = @"jpg";
                } else {
                    afterSum += (uint64_t)stillData.length;
                }

                // 保存到系统相册（可选删除原 Live）
                dispatch_semaphore_t saveSema = dispatch_semaphore_create(0);
                __block BOOL saveOK = NO;
                __block NSError *saveErr = nil;
                __block NSString *createdAssetId = nil;

                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetChangeRequest *req = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
                    PHObjectPlaceholder *ph = req.placeholderForCreatedAsset;
                    createdAssetId = ph.localIdentifier;

                    if (studioAlbum) {
                        [ASStudioAlbumManager addPlaceholder:ph toAlbum:studioAlbum];
                    }

                    if (deleteOriginal) {
                        [PHAssetChangeRequest deleteAssets:@[asset]];
                    }
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    saveOK = success;
                    saveErr = error;
                    dispatch_semaphore_signal(saveSema);
                }];

                dispatch_semaphore_wait(saveSema, DISPATCH_TIME_FOREVER);
                [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

                if (!saveOK) {
                    // 失败时，把 afterSum 回滚掉这张（避免统计虚高）
                    if (afterSum >= (uint64_t)stillData.length) afterSum -= (uint64_t)stillData.length;

                    // 如果是权限/limited 导致 delete 失败，区分处理
                    (void)saveErr;
                }

                if (saveOK && createdAssetId.length > 0) {
                    // 写入索引
                    uint64_t p=0,v=0; ASLiveBytes(asset,&p,&v);

                    ASStudioItem *item = [ASStudioItem new];
                    item.assetId = createdAssetId;
                    item.type = ASStudioMediaTypePhoto;
                    item.afterBytes = (int64_t)stillData.length;
                    item.beforeBytes = (int64_t)(p+v);
                    item.compressedAt = [NSDate date];
                    item.duration = 0;
                    item.displayName = @"Live Cover Frame";
                    [[ASStudioStore shared] upsertItem:item];
                }

                if (progress) progress(i+1, total, (float)(i+1) / MAX(total, 1), asset);
            }
        }

        self.isRunning = NO;

        if (self.cancelFlag) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:-999
                                           userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
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
