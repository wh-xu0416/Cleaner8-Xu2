#import "VideoCompressionManager.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Photos/Photos.h>

#import "ASStudioAlbumManager.h"
#import "ASStudioStore.h"
#import "ASStudioUtils.h"

@implementation ASCompressionItemResult
@end

@implementation ASCompressionSummary
@end

#pragma mark - Helpers

static NSString *ASVideoQualitySuffix(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return @"S";
        case ASCompressionQualityMedium: return @"M";
        case ASCompressionQualityLarge:  return @"L";
    }
}

/// ========= 颜色/范围（曝光变亮）修复 =========

// 读取源 track 是否 FullRange（否则默认为 VideoRange）
static BOOL ASIsFullRangeVideoFromTrack(AVAssetTrack *track) {
    if (!track || track.formatDescriptions.count == 0) return NO;

    CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions(fd);
    if (!ext) return NO;

    CFBooleanRef full = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_FullRangeVideo);
    return (full == kCFBooleanTrue);
}

// 按源范围选择像素格式：绝大多数素材是 VideoRange（16~235）
static OSType ASPixelFormatForTrack(AVAssetTrack *track) {
    return ASIsFullRangeVideoFromTrack(track)
    ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
}

// 读取源视频色彩信息（primaries/transfer/matrix），原样写入输出，避免 Rec601/709 误判导致变亮/偏色
static NSDictionary *ASVideoColorPropsFromTrack(AVAssetTrack *track, BOOL *outHDR) {
    if (outHDR) *outHDR = NO;
    if (!track || track.formatDescriptions.count == 0) return nil;

    CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
    CFDictionaryRef ext = CMFormatDescriptionGetExtensions(fd);
    if (!ext) return nil;

    CFStringRef prim = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ColorPrimaries);
    CFStringRef tf   = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_TransferFunction);
    CFStringRef mat  = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_YCbCrMatrix);

    if (outHDR && tf) {
        if (CFEqual(tf, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG) ||
            CFEqual(tf, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)) {
            *outHDR = YES;
        }
    }

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (prim) d[AVVideoColorPrimariesKey]    = (__bridge NSString *)prim;
    if (tf)   d[AVVideoTransferFunctionKey] = (__bridge NSString *)tf;
    if (mat)  d[AVVideoYCbCrMatrixKey]      = (__bridge NSString *)mat;

    return d.count ? d : nil;
}

// reader 输出 settings（关键：不要强制 FullRange）
static NSDictionary *ASPixelOutSettingsForVideoTrack(AVAssetTrack *track) {
    OSType pix = ASPixelFormatForTrack(track);
    return @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(pix),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
}

// writer 输入 settings（关键：把源 color props 写进去）
static NSDictionary *ASVideoInSettingsWithColorProps(NSInteger w,
                                                     NSInteger h,
                                                     NSDictionary *videoCompProps,
                                                     AVAssetTrack *srcVideoTrack,
                                                     BOOL *outHDR)
{
    NSMutableDictionary *settings = [@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(w),
        AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: videoCompProps ?: @{}
    } mutableCopy];

    NSDictionary *colorProps = ASVideoColorPropsFromTrack(srcVideoTrack, outHDR);
    if (colorProps) {
        settings[AVVideoColorPropertiesKey] = colorProps;
    }
    return settings;
}

// composition 也写入颜色信息（建议）
static void ASApplyColorPropsToVideoCompositionIfPossible(AVMutableVideoComposition *comp, AVAssetTrack *srcVideoTrack) {
    if (!comp) return;
    BOOL isHDR = NO;
    NSDictionary *colorProps = ASVideoColorPropsFromTrack(srcVideoTrack, &isHDR);
    if (!colorProps) return;

    if (@available(iOS 15.0, *)) {
        comp.colorPrimaries        = colorProps[AVVideoColorPrimariesKey];
        comp.colorTransferFunction = colorProps[AVVideoTransferFunctionKey];
        comp.colorYCbCrMatrix      = colorProps[AVVideoYCbCrMatrixKey];
    }
}

/// ========= 其它工具 =========

