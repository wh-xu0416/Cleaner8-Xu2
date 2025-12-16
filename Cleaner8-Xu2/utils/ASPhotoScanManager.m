#import "ASPhotoScanManager.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>

const ASComparePolicy kPolicySimilar   = { .phashThreshold = 119, .visionThreshold = 0.56f };
const ASComparePolicy kPolicyDuplicate = { .phashThreshold = 30,  .visionThreshold = 0.20f };

static NSString * const kASCacheFileName = @"as_photo_scan_cache_v1.dat";
static const uint64_t   kBigVideoMinBytes = (uint64_t)20 * 1024ull * 1024ull;

#pragma mark - Screen Metrics (One-time)

typedef struct {
    int longSide;
    int shortSide;
    int pxEpsilon;        // ±8 px
    int ratioPermille;    // ±2% => 20‰
} ASScreenMetrics;

static inline ASScreenMetrics ASScreenMetricsMake(void) {
    __block CGRect bounds = CGRectZero;

    if ([NSThread isMainThread]) {
        bounds = UIScreen.mainScreen.nativeBounds;
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            bounds = UIScreen.mainScreen.nativeBounds;
        });
    }

    int w = (int)bounds.size.width;
    int h = (int)bounds.size.height;

    ASScreenMetrics m;
    m.longSide = MAX(w, h);
    m.shortSide = MIN(w, h);
    m.pxEpsilon = 8;
    m.ratioPermille = 20;
    return m;
}

static ASScreenMetrics ASScreen(void) {
    static ASScreenMetrics metrics;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        metrics = ASScreenMetricsMake();
    });
    return metrics;
}
static NSSet<NSNumber *> *ASCommonCameraSides(void) {
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[
            @720, @1080, @1280, @1440, @1920, @2160, @2560,
            @2720, @3000, @3072, @3200, @3840, @4000,
            @4096, @4320, @4608, @5120, @7680
        ]];
    });
    return set;
}

static NSArray<NSString *> *ASScreenRecordingKeywords(void) {
    static NSArray *arr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arr = @[
            @"rpreplay", @"screen recording", @"screenrecording",
            @"屏幕录制", @"录屏",
            @"画面収録", @"スクリーンレコーディング",
            @"녹화", @"화면 기록",
            @"запись экрана",
            @"錄製"
        ];
    });
    return arr;
}
static NSCache<NSString *, NSNumber *> *ASScreenRecordingMemo(void) {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 10000;
    });
    return cache;
}
static inline BOOL ASApproxScreenAspect(int w, int h) {
    ASScreenMetrics s = ASScreen();

    int ww = MAX(w, h);
    int hh = MIN(w, h);

    // 像素几乎等于屏幕
    if (abs(ww - s.longSide) <= s.pxEpsilon &&
        abs(hh - s.shortSide) <= s.pxEpsilon) {
        return YES;
    }

    // 比例比较（整型，避免浮点）
    int64_t lhs = (int64_t)ww * (int64_t)s.shortSide;
    int64_t rhs = (int64_t)hh * (int64_t)s.longSide;
    int64_t diff = llabs(lhs - rhs);
    int64_t base = MAX(lhs, rhs);

    // diff/base ≤ 2%
    return diff * 1000 <= base * s.ratioPermille;
}
static inline BOOL ASIsCommonCameraSize(int w, int h) {
    int ww = MAX(w, h);
    int hh = MIN(w, h);
    NSSet *set = ASCommonCameraSides();
    return [set containsObject:@(ww)] || [set containsObject:@(hh)];
}
static BOOL ASNameLooksLikeScreenRecording(PHAsset *asset) {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    for (PHAssetResource *r in resources) {
        NSString *name = r.originalFilename;
        for (NSString *kw in ASScreenRecordingKeywords()) {
            if ([name rangeOfString:kw
                            options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound) {
                return YES;
            }
        }
    }
    return NO;
}
static BOOL ASIsDeviceApprox16x9(void) {
    static BOOL is16x9;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ASScreenMetrics s = ASScreen();
        int64_t lhs = (int64_t)s.longSide * 9;
        int64_t rhs = (int64_t)s.shortSide * 16;
        int64_t diff = llabs(lhs - rhs);
        int64_t base = MAX(lhs, rhs);
        // ≤ 1%
        is16x9 = (diff * 1000 <= base * 10);
    });
    return is16x9;
}


#pragma mark - Helpers

static inline NSString *ASCachePath(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = dirs.firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [[dir stringByAppendingPathComponent:kASCacheFileName] copy];
}

static inline NSDate *ASDayStart(NSDate *date) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:date];
    return [cal dateFromComponents:c] ?: date;
}

static inline BOOL ASIsScreenshot(PHAsset *a) {
    return (a.mediaType == PHAssetMediaTypeImage) && (a.mediaSubtypes & PHAssetMediaSubtypePhotoScreenshot);
}

static inline BOOL ASIsScreenRecording(PHAsset *asset) {
    if (asset.mediaType != PHAssetMediaTypeVideo) return NO;

        NSString *key = asset.localIdentifier;
        NSCache *memo = ASScreenRecordingMemo();
        NSNumber *cached = [memo objectForKey:key];
        if (cached) return cached.boolValue;

        int w = (int)asset.pixelWidth;
        int h = (int)asset.pixelHeight;

        BOOL isSR = NO;

        if (ASApproxScreenAspect(w, h)) {
            if (!ASIsDeviceApprox16x9()) {
                // 长屏设备：几何命中即可
                isSR = YES;
            } else {
                // 16:9 设备：防止误伤相机视频
                isSR = !ASIsCommonCameraSize(w, h) || ASNameLooksLikeScreenRecording(asset);
            }
        }

        [memo setObject:@(isSR) forKey:key];
        return isSR;
}

static inline BOOL ASAllowedForCompare(PHAsset *a) {
    if (a.mediaType == PHAssetMediaTypeImage) return !ASIsScreenshot(a);
    if (a.mediaType == PHAssetMediaTypeVideo) return !ASIsScreenRecording(a);
    return NO;
}

static inline uint32_t ASPHashDistance(uint64_t h1, uint64_t h2) {
    return (uint32_t)__builtin_popcountll(h1 ^ h2);
}

// Vision distance -> similarity [0,1], larger means more similar
static inline float ASVisionDistanceToScore(float distance) {
    // FeaturePrint distance: smaller is more similar. 用一个稳定映射到 0~1
    // score = 1 / (1 + distance)
    return 1.0f / (1.0f + MAX(distance, 0.0f));
}

