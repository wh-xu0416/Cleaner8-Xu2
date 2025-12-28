#import "VideoCompressionManager.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
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

    // renderSize 用变换后的 bbox 尺寸
    CGSize rs = CGSizeMake(fabs(r.size.width), fabs(r.size.height));
    if (outRenderSize) *outRenderSize = rs;

    // 把内容平移到 (0,0) 可见区域
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

// 你要的：节省 80/50/20 => remain 0.2/0.5/0.8
static double ASRemainRatio(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 0.20; // save 80%
        case ASCompressionQualityMedium: return 0.50; // save 50%
        case ASCompressionQualityLarge:  return 0.80; // save 20%
    }
}

// 目标最大边长（会改变尺寸：Small/Medium/Large）
static NSInteger ASMaxDimForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 540;
        case ASCompressionQualityMedium: return 720;
        case ASCompressionQualityLarge:  return 1080;
    }
}

// 防糊：不同分辨率的最低视频码率（bit/s）
static int64_t ASMinVideoBitrateForMaxDim(NSInteger maxDim) {
    if (maxDim <= 540)  return 900000;   // 0.9 Mbps
    if (maxDim <= 720)  return 1600000;  // 1.6 Mbps
    return 2500000;                     // 2.5 Mbps (1080p)
}

// 上限（避免过大）
static int64_t ASMaxVideoBitrateForMaxDim(NSInteger maxDim) {
    if (maxDim <= 540)  return 3000000;  // 3 Mbps
    if (maxDim <= 720)  return 5000000;  // 5 Mbps
    return 8000000;                     // 8 Mbps
}

static int64_t ASAudioBitrateForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return  96000; // 96 kbps
        case ASCompressionQualityMedium: return 128000; // 128 kbps
        case ASCompressionQualityLarge:  return 160000; // 160 kbps
    }
}

static NSInteger ASEven(NSInteger x) { return (x % 2 == 0) ? x : (x - 1); }

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
        weakSelf.studioAlbum = album; // 可能为 nil（失败也不阻塞压缩，只是不归档到 album）
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
    self.currentReader = nil;
    self.currentWriter = nil;

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

        // ✅ 输出 URL（UUID）
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

            // 保存到相册 + 加入 My Studio album + 写入索引（历史）
            __block NSString *createdAssetId = nil;
            PHAssetCollection *album = weakSelf.studioAlbum; // 取缓存（可能 nil）

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
                        // 失败也清理临时文件，避免堆积
                        [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
                        [weakSelf fail:ASError(saveError.localizedDescription ?: @"Save to album failed", -6)];
                        return;
                    }

                    // ✅ 写索引：My Studio 列表展示用
                    if (createdAssetId.length > 0) {
                        ASStudioItem *sitem = [ASStudioItem new];
                        sitem.assetId = createdAssetId;
                        sitem.type = ASStudioMediaTypeVideo;
                        sitem.beforeBytes = (int64_t)before;
                        sitem.afterBytes  = (int64_t)afterBytes;
                        sitem.duration = ph.duration; // 用原 PHAsset 时长即可
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

                    // 你原来存 outputURL：注意 outURL 是 tmp，若你后面不再使用建议置空并删除文件
                    item.outputURL = outURL;

                    [weakSelf.results addObject:item];

                    // ✅ 可选：如果你不需要 tmp 文件（推荐），这里删除并把 outputURL 置空
                    // [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
                    // item.outputURL = nil;

                    weakSelf.index += 1;
                    [weakSelf startNext];
                });
            }];

        }];
    }];
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

    // coded 和 natural 差异明显：大概率存在 padding/cropping（1906 这种非常常见）
    if (abs(coded.width  - nW) > 2 || abs(coded.height - nH) > 2) return YES;

    return NO;
}

static NSInteger ASEvenFloor(CGFloat v) {
    NSInteger i = (NSInteger)floor(v);
    if (i < 2) i = 2;
    return (i % 2 == 0) ? i : (i - 1);
}