static BOOL ASIsBlackFrame(CMSampleBufferRef sb) {
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
    if (!pb) return NO;

    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    size_t w = CVPixelBufferGetWidthOfPlane(pb, 0);
    size_t h = CVPixelBufferGetHeightOfPlane(pb, 0);
    size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    uint8_t *yBase = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 0);

    if (!yBase || w == 0 || h == 0) {
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        return NO;
    }

    // 抽样 25 个点，计算平均亮度（Y）
    int samples = 0;
    int sum = 0;
    for (int gy = 1; gy <= 5; gy++) {
        size_t yy = (size_t)((double)h * gy / 6.0);
        if (yy >= h) yy = h - 1;
        uint8_t *row = yBase + yy * stride;

        for (int gx = 1; gx <= 5; gx++) {
            size_t xx = (size_t)((double)w * gx / 6.0);
            if (xx >= w) xx = w - 1;
            sum += row[xx];
            samples++;
        }
    }

    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);

    double avg = (samples > 0) ? ((double)sum / (double)samples) : 255.0;

    // video range 黑大概在 16 左右，full range 黑在 0
    return avg < 20.0;
}

static CGAffineTransform ASNormalizedTransform(AVAssetTrack *track, CGSize *outRenderSize) {
    CGSize n = track.naturalSize;
    CGAffineTransform t = track.preferredTransform;
    CGRect r = CGRectApplyAffineTransform((CGRect){CGPointZero, n}, t);

    CGSize rs = CGSizeMake(fabs(r.size.width), fabs(r.size.height));
    if (outRenderSize) *outRenderSize = rs;

    CGAffineTransform nt = CGAffineTransformTranslate(t, -r.origin.x, -r.origin.y);
    return nt;
}

static uint64_t ASFileSizeAtURL(NSURL *url) {
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    return (uint64_t)[attr[NSFileSize] unsignedLongLongValue];
}

static uint64_t ASAssetFileSize(PHAsset *asset) {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    PHAssetResource *r = resources.firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

static double ASRemainRatio(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 0.20;
        case ASCompressionQualityMedium: return 0.50;
        case ASCompressionQualityLarge:  return 0.80;
    }
}

static NSInteger ASMaxDimForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 540;
        case ASCompressionQualityMedium: return 720;
        case ASCompressionQualityLarge:  return 1080;
    }
}

static int64_t ASAudioBitrateForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return  96000;
        case ASCompressionQualityMedium: return 128000;
        case ASCompressionQualityLarge:  return 160000;
    }
}

static NSInteger ASEven(NSInteger x) { return (x % 2 == 0) ? x : (x - 1); }

static NSInteger ASEvenFloor(CGFloat v) {
    NSInteger i = (NSInteger)floor(v);
    if (i < 2) i = 2;
    return (i % 2 == 0) ? i : (i - 1);
}

static CGSize ASNaturalDisplaySize(AVAssetTrack *videoTrack) {
    CGSize n = videoTrack.naturalSize;
    CGAffineTransform t = videoTrack.preferredTransform;
    CGRect r = CGRectApplyAffineTransform((CGRect){CGPointZero, n}, t);
    return CGSizeMake(fabs(r.size.width), fabs(r.size.height));
}

static CGSize ASTargetSizeKeepAR(CGSize src, NSInteger maxDim) {
    if (src.width <= 0 || src.height <= 0) return src;

    CGFloat maxSide = MAX(src.width, src.height);
    if (maxSide <= maxDim) {
        return CGSizeMake(ASEven((NSInteger)llround(src.width)), ASEven((NSInteger)llround(src.height)));
    }

    CGFloat scale = (CGFloat)maxDim / maxSide;
    NSInteger w = ASEven((NSInteger)llround(src.width * scale));
    NSInteger h = ASEven((NSInteger)llround(src.height * scale));
    w = MAX(w, 2); h = MAX(h, 2);
    return CGSizeMake(w, h);
}

static NSError *ASError(NSString *msg, NSInteger code) {
    return [NSError errorWithDomain:@"compress" code:code userInfo:@{NSLocalizedDescriptionKey: msg ?: @"Error"}];
}

// ✅ 复制 sampleBuffer 并整体平移 PTS/DTS（修复 startSession=0 导致封面黑）
static CMSampleBufferRef ASCopySampleBufferWithTimeOffset(CMSampleBufferRef sb, CMTime offset) {
    if (!sb) return NULL;

    CMItemCount count = 0;
    if (CMSampleBufferGetSampleTimingInfoArray(sb, 0, NULL, &count) != noErr || count <= 0) {
        return NULL;
    }

    CMSampleTimingInfo *timings = (CMSampleTimingInfo *)malloc(sizeof(CMSampleTimingInfo) * (size_t)count);
    if (!timings) return NULL;

    if (CMSampleBufferGetSampleTimingInfoArray(sb, count, timings, &count) != noErr) {
        free(timings);
        return NULL;
    }

    for (CMItemCount i = 0; i < count; i++) {
        if (CMTIME_IS_VALID(timings[i].presentationTimeStamp)) {
            timings[i].presentationTimeStamp = CMTimeAdd(timings[i].presentationTimeStamp, offset);
        }
        if (CMTIME_IS_VALID(timings[i].decodeTimeStamp)) {
            timings[i].decodeTimeStamp = CMTimeAdd(timings[i].decodeTimeStamp, offset);
        }
    }

    CMSampleBufferRef out = NULL;
    CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sb, count, timings, &out);
    free(timings);
    return out;
}