// pHash 汉明距离 <= phashThreshold  且  Vision distance <= visionThreshold
static inline BOOL ASMatchPolicy(uint64_t h1, uint64_t h2, float visionDistance, ASComparePolicy p) {
    if (ASPHashDistance(h1, h2) > p.phashThreshold) return NO;
    if (visionDistance > p.visionThreshold) return NO; // 阈值含义“distance上限”
    return YES;
}

#pragma mark - Models

@implementation ASScanSnapshot
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init {
    if (self=[super init]){
        _lastUpdated=[NSDate date];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.state forKey:@"state"];
    [coder encodeInteger:self.scannedCount forKey:@"scannedCount"];
    [coder encodeInt64:(int64_t)self.scannedBytes forKey:@"scannedBytes"];
    [coder encodeInteger:self.cleanableCount forKey:@"cleanableCount"];
    [coder encodeInt64:(int64_t)self.cleanableBytes forKey:@"cleanableBytes"];
    [coder encodeInteger:self.screenshotCount forKey:@"screenshotCount"];
    [coder encodeInt64:(int64_t)self.screenshotBytes forKey:@"screenshotBytes"];
    [coder encodeInteger:self.screenRecordingCount forKey:@"screenRecordingCount"];
    [coder encodeInt64:(int64_t)self.screenRecordingBytes forKey:@"screenRecordingBytes"];
    [coder encodeInteger:self.bigVideoCount forKey:@"bigVideoCount"];
    [coder encodeInt64:(int64_t)self.bigVideoBytes forKey:@"bigVideoBytes"];
    [coder encodeInteger:self.duplicateGroupCount forKey:@"duplicateGroupCount"];
    [coder encodeInteger:self.similarGroupCount forKey:@"similarGroupCount"];
    [coder encodeObject:self.lastUpdated forKey:@"lastUpdated"];
    [coder encodeObject:self.phash256Data forKey:@"phash256Data"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self=[super init]) {
        _state = [coder decodeIntegerForKey:@"state"];
        _scannedCount = [coder decodeIntegerForKey:@"scannedCount"];
        _scannedBytes = (uint64_t)[coder decodeInt64ForKey:@"scannedBytes"];
        _cleanableCount = [coder decodeIntegerForKey:@"cleanableCount"];
        _cleanableBytes = (uint64_t)[coder decodeInt64ForKey:@"cleanableBytes"];
        _screenshotCount = [coder decodeIntegerForKey:@"screenshotCount"];
        _screenshotBytes = (uint64_t)[coder decodeInt64ForKey:@"screenshotBytes"];
        _screenRecordingCount = [coder decodeIntegerForKey:@"screenRecordingCount"];
        _screenRecordingBytes = (uint64_t)[coder decodeInt64ForKey:@"screenRecordingBytes"];
        _bigVideoCount = [coder decodeIntegerForKey:@"bigVideoCount"];
        _bigVideoBytes = (uint64_t)[coder decodeInt64ForKey:@"bigVideoBytes"];
        _duplicateGroupCount = [coder decodeIntegerForKey:@"duplicateGroupCount"];
        _similarGroupCount = [coder decodeIntegerForKey:@"similarGroupCount"];
        _lastUpdated = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastUpdated"] ?: [NSDate date];
        _phash256Data = [coder decodeObjectOfClass:[NSData class] forKey:@"phash256Data"];
    }
    return self;
}
@end

@implementation ASAssetModel
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.localId forKey:@"localId"];
    [coder encodeInteger:self.mediaType forKey:@"mediaType"];
    [coder encodeInt64:(int64_t)self.subtypes forKey:@"subtypes"];
    [coder encodeObject:self.creationDate forKey:@"creationDate"];
    [coder encodeObject:self.modificationDate forKey:@"modificationDate"];
    [coder encodeInt64:(int64_t)self.fileSizeBytes forKey:@"fileSizeBytes"];
    [coder encodeInt64:(int64_t)self.pHash forKey:@"pHash"];
    [coder encodeObject:self.visionPrintData forKey:@"visionPrintData"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self=[super init]) {
        _localId = [coder decodeObjectOfClass:[NSString class] forKey:@"localId"] ?: @"";
        _mediaType = [coder decodeIntegerForKey:@"mediaType"];
        _subtypes = (PHAssetMediaSubtype)[coder decodeInt64ForKey:@"subtypes"];
        _creationDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"creationDate"];
        _modificationDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"modificationDate"];
        _fileSizeBytes = (uint64_t)[coder decodeInt64ForKey:@"fileSizeBytes"];
        _pHash = (uint64_t)[coder decodeInt64ForKey:@"pHash"];
        _visionPrintData = [coder decodeObjectOfClass:[NSData class] forKey:@"visionPrintData"];
        _phash256Data = [coder decodeObjectOfClass:[NSData class] forKey:@"phash256Data"];
    }
    return self;
}
@end

@implementation ASAssetGroup
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init { if (self=[super init]) { _assets=[NSMutableArray array]; } return self; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.assets forKey:@"assets"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self=[super init]) {
        _type = [coder decodeIntegerForKey:@"type"];
        NSSet *classes = [NSSet setWithArray:@[[NSArray class],[NSMutableArray class],[ASAssetModel class]]];
        _assets = [[coder decodeObjectOfClasses:classes forKey:@"assets"] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}
@end

#pragma mark - Cache container

@interface ASScanCache : NSObject <NSSecureCoding>
@property (nonatomic, strong) ASScanSnapshot *snapshot;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *duplicateGroups;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *similarGroups;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenshots;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenRecordings;
@property (nonatomic, strong) NSArray<ASAssetModel *> *bigVideos;

// 用于“杀死重启后检测增量”
@property (nonatomic, strong) NSDate *anchorDate;           // 上次扫描时见过的最新 creation/modification
@property (nonatomic, strong) NSDate *homeStatRefreshDate;  // 每三天刷新一次首页统计
@end

@implementation ASScanCache
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init { if (self=[super init]) { _snapshot=[ASScanSnapshot new]; _anchorDate=[NSDate dateWithTimeIntervalSince1970:0]; _homeStatRefreshDate=[NSDate dateWithTimeIntervalSince1970:0]; } return self; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.snapshot forKey:@"snapshot"];
    [coder encodeObject:self.duplicateGroups forKey:@"duplicateGroups"];
    [coder encodeObject:self.similarGroups forKey:@"similarGroups"];
    [coder encodeObject:self.screenshots forKey:@"screenshots"];
    [coder encodeObject:self.screenRecordings forKey:@"screenRecordings"];
    [coder encodeObject:self.bigVideos forKey:@"bigVideos"];
    [coder encodeObject:self.anchorDate forKey:@"anchorDate"];
    [coder encodeObject:self.homeStatRefreshDate forKey:@"homeStatRefreshDate"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self=[super init]) {
        _snapshot = [coder decodeObjectOfClass:[ASScanSnapshot class] forKey:@"snapshot"] ?: [ASScanSnapshot new];
        NSSet *gClasses = [NSSet setWithArray:@[[NSArray class],[ASAssetGroup class],[ASAssetModel class],[NSMutableArray class]]];
        _duplicateGroups = [coder decodeObjectOfClasses:gClasses forKey:@"duplicateGroups"] ?: @[];
        _similarGroups   = [coder decodeObjectOfClasses:gClasses forKey:@"similarGroups"] ?: @[];
        NSSet *aClasses = [NSSet setWithArray:@[[NSArray class],[ASAssetModel class]]];
        _screenshots = [coder decodeObjectOfClasses:aClasses forKey:@"screenshots"] ?: @[];
        _screenRecordings = [coder decodeObjectOfClasses:aClasses forKey:@"screenRecordings"] ?: @[];
        _bigVideos = [coder decodeObjectOfClasses:aClasses forKey:@"bigVideos"] ?: @[];
        _anchorDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"anchorDate"] ?: [NSDate dateWithTimeIntervalSince1970:0];
        _homeStatRefreshDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"homeStatRefreshDate"] ?: [NSDate dateWithTimeIntervalSince1970:0];
    }
    return self;
}
@end