- (void)transcodeAsset:(AVAsset *)asset
               phAsset:(PHAsset *)ph
           beforeBytes:(uint64_t)beforeBytes
             outputURL:(NSURL *)outURL
            completion:(void(^)(uint64_t afterBytes, NSError * _Nullable error))completion
{
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"No video track", -3)); }); return; }
    AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];

    double duration = CMTimeGetSeconds(asset.duration);
    if (duration <= 0) duration = ph.duration > 0 ? ph.duration : 1;

    CGSize naturalSize = videoTrack.naturalSize;
    CGAffineTransform txf = videoTrack.preferredTransform;
    CGRect rr = CGRectApplyAffineTransform((CGRect){CGPointZero, naturalSize}, txf);
    CGSize displaySize = CGSizeMake(fabs(rr.size.width), fabs(rr.size.height));

    float srcFPS = videoTrack.nominalFrameRate;
    NSInteger fps = MAX((NSInteger)llroundf(srcFPS), 30);

    // ===== bitrate：保持你现在 Swift 同款逻辑 =====
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

    writer.shouldOptimizeForNetworkUse = YES; // 建议打开

    self.currentReader = reader;
    self.currentWriter = writer;

    NSDictionary *pixelOutSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    };

    // ===== 关键 1：针对行车记录仪等，必要时走 VideoCompositionOutput 规范化尺寸 =====
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
        [layer setTransform:nt atTime:kCMTimeZero];  // 用 nt，不要用 txf

        ins.layerInstructions = @[layer];
        comp.instructions = @[ins];

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
        // fast path：不烤方向，编码尺寸用 naturalSize（未旋转）
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

    // ===== writer video input（Swift 同款关键参数）=====
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

    NSDictionary *videoInSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(encodeW),
        AVVideoHeightKey: @(encodeH),
        AVVideoCompressionPropertiesKey: videoCompProps
    };

    AVAssetWriterInput *videoIn =
        [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoInSettings];
    videoIn.expectsMediaDataInRealTime = NO;

    // 关键：composition 已烤方向 => transform 用 identity；否则用 txf
    videoIn.transform = useComposition ? CGAffineTransformIdentity : txf;

    if (![writer canAddInput:videoIn]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, ASError(@"Cannot add video input", -12)); });
        return;
    }
    [writer addInput:videoIn];

    // ===== audio =====
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

    // ===== 关键 2：保留封面（缩略图）—— 把第一帧对齐到 t=0（消除时间轴空洞）=====
    __block BOOL sessionStarted = NO;
    __block CMTime sessionStartPTS = kCMTimeInvalid;
    __block CMTime timeOffset = kCMTimeInvalid;   // = -sessionStartPTS
    __block double effectiveDuration = MAX(0.1, duration);

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t videoQ = dispatch_queue_create("compress.writer.video", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t audioQ = dispatch_queue_create("compress.writer.audio", DISPATCH_QUEUE_SERIAL);

    __block BOOL videoDone = NO;
    __block BOOL audioDone = (audioIn == nil);
    __block BOOL audioLoopStarted = (audioIn == nil);

    __weak typeof(self) weakSelf = self;

    // 音频循环：必须等 sessionStarted（即拿到首帧视频PTS并完成 timeOffset）后再启动
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

                // 丢弃早于首帧视频的音频（否则 shift 后会变负时间）
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

    // 可选：最多跳过前 N 帧黑帧，避免某些视频真的全黑导致死循环
    __block int blackSkipCount = 0;
    const int blackSkipMax = fps * 2; // 最多跳 2 秒

    [videoIn requestMediaDataWhenReadyOnQueue:videoQ usingBlock:^{
        while (videoIn.isReadyForMoreMediaData && !videoDone && !weakSelf.shouldCancel) {

            CMSampleBufferRef sb = [videoOut copyNextSampleBuffer];
            if (!sb) {
                // 没帧了：如果还没 startSession，也必须 start 一下，否则 writer 可能 finish 失败
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
                // ✅ 只在 sb 有值时才判断黑帧
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

                // ✅ sessionStarted 之后再启动音频写入
                startAudioLoopIfNeeded();
            }

            // progress：用 pts - sessionStartPTS
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

            // ✅ 平移时间轴，让“第一张非黑帧”落在 t=0
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

@end