static int64_t ASMinVideoBitrateForResolution(CGSize displaySize) {
    CGFloat w = MAX(displaySize.width, displaySize.height);
    if (w < 800)  return 600000;     // ~480p
    if (w < 1300) return 1500000;    // ~720p
    if (w < 2000) return 3000000;    // ~1080p
    if (w < 2600) return 6000000;    // ~1440p
    return 12000000;                // 4K+
}

static void ASGetAudioParams(AVAssetTrack *audioTrack, double *outSampleRate, int *outChannels) {
    double sr = 44100.0;
    int ch = 2;
    if (audioTrack.formatDescriptions.count > 0) {
        CMAudioFormatDescriptionRef fmt =
        (__bridge CMAudioFormatDescriptionRef)audioTrack.formatDescriptions.firstObject;
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
        if (asbd) {
            if (asbd->mSampleRate > 0) sr = asbd->mSampleRate;
            if (asbd->mChannelsPerFrame > 0) ch = (int)asbd->mChannelsPerFrame;
        }
    }
    if (outSampleRate) *outSampleRate = sr;
    if (outChannels) *outChannels = ch;
}

/// 判断是否需要用 VideoComposition 规范化（行车记录仪这类常见：coded != natural）
static BOOL ASShouldUseVideoComposition(AVAssetTrack *videoTrack) {
    if (videoTrack.formatDescriptions.count == 0) return NO;
    CMVideoFormatDescriptionRef fd =
    (__bridge CMVideoFormatDescriptionRef)videoTrack.formatDescriptions.firstObject;

    CMVideoDimensions coded = CMVideoFormatDescriptionGetDimensions(fd);
    CGSize natural = videoTrack.naturalSize;

    int nW = (int)llround(natural.width);
    int nH = (int)llround(natural.height);

    if (abs(coded.width  - nW) > 2 || abs(coded.height - nH) > 2) return YES;
    return NO;
}

#pragma mark - Manager

@interface VideoCompressionManager ()
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic) ASCompressionQuality quality;
@property (nonatomic) NSInteger index;

@property (nonatomic, strong) NSMutableArray<ASCompressionItemResult *> *results;
@property (nonatomic) uint64_t totalBefore;
@property (nonatomic) uint64_t totalAfter;

@property (nonatomic, copy) void(^progressBlock)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset);
@property (nonatomic, copy) void(^completionBlock)(ASCompressionSummary * _Nullable summary, NSError * _Nullable error);

@property (nonatomic, strong) AVAssetReader *currentReader;
@property (nonatomic, strong) AVAssetWriter *currentWriter;
@property (nonatomic, strong) AVAssetExportSession *currentExport; // ✅ HDR 分流用
@property (nonatomic, assign) PHImageRequestID currentRequestId;

@property (nonatomic) BOOL shouldCancel;
@property (nonatomic, readwrite) BOOL isRunning;
@property (nonatomic, strong) PHAssetCollection *studioAlbum;
@end

@implementation VideoCompressionManager

- (instancetype)init {
    if (self = [super init]) {
        _currentRequestId = PHInvalidImageRequestID;
    }
    return self;
}

- (void)compressAssets:(NSArray<PHAsset *> *)assets
               quality:(ASCompressionQuality)quality
              progress:(void(^)(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset))progress
            completion:(void(^)(ASCompressionSummary * _Nullable summary, NSError * _Nullable error))completion {

    if (self.isRunning) return;
    if (assets.count == 0) { if (completion) completion(nil, ASError(@"No assets", -1)); return; }

    self.isRunning = YES;
    self.shouldCancel = NO;

    self.assets = assets;
    self.quality = quality;
    self.progressBlock = progress;
    self.completionBlock = completion;

    self.index = 0;
    self.results = [NSMutableArray array];
    self.totalBefore = 0;
    self.totalAfter = 0;

    __weak typeof(self) weakSelf = self;
    [[ASStudioAlbumManager shared] fetchOrCreateAlbum:^(PHAssetCollection * _Nullable album, NSError * _Nullable error) {
        weakSelf.studioAlbum = album;
        if (!album) {
            NSLog(@"[MyStudio] Warning: studio album unavailable, will save video but not add to album.");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startNext];
        });
    }];
}