#pragma mark - Manager

@interface ASPhotoScanManager ()
@property (nonatomic, strong) NSCache<NSString*, VNFeaturePrintObservation*> *visionMemo;
@property (nonatomic, strong) dispatch_queue_t workQ;
@property (nonatomic, strong) PHCachingImageManager *imageManager;

@property (nonatomic, strong) ASScanCache *cache;

@property (nonatomic, copy) ASScanProgressBlock progressBlock;
@property (nonatomic, copy) ASScanCompletionBlock completionBlock;

@property (nonatomic, strong) ASScanSnapshot *snapshot;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *duplicateGroups;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *similarGroups;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenshots;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenRecordings;
@property (nonatomic, strong) NSArray<ASAssetModel *> *bigVideos;

@property (atomic) BOOL cancelled;

// 索引加速：按 hash 前缀分桶，减少比较量
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *indexImage;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *indexVideo;

// 可变容器（扫描中）
@property (nonatomic, strong) NSMutableArray<ASAssetGroup *> *dupGroupsM;
@property (nonatomic, strong) NSMutableArray<ASAssetGroup *> *simGroupsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *screenshotsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *screenRecordingsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *bigVideosM;

// 当前天
@property (nonatomic, strong) NSDate *currentDay;
@end

@implementation ASPhotoScanManager

+ (instancetype)shared {
    static ASPhotoScanManager *m;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        m = [ASPhotoScanManager new];
    });
    return m;
}

- (instancetype)init {
    if (self=[super init]) {
        _workQ = dispatch_queue_create("as.photo.scan.q", DISPATCH_QUEUE_SERIAL);
        _imageManager = [PHCachingImageManager new];
        _snapshot = [ASScanSnapshot new];
        _duplicateGroups = @[];
        _similarGroups = @[];
        _screenshots = @[];
        _screenRecordings = @[];
        _bigVideos = @[];
        _indexImage = [NSMutableDictionary dictionary];
        _indexVideo = [NSMutableDictionary dictionary];
        _cache = [ASScanCache new];
        _visionMemo = [[NSCache alloc] init];
        _visionMemo.countLimit = 200;
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    }
    return self;
}

- (VNFeaturePrintObservation *)visionFeatureForLocalId:(NSString *)localId {
    if (!localId.length) return nil;
    if (@available(iOS 13.0, *)) {
        VNFeaturePrintObservation *cached = [self.visionMemo objectForKey:localId];
        if (cached) return cached;

        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:@[localId] options:nil];
        PHAsset *asset = fr.firstObject;
        if (!asset) return nil;

        @autoreleasepool {
            UIImage *thumb = [self requestThumbnailSyncForAsset:asset target:CGSizeMake(512, 512)];
            if (!thumb.CGImage) return nil;

            VNGenerateImageFeaturePrintRequest *req = [VNGenerateImageFeaturePrintRequest new];
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:thumb.CGImage options:@{}];

            NSError *err = nil;
            [handler performRequests:@[req] error:&err];
            if (err) return nil;

            VNFeaturePrintObservation *obs = (VNFeaturePrintObservation *)req.results.firstObject;
            if (![obs isKindOfClass:[VNFeaturePrintObservation class]]) return nil;

            [self.visionMemo setObject:obs forKey:localId];
            return obs;
        }
    }
    return nil;
}