- (void)cancel {
    if (!self.isRunning) return;
    self.shouldCancel = YES;

    if (self.currentRequestId != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:self.currentRequestId];
        self.currentRequestId = PHInvalidImageRequestID;
    }

    [self.currentReader cancelReading];
    [self.currentWriter cancelWriting];
    [self.currentExport cancelExport]; // ✅ HDR 导出也 cancel
    self.currentReader = nil;
    self.currentWriter = nil;
    self.currentExport = nil;

    self.isRunning = NO;
    if (self.completionBlock) self.completionBlock(nil, ASError(@"Cancelled", -999));
}

- (void)startNext {
    if (self.shouldCancel) return;

    if (self.index >= self.assets.count) {
        [self finishAll];
        return;
    }

    PHAsset *ph = self.assets[self.index];

    uint64_t before = ASAssetFileSize(ph);
    self.totalBefore += before;

    PHVideoRequestOptions *opt = [PHVideoRequestOptions new];
    opt.networkAccessAllowed = YES;

    __weak typeof(self) weakSelf = self;
    self.currentRequestId =
    [[PHImageManager defaultManager] requestAVAssetForVideo:ph options:opt resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {

        if (!weakSelf || weakSelf.shouldCancel) return;
        if (!avAsset) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf fail:ASError(@"Failed to load AVAsset", -2)];
            });
            return;
        }

        NSString *name = [NSString stringWithFormat:@"compress_%@.mp4", NSUUID.UUID.UUIDString];
        NSURL *outURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

        [weakSelf transcodeAsset:avAsset
                         phAsset:ph
                      beforeBytes:before
                        outputURL:outURL
                       completion:^(uint64_t afterBytes, NSError * _Nullable error) {

            if (weakSelf.shouldCancel) return;

            if (error) {
                [weakSelf fail:error];
                return;
            }

            __block NSString *createdAssetId = nil;
            PHAssetCollection *album = weakSelf.studioAlbum;

            [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
                PHAssetChangeRequest *req =
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:outURL];
                req.creationDate = [NSDate date];

                PHObjectPlaceholder *phd = req.placeholderForCreatedAsset;
                createdAssetId = phd.localIdentifier;

                if (album && phd) {
                    [ASStudioAlbumManager addPlaceholder:phd toAlbum:album];
                }

            } completionHandler:^(BOOL success, NSError * _Nullable saveError) {

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!success) {
                        [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
                        [weakSelf fail:ASError(saveError.localizedDescription ?: @"Save to album failed", -6)];
                        return;
                    }

                    if (createdAssetId.length > 0) {
                        ASStudioItem *sitem = [ASStudioItem new];
                        sitem.assetId = createdAssetId;
                        sitem.type = ASStudioMediaTypeVideo;
                        sitem.beforeBytes = (int64_t)before;
                        sitem.afterBytes  = (int64_t)afterBytes;
                        sitem.duration = ph.duration;
                        sitem.compressedAt = [NSDate date];
                        sitem.displayName =
                        [ASStudioUtils makeDisplayNameForVideoWithQualitySuffix:ASVideoQualitySuffix(weakSelf.quality)];
                        [[ASStudioStore shared] upsertItem:sitem];
                    }

                    weakSelf.totalAfter += afterBytes;

                    ASCompressionItemResult *item = [ASCompressionItemResult new];
                    item.originalAsset = ph;
                    item.beforeBytes = before;
                    item.afterBytes = afterBytes;
                    item.outputURL = outURL;
                    [weakSelf.results addObject:item];

                    weakSelf.index += 1;
                    [weakSelf startNext];
                });
            }];
        }];
    }];
}

#pragma mark - HDR 分流（可避免 HDR 曝光/炸高光）

- (NSString *)_exportPresetForQuality:(ASCompressionQuality)q {
    // 尽量用 HEVC Highest（HDR 最稳）；不行再 fallback 常规 preset
    // 让 videoComposition 控制尺寸，preset 控制编码策略/兼容性
    if (@available(iOS 11.0, *)) {
        return AVAssetExportPresetHEVCHighestQuality;
    }
    // 老系统 fallback
    return AVAssetExportPresetHighestQuality;
}

- (void)transcodeHDRAsset:(AVAsset *)asset
                  phAsset:(PHAsset *)ph
              beforeBytes:(uint64_t)beforeBytes
                outputURL:(NSURL *)outURL
               completion:(void(^)(uint64_t afterBytes, NSError * _Nullable error))completion
{
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"No video track", -3)); }); return; }

    // HDR 也按你的 quality 做缩放（可调：如果你不想缩放，改成 target = display）
    CGSize display = ASNaturalDisplaySize(videoTrack);
    CGSize target = ASTargetSizeKeepAR(display, ASMaxDimForQuality(self.quality));
    NSInteger renderW = ASEvenFloor(target.width);
    NSInteger renderH = ASEvenFloor(target.height);

    float srcFPS = videoTrack.nominalFrameRate;
    NSInteger fps = MAX((NSInteger)llroundf(srcFPS), 30);

    CGAffineTransform nt = ASNormalizedTransform(videoTrack, NULL);

    CGFloat sx = (display.width  > 0) ? ((CGFloat)renderW / display.width)  : 1.0;
    CGFloat sy = (display.height > 0) ? ((CGFloat)renderH / display.height) : 1.0;

    // final = Scale ∘ NormalizedTransform （先 nt 后 scale）
    CGAffineTransform finalT = CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), nt);

    AVMutableVideoComposition *comp = [AVMutableVideoComposition videoComposition];
    comp.renderSize = CGSizeMake(renderW, renderH);
    comp.frameDuration = CMTimeMake(1, (int32_t)fps);

    AVMutableVideoCompositionInstruction *ins = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    ins.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

    AVMutableVideoCompositionLayerInstruction *layer =
    [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [layer setTransform:finalT atTime:kCMTimeZero];

    ins.layerInstructions = @[layer];
    comp.instructions = @[ins];

    // ✅ 把源颜色信息写回 composition
    ASApplyColorPropsToVideoCompositionIfPossible(comp, videoTrack);

    NSString *preset = [self _exportPresetForQuality:self.quality];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!export) {
        export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    }
    if (!export) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"ExportSession init failed", -20)); });
        return;
    }

    self.currentExport = export;

    export.videoComposition = comp;
    export.shouldOptimizeForNetworkUse = YES;

    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
    export.outputURL = outURL;
    export.outputFileType = AVFileTypeMPEG4;

    __weak typeof(self) weakSelf = self;

    // progress 轮询
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(0.12 * NSEC_PER_SEC),
                              (uint64_t)(0.02 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        if (!weakSelf || weakSelf.shouldCancel) return;
        float p = export.progress;
        float overall = (float)((weakSelf.index + p) / (double)weakSelf.assets.count);
        if (weakSelf.progressBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.progressBlock(weakSelf.index, weakSelf.assets.count, overall, ph);
            });
        }
    });
    dispatch_resume(timer);

    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_source_cancel(timer);

        if (!weakSelf || weakSelf.shouldCancel) return;

        weakSelf.currentExport = nil;

        if (export.status == AVAssetExportSessionStatusCompleted) {
            uint64_t after = ASFileSizeAtURL(outURL);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(after, nil); });
            return;
        }

        NSError *e = export.error ?: ASError(@"HDR export failed", -21);

        // mp4 不支持时兜底 mov
        NSURL *movURL = [[outURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"mov"];
        [[NSFileManager defaultManager] removeItemAtURL:movURL error:nil];

        AVAssetExportSession *export2 = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
        if (!export2) export2 = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
        if (!export2) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, e); });
            return;
        }

        weakSelf.currentExport = export2;
        export2.videoComposition = comp;
        export2.shouldOptimizeForNetworkUse = YES;
        export2.outputURL = movURL;
        export2.outputFileType = AVFileTypeQuickTimeMovie;

        [export2 exportAsynchronouslyWithCompletionHandler:^{
            weakSelf.currentExport = nil;

            if (export2.status == AVAssetExportSessionStatusCompleted) {
                uint64_t after = ASFileSizeAtURL(movURL);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(after, nil); });
            } else {
                NSError *e2 = export2.error ?: e;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(0, e2); });
            }
        }];
    }];
}

#pragma mark - SDR 主路径（Reader/Writer）