- (float)visionDistanceBetweenLocalId:(NSString *)aId and:(NSString *)bId {
    if (@available(iOS 13.0, *)) {
        VNFeaturePrintObservation *a = [self visionFeatureForLocalId:aId];
        VNFeaturePrintObservation *b = [self visionFeatureForLocalId:bId];
        if (!a || !b) return FLT_MAX;

        float dist = 0.f;
        NSError *err = nil;
        [a computeDistance:&dist toFeaturePrintObservation:b error:&err];
        if (err) return FLT_MAX;
        return dist; // distance 越小越像
    }
    return FLT_MAX;
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

#pragma mark - Public

- (void)loadCacheAndCheckIncremental {
    [self loadCacheIfExists];

    // 先把缓存内容立即发布出去（同步）
    [self applyCacheToPublicState];

    // 然后再做增量检测
    [self checkIncrementalFromDiskAnchor];
}

- (void)startFullScanWithProgress:(ASScanProgressBlock)progress
                       completion:(ASScanCompletionBlock)completion
{
    self.progressBlock = progress;
    self.completionBlock = completion;
    self.cancelled = NO;

    self.snapshot = [ASScanSnapshot new];
    self.snapshot.state = ASScanStateScanning;
    [self emitProgress];

    dispatch_async(self.workQ, ^{
        @autoreleasepool {
            NSError *error = nil;

            // 清空容器
            self.dupGroupsM = [NSMutableArray array];
            self.simGroupsM = [NSMutableArray array];
            self.screenshotsM = [NSMutableArray array];
            self.screenRecordingsM = [NSMutableArray array];
            self.bigVideosM = [NSMutableArray array];
            [self.indexImage removeAllObjects];
            [self.indexVideo removeAllObjects];
            self.currentDay = nil;

            // 拉取所有资源：按 creationDate 降序
            PHFetchOptions *opt = [PHFetchOptions new];
            opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithOptions:opt];

            // 用于 anchorDate：记录本次扫描“最新时间戳”
            NSDate *maxAnchor = [NSDate dateWithTimeIntervalSince1970:0];

            for (PHAsset *asset in result) {
                @autoreleasepool {
                    if (self.cancelled) { error = [NSError errorWithDomain:@"ASPhotoScan" code:-999 userInfo:@{NSLocalizedDescriptionKey:@"cancelled"}]; break; }
                    
                    NSDate *cd = asset.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
                    NSDate *md = asset.modificationDate ?: cd;
                    if ([cd compare:maxAnchor] == NSOrderedDescending) maxAnchor = cd;
                    if ([md compare:maxAnchor] == NSOrderedDescending) maxAnchor = md;
                    
                    NSDate *day = ASDayStart(cd);
                    if (!self.currentDay) self.currentDay = day;
                    
                    // “按天扫描”：当天变化时可以在这里做一些统计或释放（当前实现是全局索引，不影响正确性）
                    if (![day isEqualToDate:self.currentDay]) {
                        self.currentDay = day;
                    }
                    
                    // 生成模型（包括 fileSize/pHash/vision）
                    ASAssetModel *model = [self buildModelForAsset:asset error:&error];
                    if (!model) { if (error) break; else continue; }
                    
                    // 总扫描统计
                    self.snapshot.scannedCount += 1;
                    self.snapshot.scannedBytes += model.fileSizeBytes;
                    
                    // 分类收集
                    if (ASIsScreenshot(asset)) {
                        [self.screenshotsM addObject:model];
                        self.snapshot.screenshotCount += 1;
                        self.snapshot.screenshotBytes += model.fileSizeBytes;
                        [self emitProgressMaybe];
                        continue;
                    }
                    
                    if (ASIsScreenRecording(asset)) {
                        [self.screenRecordingsM addObject:model];
                        self.snapshot.screenRecordingCount += 1;
                        self.snapshot.screenRecordingBytes += model.fileSizeBytes;
                        [self emitProgressMaybe];
                        continue;
                    }
                    
                    if (asset.mediaType == PHAssetMediaTypeVideo && model.fileSizeBytes >= kBigVideoMinBytes) {
                        [self.bigVideosM addObject:model];
                        self.snapshot.bigVideoCount += 1;
                        self.snapshot.bigVideoBytes += model.fileSizeBytes;
                        // 注意：大视频也可能参与相似/重复（只要不是录屏），你的需求没禁止
                    }
                    
                    // 相似/重复：排除截屏/录屏
                    if (!ASAllowedForCompare(asset)) {
                        [self emitProgressMaybe];
                        continue;
                    }
                    
                    // 分组（图片/视频分别进索引）
                    [self matchAndGroup:model asset:asset];
                    
                    // 更新可清理统计（每次分组后重算增量）
                    [self recomputeCleanableStatsFast];
                    
                    [self emitProgressMaybe];
                }
            }

            if (!error && !self.cancelled) {
                self.snapshot.state = ASScanStateFinished;
                self.snapshot.duplicateGroupCount = self.dupGroupsM.count;
                self.snapshot.similarGroupCount = self.simGroupsM.count;
                self.snapshot.lastUpdated = [NSDate date];

                // 写缓存
                self.cache.snapshot = self.snapshot;
                self.cache.duplicateGroups = [self.dupGroupsM copy];
                self.cache.similarGroups = [self.simGroupsM copy];
                self.cache.screenshots = [self.screenshotsM copy];
                self.cache.screenRecordings = [self.screenRecordingsM copy];
                self.cache.bigVideos = [self.bigVideosM copy];

                self.cache.anchorDate = maxAnchor;

                // 每三天刷新首页统计（这里只更新刷新时间戳；真正 UI 可用 snapshot）
                if ([self needRefreshHomeStat:self.cache.homeStatRefreshDate]) {
                    self.cache.homeStatRefreshDate = [NSDate date];
                }

                [self saveCache];
                [self applyCacheToPublicState];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.completionBlock) self.completionBlock(self.snapshot, error);
            });
        }
    });
}

- (void)cancel {
    self.cancelled = YES;
}

#pragma mark - Selection helpers

- (NSArray<ASAssetModel *> *)allCleanableAssets {
    NSMutableArray *arr = [NSMutableArray array];
    for (ASAssetGroup *g in self.duplicateGroups) {
        for (NSInteger i=1; i<g.assets.count; i++) [arr addObject:g.assets[i]];
    }
    for (ASAssetGroup *g in self.similarGroups) {
        for (NSInteger i=1; i<g.assets.count; i++) [arr addObject:g.assets[i]];
    }
    return arr;
}

- (NSArray<ASAssetModel *> *)allScreenshotAssets { return self.screenshots ?: @[]; }
- (NSArray<ASAssetModel *> *)allScreenRecordingAssets { return self.screenRecordings ?: @[]; }
- (NSArray<ASAssetModel *> *)allBigVideoAssets { return self.bigVideos ?: @[]; }

#pragma mark - PHPhotoLibraryChangeObserver (实时监听增量)

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    // 这里不走 fetchResultChangeDetails（因为我们用的是“缓存+anchorDate”策略）
    // 触发后做一次轻量增量检查：新增/修改/删除
    [self checkIncrementalFromDiskAnchor];
}

#pragma mark - Incremental after restart / change