- (void)transcodeAsset:(AVAsset *)asset
               phAsset:(PHAsset *)ph
            beforeBytes:(uint64_t)beforeBytes
              outputURL:(NSURL *)outURL
             completion:(void(^)(uint64_t afterBytes, NSError * _Nullable error))completion
{
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"No video track", -3)); }); return; }
    AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];

    // ✅ HDR 分流（HLG/PQ）：走 ExportSession 更稳，避免曝光/炸高光
    BOOL isHDR = NO;
    (void)ASVideoColorPropsFromTrack(videoTrack, &isHDR);
    if (isHDR) {
        [self transcodeHDRAsset:asset phAsset:ph beforeBytes:beforeBytes outputURL:outURL completion:completion];
        return;
    }

    double duration = CMTimeGetSeconds(asset.duration);
    if (duration <= 0) duration = ph.duration > 0 ? ph.duration : 1;

    CGSize naturalSize = videoTrack.naturalSize;
    CGAffineTransform txf = videoTrack.preferredTransform;
    CGRect rr = CGRectApplyAffineTransform((CGRect){CGPointZero, naturalSize}, txf);
    CGSize displaySize = CGSizeMake(fabs(rr.size.width), fabs(rr.size.height));

    float srcFPS = videoTrack.nominalFrameRate;
    NSInteger fps = MAX((NSInteger)llroundf(srcFPS), 30);

    double origTotalBitrate = 0;
    if (beforeBytes > 0 && duration > 0) {
        origTotalBitrate = ((double)beforeBytes * 8.0) / duration;
    } else {
        double v = MAX(0.0, videoTrack.estimatedDataRate);
        double a = audioTrack ? MAX(0.0, audioTrack.estimatedDataRate) : 128000.0;
        origTotalBitrate = v + a;
        if (origTotalBitrate <= 0) origTotalBitrate = 3000000.0;
    }

    int64_t audioHint = ASAudioBitrateForQuality(self.quality);
    int64_t originalAudioBR = audioTrack ? (int64_t)llround(MAX(0.0, audioTrack.estimatedDataRate)) : 0;
    int64_t audioBitrate = MAX(originalAudioBR, audioHint);

    double remain = ASRemainRatio(self.quality);
    int64_t targetTotal = (int64_t)llround(origTotalBitrate * remain);
    int64_t floorBR = ASMinVideoBitrateForResolution(displaySize);

    int64_t targetVideoBitrate = targetTotal - audioBitrate;
    if (targetVideoBitrate < floorBR) targetVideoBitrate = floorBR;
    if (targetVideoBitrate < 200000) targetVideoBitrate = 200000;

    NSError *err = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&err];
    if (!reader) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, err ?: ASError(@"Reader init failed", -4)); }); return; }

    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outURL fileType:AVFileTypeMPEG4 error:&err];
    if (!writer) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, err ?: ASError(@"Writer init failed", -5)); }); return; }

    writer.shouldOptimizeForNetworkUse = YES;

    self.currentReader = reader;
    self.currentWriter = writer;

    NSDictionary *pixelOutSettings = ASPixelOutSettingsForVideoTrack(videoTrack);

    BOOL useComposition = ASShouldUseVideoComposition(videoTrack);
    AVAssetReaderOutput *videoOut = nil;

    NSInteger encodeW = 0;
    NSInteger encodeH = 0;

    if (useComposition) {
        CGSize renderSize = CGSizeZero;
        CGAffineTransform nt = ASNormalizedTransform(videoTrack, &renderSize);

        encodeW = ASEvenFloor(renderSize.width);
        encodeH = ASEvenFloor(renderSize.height);

        AVMutableVideoComposition *comp = [AVMutableVideoComposition videoComposition];
        comp.renderSize = CGSizeMake(encodeW, encodeH);
        comp.frameDuration = CMTimeMake(1, (int32_t)fps);

        AVMutableVideoCompositionInstruction *ins = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        ins.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

        AVMutableVideoCompositionLayerInstruction *layer =
        [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        [layer setTransform:nt atTime:kCMTimeZero];

        ins.layerInstructions = @[layer];
        comp.instructions = @[ins];

        // ✅ 补：composition 写颜色信息（否则部分视频会变亮/偏色）
        ASApplyColorPropsToVideoCompositionIfPossible(comp, videoTrack);

        AVAssetReaderVideoCompositionOutput *vco =
        [[AVAssetReaderVideoCompositionOutput alloc] initWithVideoTracks:@[videoTrack]
                                                           videoSettings:pixelOutSettings];
        vco.videoComposition = comp;
        vco.alwaysCopiesSampleData = NO;

        if (![reader canAddOutput:vco]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"Cannot add video composition output", -10)); });
            return;
        }
        [reader addOutput:vco];
        videoOut = vco;
    } else {
        encodeW = ASEvenFloor(naturalSize.width);
        encodeH = ASEvenFloor(naturalSize.height);

        AVAssetReaderTrackOutput *vto =
        [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:pixelOutSettings];
        vto.alwaysCopiesSampleData = NO;

        if (![reader canAddOutput:vto]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"Cannot add video track output", -11)); });
            return;
        }
        [reader addOutput:vto];
        videoOut = vto;
    }

    NSDictionary *videoCompProps = @{
        AVVideoAverageBitRateKey: @(targetVideoBitrate),
        AVVideoAllowFrameReorderingKey: @NO,
        AVVideoMaxKeyFrameIntervalKey: @(fps * 2),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
        AVVideoCleanApertureKey: @{
            AVVideoCleanApertureWidthKey: @(encodeW),
            AVVideoCleanApertureHeightKey: @(encodeH),
            AVVideoCleanApertureHorizontalOffsetKey: @0,
            AVVideoCleanApertureVerticalOffsetKey: @0
        },
        AVVideoPixelAspectRatioKey: @{
            AVVideoPixelAspectRatioHorizontalSpacingKey: @1,
            AVVideoPixelAspectRatioVerticalSpacingKey: @1
        }
    };

    BOOL dummyHDR = NO;
    NSDictionary *videoInSettings =
    ASVideoInSettingsWithColorProps(encodeW, encodeH, videoCompProps, videoTrack, &dummyHDR);

    AVAssetWriterInput *videoIn =
    [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoInSettings];
    videoIn.expectsMediaDataInRealTime = NO;

    videoIn.transform = useComposition ? CGAffineTransformIdentity : txf;

    if (![writer canAddInput:videoIn]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"Cannot add video input", -12)); });
        return;
    }
    [writer addInput:videoIn];

    AVAssetReaderTrackOutput *audioOut = nil;
    AVAssetWriterInput *audioIn = nil;
    if (audioTrack) {
        NSDictionary *audioOutSettings = @{
            AVFormatIDKey: @(kAudioFormatLinearPCM),
            AVLinearPCMIsBigEndianKey: @NO,
            AVLinearPCMIsFloatKey: @NO,
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsNonInterleaved: @NO
        };
        audioOut = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:audioOutSettings];
        audioOut.alwaysCopiesSampleData = NO;
        if ([reader canAddOutput:audioOut]) [reader addOutput:audioOut];

        double sr = 44100.0; int ch = 2;
        ASGetAudioParams(audioTrack, &sr, &ch);

        NSDictionary *audioInSettings = @{
            AVFormatIDKey: @(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: @(ch),
            AVSampleRateKey: @(sr),
            AVEncoderBitRateKey: @(audioBitrate)
        };
        audioIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioInSettings];
        audioIn.expectsMediaDataInRealTime = NO;
        if ([writer canAddInput:audioIn]) [writer addInput:audioIn];
    }

    if (![reader startReading]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, reader.error ?: ASError(@"Reader start failed", -7)); });
        return;
    }
    if (![writer startWriting]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, writer.error ?: ASError(@"Writer start failed", -8)); });
        return;
    }

    __block BOOL sessionStarted = NO;
    __block CMTime sessionStartPTS = kCMTimeInvalid;
    __block CMTime timeOffset = kCMTimeInvalid;
    __block double effectiveDuration = MAX(0.1, duration);

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t videoQ = dispatch_queue_create("compress.writer.video", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t audioQ = dispatch_queue_create("compress.writer.audio", DISPATCH_QUEUE_SERIAL);

    __block BOOL videoDone = NO;
    __block BOOL audioDone = (audioIn == nil);
    __block BOOL audioLoopStarted = (audioIn == nil);

    __weak typeof(self) weakSelf = self;

    void (^startAudioLoopIfNeeded)(void) = ^{
        if (audioLoopStarted) return;
        if (!audioIn || !audioOut) return;
        if (!sessionStarted) return;

        audioLoopStarted = YES;
        dispatch_group_enter(group);

        [audioIn requestMediaDataWhenReadyOnQueue:audioQ usingBlock:^{
            while (audioIn.isReadyForMoreMediaData && !audioDone && !weakSelf.shouldCancel) {

                CMSampleBufferRef sb = [audioOut copyNextSampleBuffer];
                if (!sb) {
                    audioDone = YES;
                    [audioIn markAsFinished];
                    dispatch_group_leave(group);
                    break;
                }

                CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb);
                if (CMTIME_IS_VALID(sessionStartPTS) && CMTIME_IS_VALID(pts) &&
                    CMTIME_COMPARE_INLINE(pts, <, sessionStartPTS)) {
                    CFRelease(sb);
                    continue;
                }

                CMSampleBufferRef shifted = NULL;
                if (CMTIME_IS_VALID(timeOffset)) {
                    shifted = ASCopySampleBufferWithTimeOffset(sb, timeOffset);
                }

                BOOL ok = [audioIn appendSampleBuffer:(shifted ?: sb)];
                if (shifted) CFRelease(shifted);
                CFRelease(sb);

                if (!ok) {
                    audioDone = YES;
                    [audioIn markAsFinished];
                    dispatch_group_leave(group);
                    break;
                }
            }
        }];
    };

    dispatch_group_enter(group);

    __block int blackSkipCount = 0;
    const int blackSkipMax = fps * 2;

    [videoIn requestMediaDataWhenReadyOnQueue:videoQ usingBlock:^{
        while (videoIn.isReadyForMoreMediaData && !videoDone && !weakSelf.shouldCancel) {

            CMSampleBufferRef sb = [videoOut copyNextSampleBuffer];
            if (!sb) {
                if (!sessionStarted) {
                    sessionStartPTS = kCMTimeZero;
                    timeOffset = kCMTimeZero;
                    [writer startSessionAtSourceTime:kCMTimeZero];
                    sessionStarted = YES;
                    effectiveDuration = MAX(0.1, duration);
                    startAudioLoopIfNeeded();
                }

                videoDone = YES;
                [videoIn markAsFinished];
                dispatch_group_leave(group);
                break;
            }

            CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb);

            if (!sessionStarted) {
                if (blackSkipCount < blackSkipMax && ASIsBlackFrame(sb)) {
                    blackSkipCount++;
                    CFRelease(sb);
                    continue;
                }

                sessionStartPTS = CMTIME_IS_VALID(pts) ? pts : kCMTimeZero;
                timeOffset = CMTimeSubtract(kCMTimeZero, sessionStartPTS);

                [writer startSessionAtSourceTime:kCMTimeZero];
                sessionStarted = YES;

                double startSec = CMTimeGetSeconds(sessionStartPTS);
                if (!isfinite(startSec) || startSec < 0) startSec = 0;
                effectiveDuration = MAX(0.1, duration - startSec);

                startAudioLoopIfNeeded();
            }

            CMTime rel = CMTIME_IS_VALID(pts) ? CMTimeSubtract(pts, sessionStartPTS) : kCMTimeZero;
            double tsec = CMTimeGetSeconds(rel);
            if (!isfinite(tsec) || tsec < 0) tsec = 0;
            double p = MAX(0.0, MIN(1.0, tsec / effectiveDuration));
            float overall = (float)((weakSelf.index + p) / (double)weakSelf.assets.count);
            if (weakSelf.progressBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.progressBlock(weakSelf.index, weakSelf.assets.count, overall, ph);
                });
            }

            CMSampleBufferRef shifted = NULL;
            if (CMTIME_IS_VALID(timeOffset)) {
                shifted = ASCopySampleBufferWithTimeOffset(sb, timeOffset);
            }

            BOOL ok = [videoIn appendSampleBuffer:(shifted ?: sb)];
            if (shifted) CFRelease(shifted);
            CFRelease(sb);

            if (!ok) {
                videoDone = YES;
                [videoIn markAsFinished];
                dispatch_group_leave(group);
                break;
            }
        }
    }];

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (weakSelf.shouldCancel) return;

        [writer finishWritingWithCompletionHandler:^{
            NSError *werr = writer.error;
            if (reader.status == AVAssetReaderStatusFailed && reader.error) werr = reader.error;

            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.currentReader = nil;
                weakSelf.currentWriter = nil;

                if (werr) { completion(0, werr); return; }

                uint64_t after = ASFileSizeAtURL(outURL);
                completion(after, nil);
            });
        }];
    });
}

- (void)finishAll {
    self.isRunning = NO;

    ASCompressionSummary *sum = [ASCompressionSummary new];
    sum.items = self.results.copy;
    sum.totalBeforeBytes = self.totalBefore;
    sum.totalAfterBytes = self.totalAfter;
    sum.totalSavedBytes = (self.totalBefore > self.totalAfter) ? (self.totalBefore - self.totalAfter) : 0;

    if (self.completionBlock) self.completionBlock(sum, nil);
}

- (void)fail:(NSError *)error {
    self.isRunning = NO;
    if (self.completionBlock) self.completionBlock(nil, error ?: ASError(@"Error", -9));
}

@end