- (void)checkIncrementalFromDiskAnchor {
    dispatch_async(self.workQ, ^{
        if (self.cache.snapshot.state != ASScanStateFinished) return;

        NSDate *anchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];

        // 1) 检测新增/修改：creationDate 或 modificationDate > anchor
        PHFetchOptions *opt = [PHFetchOptions new];
        opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        opt.predicate = [NSPredicate predicateWithFormat:
                         @"(creationDate > %@) OR (modificationDate > %@)",
                         anchor, anchor];

        PHFetchResult<PHAsset *> *delta = [PHAsset fetchAssetsWithOptions:opt];

        // 2) 检测删除：把缓存中所有 localId 再 fetch 一次，找不到的就当删除
        // 为了不太重，这里只在有 delta 或定期触发时做一次
        BOOL needDeleteCheck = (delta.count > 0);
        if (!needDeleteCheck) return;

        NSMutableSet<NSString *> *cachedIds = [NSMutableSet set];
        for (ASAssetGroup *g in self.cache.duplicateGroups) for (ASAssetModel *m in g.assets) [cachedIds addObject:m.localId];
        for (ASAssetGroup *g in self.cache.similarGroups) for (ASAssetModel *m in g.assets) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.screenshots) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.screenRecordings) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.bigVideos) [cachedIds addObject:m.localId];

        PHFetchResult<PHAsset *> *exist = [PHAsset fetchAssetsWithLocalIdentifiers:cachedIds.allObjects options:nil];
        NSMutableSet<NSString *> *existIds = [NSMutableSet set];
        for (PHAsset *a in exist) [existIds addObject:a.localIdentifier];

        NSMutableSet<NSString *> *deleted = [cachedIds mutableCopy];
        [deleted minusSet:existIds];

        if (delta.count == 0 && deleted.count == 0) return;

        // 应用增量：这里采取“局部更新”策略（新增插入分组；删除从所有容器移除）
        NSError *err = nil;

        // 先把缓存容器加载到可变形式
        self.dupGroupsM = [self deepMutableGroups:self.cache.duplicateGroups];
        self.simGroupsM = [self deepMutableGroups:self.cache.similarGroups];
        self.screenshotsM = [self.cache.screenshots mutableCopy] ?: [NSMutableArray array];
        self.screenRecordingsM = [self.cache.screenRecordings mutableCopy] ?: [NSMutableArray array];
        self.bigVideosM = [self.cache.bigVideos mutableCopy] ?: [NSMutableArray array];

        // 重建索引（只从缓存数据）
        [self.indexImage removeAllObjects];
        [self.indexVideo removeAllObjects];
        [self rebuildIndexFromGroups];

        // 删除
        if (deleted.count > 0) {
            [self removeModelsByIds:deleted];
        }

        // 新增/修改：直接按全量同样流程建 model 然后插入
        NSDate *newAnchor = anchor;
        for (PHAsset *a in delta) {
            ASAssetModel *m = [self buildModelForAsset:a error:&err];
            if (!m) continue;

            NSDate *cd = a.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
            NSDate *md = a.modificationDate ?: cd;
            if ([cd compare:newAnchor] == NSOrderedDescending) newAnchor = cd;
            if ([md compare:newAnchor] == NSOrderedDescending) newAnchor = md;

            // 分类更新
            if (ASIsScreenshot(a)) {
                [self.screenshotsM addObject:m];
                continue;
            }
            if (ASIsScreenRecording(a)) {
                [self.screenRecordingsM addObject:m];
                continue;
            }
            if (a.mediaType == PHAssetMediaTypeVideo && m.fileSizeBytes >= kBigVideoMinBytes) {
                [self.bigVideosM addObject:m];
            }
            if (ASAllowedForCompare(a)) {
                [self matchAndGroup:m asset:a];
            }
        }

        // 重算 snapshot（简单起见做一次全重算，保证一致性）
        [self recomputeSnapshotFromCurrentContainers];
        self.cache.anchorDate = newAnchor;
        self.cache.snapshot = self.snapshot;
        self.cache.duplicateGroups = [self.dupGroupsM copy];
        self.cache.similarGroups = [self.simGroupsM copy];
        self.cache.screenshots = [self.screenshotsM copy];
        self.cache.screenRecordings = [self.screenRecordingsM copy];
        self.cache.bigVideos = [self.bigVideosM copy];
        [self saveCache];
        [self applyCacheToPublicState];

        [self emitProgress];
    });
}

#pragma mark - Build model (size + phash + vision)

- (ASAssetModel *)buildModelForAsset:(PHAsset *)asset error:(NSError **)err {
    ASAssetModel *m = [ASAssetModel new];
    m.localId = asset.localIdentifier ?: @"";
    m.mediaType = asset.mediaType;
    m.subtypes = asset.mediaSubtypes;
    m.creationDate = asset.creationDate;
    m.modificationDate = asset.modificationDate;

    // file size
    uint64_t size = [self fetchFileSizeForAsset:asset];
    m.fileSizeBytes = size;

    // pHash + vision 只对允许参与相似/重复的做（你要求排除截屏/录屏）
    if (ASAllowedForCompare(asset)) {
        UIImage *thumb = nil;

        if (asset.mediaType == PHAssetMediaTypeVideo) {
            Float64 dur = asset.duration;
            Float64 t = dur > 0 ? dur * 0.30 : 1.0;
            thumb = [self requestVideoFrameSyncForAsset:asset seconds:t target:CGSizeMake(256, 256)];
            if (!thumb) thumb = [self requestVideoFrameSyncForAsset:asset seconds:1.0 target:CGSizeMake(256, 256)];
        } else {
            thumb = [self requestThumbnailSyncForAsset:asset target:CGSizeMake(128, 128)];
        }

        if (thumb) {
            m.phash256Data = [self computeColorPHash256Data:thumb];
            // Vision 建议也用更大的帧，但同样来源于“真实视频帧”
            m.visionPrintData = [self computeVisionPrintDataFromImage:thumb];  // 你如果改成按需算，也OK
        }
    }
    return m;
}


- (uint64_t)fetchFileSizeForAsset:(PHAsset *)asset {
    __block uint64_t size = 0;
    NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
    for (PHAssetResource *r in resources) {
        NSNumber *s = [r valueForKey:@"fileSize"];
        if ([s isKindOfClass:[NSNumber class]]) size += s.unsignedLongLongValue;
    }
    return size;
}

- (UIImage *)requestThumbnailSyncForAsset:(PHAsset *)asset target:(CGSize)target {
    __block UIImage *img = nil;
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.synchronous = YES;
    opt.networkAccessAllowed = NO;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;

    [self.imageManager requestImageForAsset:asset
                                 targetSize:target
                                contentMode:PHImageContentModeAspectFill
                                    options:opt
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        img = result;
    }];
    return img;
}

- (UIImage *)requestVideoFrameSyncForAsset:(PHAsset *)asset seconds:(Float64)seconds target:(CGSize)target {
    if (asset.mediaType != PHAssetMediaTypeVideo) return nil;

    __block UIImage *outImg = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    PHVideoRequestOptions *opt = [PHVideoRequestOptions new];
    opt.networkAccessAllowed = NO;

    [self.imageManager requestAVAssetForVideo:asset options:opt resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        @autoreleasepool {
            if (!avAsset) { dispatch_semaphore_signal(sema); return; }

            AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:avAsset];
            gen.appliesPreferredTrackTransform = YES;
            gen.requestedTimeToleranceBefore = kCMTimeZero;
            gen.requestedTimeToleranceAfter  = kCMTimeZero;

            // 控制输出大小（避免内存爆）
            if (!CGSizeEqualToSize(target, CGSizeZero)) {
                gen.maximumSize = target;
            }

            CMTime t = CMTimeMakeWithSeconds(seconds, 600);
            NSError *err = nil;
            CGImageRef cg = [gen copyCGImageAtTime:t actualTime:NULL error:&err];
            if (cg && !err) {
                outImg = [UIImage imageWithCGImage:cg];
                CGImageRelease(cg);
            }
            dispatch_semaphore_signal(sema);
        }
    }];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    return outImg;
}

#pragma mark - Color pHash 256-bit

static inline int ASHamming256(NSData *a, NSData *b) {
    if (a.length < 32 || b.length < 32) return INT_MAX;
    const uint64_t *pa = (const uint64_t *)a.bytes;
    const uint64_t *pb = (const uint64_t *)b.bytes;
    int count = 0;
    for (int i = 0; i < 4; i++) {
        count += __builtin_popcountll(pa[i] ^ pb[i]);
    }
    return count;
}

static inline NSNumber *ASBucketKeyForPHash256(NSData *d) {
    if (d.length < 32) return @(0);
    const uint64_t *p = (const uint64_t *)d.bytes;
    uint8_t key = (uint8_t)((p[0] >> 56) & 0xFF);
    return @(key);
}

static inline float ASClamp255(float x) {
    if (x < 0.f) return 0.f;
    if (x > 255.f) return 255.f;
    return x;
}

static int ASFloatCmp(const void *a, const void *b) {
    float fa = *(const float *)a;
    float fb = *(const float *)b;
    return (fa > fb) - (fa < fb);
}

// 预计算 cos 表：cos( (pi/N) * (n+0.5) * k )
static const int kASDCTN = 64;
static const int kASDCTSize = 64 * 64;
static float *ASDCTCosTable(void) {
    static float table[kASDCTSize];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const double N = (double)kASDCTN;
        const double coef = M_PI / N;
        for (int k = 0; k < kASDCTN; k++) {
            for (int n = 0; n < kASDCTN; n++) {
                table[k*kASDCTN + n] = (float)cos(coef * ((double)n + 0.5) * (double)k);
            }
        }
    });
    return table;
}

// 1D DCT-II（不做额外归一化；pHash 用 median 阈值，整体缩放不影响）
// out[k] = sum_{n} in[n] * cos(...)
static inline void ASDCT1D_64(const float *in, float *out) {
    const float *cosT = ASDCTCosTable();
    for (int k = 0; k < 64; k++) {
        const float *row = &cosT[k*64];
        float sum = 0.f;
        // 64 很小，直接循环稳定
        for (int n = 0; n < 64; n++) {
            sum += in[n] * row[n];
        }
        out[k] = sum;
    }
}

// 返回 32 bytes：4 * UInt64（bit 排布与你 Swift 一致：offset = 63 - (i % 64)）
- (NSData *)computeColorPHash256Data:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg) {
        uint64_t z[4] = {0,0,0,0};
        return [NSData dataWithBytes:z length:32];
    }

    const int width = 64;
    const int height = 64;
    const int bytesPerRow = width * 4;

    // RGBA 像素
    uint8_t pixels[64*64*4];
    memset(pixels, 0, sizeof(pixels));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        pixels,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast
    );
    CGColorSpaceRelease(colorSpace);

    if (!ctx) {
        uint64_t z[4] = {0,0,0,0};
        return [NSData dataWithBytes:z length:32];
    }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(ctx);

    // Swift 同款增强 + 灰度（把 r/g/b 都写成 enhanced）
    float floatPixels[64*64];
    for (int i = 0; i < width*height; i++) {
        float r = (float)pixels[i*4 + 0];
        float g = (float)pixels[i*4 + 1];
        float b = (float)pixels[i*4 + 2];

        float luma = 0.299f*r + 0.587f*g + 0.114f*b;
        float enhanced = ASClamp255(1.1f*luma - 10.f);

        // Swift 里把 RGB 都设为 enhanced；我们只需要 floatPixels
        floatPixels[i] = enhanced;
    }

    // 2D DCT：先行后列（与你 Swift 一致）
    float rowIn[64], rowOut[64];
    // 行 DCT
    for (int row = 0; row < 64; row++) {
        memcpy(rowIn, &floatPixels[row*64], sizeof(rowIn));
        ASDCT1D_64(rowIn, rowOut);
        memcpy(&floatPixels[row*64], rowOut, sizeof(rowOut));
    }

    // 列 DCT
    float colIn[64], colOut[64];
    for (int col = 0; col < 64; col++) {
        for (int row = 0; row < 64; row++) {
            colIn[row] = floatPixels[row*64 + col];
        }
        ASDCT1D_64(colIn, colOut);
        for (int row = 0; row < 64; row++) {
            floatPixels[row*64 + col] = colOut[row];
        }
    }

    // 取左上 16x16
    float topLeft[16*16];
    int idx = 0;
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            topLeft[idx++] = floatPixels[r*64 + c];
        }
    }

    // median
    float sorted[16*16];
    memcpy(sorted, topLeft, sizeof(sorted));
    qsort(sorted, 256, sizeof(float), ASFloatCmp);
    float median = sorted[256/2];

    // 生成 256-bit hash（4*UInt64）
    uint64_t hash[4] = {0,0,0,0};
    for (int i = 0; i < 256; i++) {
        if (topLeft[i] > median) {
            int word = i / 64;
            int offset = 63 - (i % 64);   // ✅ 与 Swift 一致
            hash[word] |= (1ULL << (uint64_t)offset);
        }
    }

    return [NSData dataWithBytes:hash length:32];
}


#pragma mark - Vision FeaturePrint

- (NSData *)computeVisionPrintDataFromImage:(UIImage *)image {
    if (@available(iOS 13.0, *)) {
        CGImageRef cg = image.CGImage;
        if (!cg) return nil;

        VNGenerateImageFeaturePrintRequest *req = [VNGenerateImageFeaturePrintRequest new];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];

        NSError *error = nil;
        [handler performRequests:@[req] error:&error];
        if (error) return nil;

        VNFeaturePrintObservation *obs = (VNFeaturePrintObservation *)req.results.firstObject;
        if (![obs isKindOfClass:[VNFeaturePrintObservation class]]) return nil;

        // 归档保存（用于缓存）
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obs requiringSecureCoding:YES error:nil];
        return data;
    }
    return nil;
}

- (float)visionDistanceBetween:(ASAssetModel *)a and:(ASAssetModel *)b {
    if (@available(iOS 13.0, *)) {
        if (!a.visionPrintData || !b.visionPrintData) return FLT_MAX;

        VNFeaturePrintObservation *oa =
        [NSKeyedUnarchiver unarchivedObjectOfClass:[VNFeaturePrintObservation class]
                                          fromData:a.visionPrintData
                                             error:nil];
        VNFeaturePrintObservation *ob =
        [NSKeyedUnarchiver unarchivedObjectOfClass:[VNFeaturePrintObservation class]
                                          fromData:b.visionPrintData
                                             error:nil];
        if (!oa || !ob) return FLT_MAX;

        float dist = 0.f;
        NSError *err = nil;
        [oa computeDistance:&dist toFeaturePrintObservation:ob error:&err];
        if (err) return FLT_MAX;

        return dist; //  直接返回 distance
    }
    return FLT_MAX;
}


#pragma mark - Grouping

- (NSNumber *)bucketKeyForHash:(uint64_t)h {
    uint8_t key = (uint8_t)((h >> 56) & 0xFF); // 0..255
    return @(key);
}

- (void)matchAndGroup:(ASAssetModel *)model asset:(PHAsset *)asset {
    if (!model.phash256Data || model.phash256Data.length < 32) return;

    BOOL isImage = (asset.mediaType == PHAssetMediaTypeImage);
    NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *index = isImage ? self.indexImage : self.indexVideo;

    NSNumber *k = ASBucketKeyForPHash256(model.phash256Data);
    NSMutableArray<ASAssetModel *> *pool = index[k];
    if (!pool) { pool = [NSMutableArray array]; index[k] = pool; }

    ASAssetModel *hit = nil;
    ASGroupType hitType = isImage ? ASGroupTypeDuplicateImage : ASGroupTypeDuplicateVideo;

    for (ASAssetModel *cand in pool) {
        if (!cand.phash256Data || cand.phash256Data.length < 32) continue;

        // ✅ 1) pHash 汉明距离粗筛（只算一次）
        int hd = ASHamming256(model.phash256Data, cand.phash256Data);
        if (hd > kPolicySimilar.phashThreshold) continue;   // 连 similar 都过不了，直接跳

        // ✅ 2) 通过粗筛才算 Vision distance（按需计算，避免内存爆）
        float vd = [self visionDistanceBetweenLocalId:model.localId and:cand.localId];
        if (vd == FLT_MAX) continue;

        // ✅ 3) duplicate 优先
        if (hd <= kPolicyDuplicate.phashThreshold && vd <= kPolicyDuplicate.visionThreshold) {
            hit = cand;
            hitType = isImage ? ASGroupTypeDuplicateImage : ASGroupTypeDuplicateVideo;
            break;
        }

        // ✅ 4) similar
        if (vd <= kPolicySimilar.visionThreshold) {
            hit = cand;
            hitType = isImage ? ASGroupTypeSimilarImage : ASGroupTypeSimilarVideo;
            break;
        }
    }

    if (!hit) {
        [pool addObject:model];
        return;
    }

    if (![self appendModel:model toExistingGroupByAnyMemberId:hit.localId groupType:hitType]) {
        ASAssetGroup *g = [ASAssetGroup new];
        g.type = hitType;
        g.assets = [NSMutableArray arrayWithObjects:hit, model, nil];
        if (hitType == ASGroupTypeDuplicateImage || hitType == ASGroupTypeDuplicateVideo) {
            [self.dupGroupsM addObject:g];
        } else {
            [self.simGroupsM addObject:g];
        }
    }

    [pool addObject:model];
}


- (BOOL)appendModel:(ASAssetModel *)model toExistingGroupByAnyMemberId:(NSString *)memberId groupType:(ASGroupType)type {
    NSArray<ASAssetGroup *> *targets = (type==ASGroupTypeDuplicateImage || type==ASGroupTypeDuplicateVideo) ? self.dupGroupsM : self.simGroupsM;
    for (ASAssetGroup *g in targets) {
        if (g.type != type) continue;
        for (ASAssetModel *m in g.assets) {
            if ([m.localId isEqualToString:memberId]) {
                [g.assets addObject:model];
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Cleanable stats

- (void)recomputeCleanableStatsFast {
    // 这里做“全局重算 cleanable”，保证准确（组数量通常不大）
    uint64_t bytes = 0;
    NSUInteger count = 0;

    for (ASAssetGroup *g in self.dupGroupsM) {
        for (NSInteger i=1; i<g.assets.count; i++) { bytes += g.assets[i].fileSizeBytes; count += 1; }
    }
    for (ASAssetGroup *g in self.simGroupsM) {
        for (NSInteger i=1; i<g.assets.count; i++) { bytes += g.assets[i].fileSizeBytes; count += 1; }
    }

    self.snapshot.cleanableBytes = bytes;
    self.snapshot.cleanableCount = count;
    self.snapshot.duplicateGroupCount = self.dupGroupsM.count;
    self.snapshot.similarGroupCount = self.simGroupsM.count;
    self.snapshot.lastUpdated = [NSDate date];
}

- (void)recomputeSnapshotFromCurrentContainers {
    ASScanSnapshot *s = [ASScanSnapshot new];
    s.state = ASScanStateFinished;

    // scanned 统计：用容器反算（不含未参与容器的？这里以缓存的容器为准）
    // 如果你需要严格等于相册总数，就应该存 “scannedCount/Bytes” 到缓存（我们已有 snapshot，可直接沿用）
    // 这里做一个合理重算：把所有容器的 size/count 相加近似
    NSMutableSet *ids = [NSMutableSet set];
    __block uint64_t scannedBytes = 0;

    void (^addArr)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr){
        for (ASAssetModel *m in arr) {
            if ([ids containsObject:m.localId]) continue;
            [ids addObject:m.localId];
            scannedBytes += m.fileSizeBytes;
        }
    };

    for (ASAssetGroup *g in self.dupGroupsM) addArr(g.assets);
    for (ASAssetGroup *g in self.simGroupsM) addArr(g.assets);
    addArr(self.screenshotsM);
    addArr(self.screenRecordingsM);
    addArr(self.bigVideosM);

    s.scannedCount = ids.count;
    s.scannedBytes = scannedBytes;

    // 分类统计
    s.screenshotCount = self.screenshotsM.count;
    for (ASAssetModel *m in self.screenshotsM) s.screenshotBytes += m.fileSizeBytes;

    s.screenRecordingCount = self.screenRecordingsM.count;
    for (ASAssetModel *m in self.screenRecordingsM) s.screenRecordingBytes += m.fileSizeBytes;

    s.bigVideoCount = self.bigVideosM.count;
    for (ASAssetModel *m in self.bigVideosM) s.bigVideoBytes += m.fileSizeBytes;

    // 组统计 & cleanable
    self.snapshot = s;
    [self recomputeCleanableStatsFast];
}

#pragma mark - Delete remove

- (void)removeModelsByIds:(NSSet<NSString *> *)ids {
    // groups
    NSArray *(^filterGroups)(NSArray<ASAssetGroup *> *) = ^NSArray *(NSArray<ASAssetGroup *> *groups){
        NSMutableArray *out = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            NSMutableArray *kept = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (![ids containsObject:m.localId]) [kept addObject:m];
            }
            // 组里少于 2 个就丢掉（不再构成相似/重复组）
            if (kept.count >= 2) {
                g.assets = kept;
                [out addObject:g];
            }
        }
        return out;
    };

    self.dupGroupsM = [[filterGroups(self.dupGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];
    self.simGroupsM = [[filterGroups(self.simGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];

    // lists
    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(ASAssetModel *m, NSDictionary *_) {
        return ![ids containsObject:m.localId];
    }];

    self.screenshotsM = [[self.screenshotsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.screenRecordingsM = [[self.screenRecordingsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.bigVideosM = [[self.bigVideosM filteredArrayUsingPredicate:keep] mutableCopy];

    // rebuild index
    [self.indexImage removeAllObjects];
    [self.indexVideo removeAllObjects];
    [self rebuildIndexFromGroups];
}

#pragma mark - Index rebuild

- (NSMutableArray<ASAssetGroup *> *)deepMutableGroups:(NSArray<ASAssetGroup *> *)groups {
    NSMutableArray *out = [NSMutableArray array];
    for (ASAssetGroup *g in groups) {
        ASAssetGroup *ng = [ASAssetGroup new];
        ng.type = g.type;
        ng.assets = [g.assets mutableCopy] ?: [NSMutableArray array];
        [out addObject:ng];
    }
    return out;
}

- (void)rebuildIndexFromGroups {
    void (^addModel)(ASAssetModel *, BOOL) = ^(ASAssetModel *m, BOOL isImage){
        NSNumber *k = [self bucketKeyForHash:m.pHash];
        NSMutableDictionary *index = isImage ? self.indexImage : self.indexVideo;
        NSMutableArray *pool = index[k];
        if (!pool) { pool = [NSMutableArray array]; index[k]=pool; }
        [pool addObject:m];
    };

    for (ASAssetGroup *g in self.dupGroupsM) {
        BOOL isImage = (g.type == ASGroupTypeDuplicateImage);
        for (ASAssetModel *m in g.assets) addModel(m, isImage);
    }
    for (ASAssetGroup *g in self.simGroupsM) {
        BOOL isImage = (g.type == ASGroupTypeSimilarImage);
        for (ASAssetModel *m in g.assets) addModel(m, isImage);
    }
}

- (void)publishLiveContainers {
    // 扫描中把当前扫描到的容器“快照”发布到对外只读属性
    // 必须 copy，防止主线程读取时后台线程还在改导致崩溃
    NSArray<ASAssetGroup *> *dupCopy = [self.dupGroupsM copy] ?: @[];
    NSArray<ASAssetGroup *> *simCopy = [self.simGroupsM copy] ?: @[];
    NSArray<ASAssetModel *> *shotCopy = [self.screenshotsM copy] ?: @[];
    NSArray<ASAssetModel *> *recCopy  = [self.screenRecordingsM copy] ?: @[];
    NSArray<ASAssetModel *> *bigCopy  = [self.bigVideosM copy] ?: @[];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.duplicateGroups = dupCopy;
        self.similarGroups = simCopy;
        self.screenshots = shotCopy;
        self.screenRecordings = recCopy;
        self.bigVideos = bigCopy;
    });
}


#pragma mark - Cache IO

- (void)loadCacheIfExists {
    NSData *d = [NSData dataWithContentsOfFile:ASCachePath()];
    if (!d) { NSLog(@"[ASCache] no cache file"); self.cache = [ASScanCache new]; return; }

    NSError *err = nil;
    ASScanCache *c = [NSKeyedUnarchiver unarchivedObjectOfClass:[ASScanCache class] fromData:d error:&err];
    if (!c || err) {
        NSLog(@"[ASCache] load failed: %@", err);
        self.cache = [ASScanCache new];
        return;
    }
    NSLog(@"[ASCache] load OK");
    self.cache = c;
}

- (void)saveCache {
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:self.cache requiringSecureCoding:YES error:&err];
    if (!d || err) {
        NSLog(@"[ASCache] save failed: %@", err);
        return;
    }
    BOOL ok = [d writeToFile:ASCachePath() atomically:YES];
    NSLog(@"[ASCache] save %@ path=%@", ok ? @"OK" : @"FAIL", ASCachePath());
}


- (void)applyCacheToPublicState {
    void (^assign)(void) = ^{
        self.snapshot = self.cache.snapshot ?: [ASScanSnapshot new];
        self.duplicateGroups = self.cache.duplicateGroups ?: @[];
        self.similarGroups = self.cache.similarGroups ?: @[];
        self.screenshots = self.cache.screenshots ?: @[];
        self.screenRecordings = self.cache.screenRecordings ?: @[];
        self.bigVideos = self.cache.bigVideos ?: @[];
    };

    if ([NSThread isMainThread]) {
        assign();                    // ✅ 立即生效
    } else {
        dispatch_async(dispatch_get_main_queue(), assign);
    }
}

#pragma mark - Home stat refresh rule (3 days)

- (BOOL)needRefreshHomeStat:(NSDate *)last {
    NSTimeInterval dt = [[NSDate date] timeIntervalSinceDate:last ?: [NSDate dateWithTimeIntervalSince1970:0]];
    return dt > 3 * 24 * 3600;
}

#pragma mark - Progress emit

- (void)emitProgress {
    self.snapshot.lastUpdated = [NSDate date];

    // ✅ 让 HomeVC 每次 progress 都能读到“最新 groups/lists”
    [self publishLiveContainers];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) self.progressBlock(self.snapshot);
    });
}


- (void)emitProgressMaybe {
    // 控制频率：每 20 个或每 0.3s 刷一次
    static CFTimeInterval lastT = 0;
    CFTimeInterval t = CACurrentMediaTime();
    if (self.snapshot.scannedCount % 20 == 0 || (t - lastT) > 0.3) {
        lastT = t;
        [self emitProgress];
    }
}

@end
