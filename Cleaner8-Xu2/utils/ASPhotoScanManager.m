#import "ASPhotoScanManager.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <float.h>

static const float kBlurKeepPercent = 0.05f;   // 保留最差 5%
static const NSUInteger kBlurKeepMin = 40;     // 至少 40 张
static const NSUInteger kBlurKeepMax = 300;    // 最多 300 张
static const NSUInteger kBlurWarmup  = 80;     // 前 80 张只收集，不入榜（稳定分布）

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

// Blur
static int gBlurDebugPrinted = 0;

static NSCache<NSString*, NSNumber*> *ASBlurMemo(void) {
    static NSCache *c;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c = [NSCache new];
        c.countLimit = 20000;
    });
    return c;
}

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

static CGImagePropertyOrientation ASCGImageOrientationFromUIImage(UIImageOrientation o) {
    switch (o) {
        case UIImageOrientationUp: return kCGImagePropertyOrientationUp;
        case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
        case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
        case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
    }
    return kCGImagePropertyOrientationUp;
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

    if (abs(ww - s.longSide) <= s.pxEpsilon &&
        abs(hh - s.shortSide) <= s.pxEpsilon) {
        return YES;
    }

    int64_t lhs = (int64_t)ww * (int64_t)s.shortSide;
    int64_t rhs = (int64_t)hh * (int64_t)s.longSide;
    int64_t diff = llabs(lhs - rhs);
    int64_t base = MAX(lhs, rhs);

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
        is16x9 = (diff * 1000 <= base * 10); // ≤ 1%
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

    NSString *key = asset.localIdentifier ?: @"";
    NSCache *memo = ASScreenRecordingMemo();
    NSNumber *cached = [memo objectForKey:key];
    if (cached) return cached.boolValue;

    int w = (int)asset.pixelWidth;
    int h = (int)asset.pixelHeight;

    BOOL isSR = NO;

    if (ASApproxScreenAspect(w, h)) {
        if (!ASIsDeviceApprox16x9()) {
            isSR = YES;
        } else {
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

#pragma mark - Models

@implementation ASScanSnapshot
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init {
    // ✅ 9 个模块状态
    _moduleStates = @[
      @(ASModuleScanStateIdle),@(ASModuleScanStateIdle),@(ASModuleScanStateIdle),
      @(ASModuleScanStateIdle),@(ASModuleScanStateIdle),@(ASModuleScanStateIdle),
      @(ASModuleScanStateIdle),@(ASModuleScanStateIdle),@(ASModuleScanStateIdle)
    ];

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
    [coder encodeInteger:self.blurryCount forKey:@"blurryCount"];
    [coder encodeInt64:(int64_t)self.blurryBytes forKey:@"blurryBytes"];
    [coder encodeInteger:self.otherCount forKey:@"otherCount"];
    [coder encodeInt64:(int64_t)self.otherBytes forKey:@"otherBytes"];
    [coder encodeInteger:self.duplicateGroupCount forKey:@"duplicateGroupCount"];
    [coder encodeInteger:self.similarGroupCount forKey:@"similarGroupCount"];
    [coder encodeObject:self.lastUpdated forKey:@"lastUpdated"];
    [coder encodeObject:self.phash256Data forKey:@"phash256Data"];
    [coder encodeObject:self.moduleStates forKey:@"moduleStates"];
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
        _blurryCount = [coder decodeIntegerForKey:@"blurryCount"];
        _blurryBytes = (uint64_t)[coder decodeInt64ForKey:@"blurryBytes"];
        _otherCount = [coder decodeIntegerForKey:@"otherCount"];
        _otherBytes = (uint64_t)[coder decodeInt64ForKey:@"otherBytes"];
        _duplicateGroupCount = [coder decodeIntegerForKey:@"duplicateGroupCount"];
        _similarGroupCount = [coder decodeIntegerForKey:@"similarGroupCount"];
        _lastUpdated = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastUpdated"] ?: [NSDate date];
        _phash256Data = [coder decodeObjectOfClass:[NSData class] forKey:@"phash256Data"];

        NSSet *classes = [NSSet setWithArray:@[[NSArray class],[NSNumber class]]];
        _moduleStates = [coder decodeObjectOfClasses:classes forKey:@"moduleStates"];
        if (!_moduleStates || _moduleStates.count != 9) {
            _moduleStates = @[@0,@0,@0,@0,@0,@0,@0,@0,@0];
        }
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
    [coder encodeObject:self.phash256Data forKey:@"phash256Data"];
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
@property (nonatomic, strong) NSArray<ASAssetModel *> *blurryPhotos;
@property (nonatomic, strong) NSArray<ASAssetModel *> *otherPhotos;

@property (nonatomic, strong) ASScanSnapshot *snapshot;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *duplicateGroups;
@property (nonatomic, strong) NSArray<ASAssetGroup *> *similarGroups;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenshots;
@property (nonatomic, strong) NSArray<ASAssetModel *> *screenRecordings;
@property (nonatomic, strong) NSArray<ASAssetModel *> *bigVideos;

@property (nonatomic, strong) NSArray<ASAssetModel *> *comparableImages;
@property (nonatomic, strong) NSArray<ASAssetModel *> *comparableVideos;

@property (nonatomic, strong) NSDate *anchorDate;
@property (nonatomic, strong) NSDate *homeStatRefreshDate;
@property (nonatomic, assign) float blurScore;
@end

@implementation ASScanCache
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init {
    if (self=[super init]) {
        _snapshot=[ASScanSnapshot new];
        _anchorDate=[NSDate dateWithTimeIntervalSince1970:0];
        _homeStatRefreshDate=[NSDate dateWithTimeIntervalSince1970:0];
        _duplicateGroups=@[];
        _similarGroups=@[];
        _screenshots=@[];
        _screenRecordings=@[];
        _bigVideos=@[];
        _comparableImages=@[];
        _comparableVideos=@[];
        _blurryPhotos=@[];
        _otherPhotos=@[];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.snapshot forKey:@"snapshot"];
    [coder encodeObject:self.duplicateGroups forKey:@"duplicateGroups"];
    [coder encodeObject:self.similarGroups forKey:@"similarGroups"];
    [coder encodeObject:self.screenshots forKey:@"screenshots"];
    [coder encodeObject:self.screenRecordings forKey:@"screenRecordings"];
    [coder encodeObject:self.bigVideos forKey:@"bigVideos"];
    [coder encodeObject:self.anchorDate forKey:@"anchorDate"];
    [coder encodeObject:self.homeStatRefreshDate forKey:@"homeStatRefreshDate"];
    [coder encodeObject:self.comparableImages forKey:@"comparableImages"];
    [coder encodeObject:self.comparableVideos forKey:@"comparableVideos"];
    [coder encodeObject:self.blurryPhotos forKey:@"blurryPhotos"];
    [coder encodeObject:self.otherPhotos forKey:@"otherPhotos"];
    [coder encodeFloat:self.blurScore forKey:@"blurScore"];
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
        _comparableImages = [coder decodeObjectOfClasses:aClasses forKey:@"comparableImages"] ?: @[];
        _comparableVideos = [coder decodeObjectOfClasses:aClasses forKey:@"comparableVideos"] ?: @[];
        _blurryPhotos = [coder decodeObjectOfClasses:aClasses forKey:@"blurryPhotos"] ?: @[];
        _otherPhotos  = [coder decodeObjectOfClasses:aClasses forKey:@"otherPhotos"] ?: @[];
        _blurScore = [coder decodeFloatForKey:@"blurScore"];
    }
    return self;
}
@end

typedef NS_ENUM(NSUInteger, ASHomeModuleType) {
    ASHomeModuleTypeSimilarImage = 0,
    ASHomeModuleTypeSimilarVideo,
    ASHomeModuleTypeDuplicateImage,
    ASHomeModuleTypeDuplicateVideo,
    ASHomeModuleTypeScreenshots,
    ASHomeModuleTypeScreenRecordings,
    ASHomeModuleTypeBigVideos,
    ASHomeModuleTypeBlurryPhotos,
    ASHomeModuleTypeOtherPhotos,
};

#pragma mark - Manager

@interface ASPhotoScanManager ()
@property (nonatomic, assign) NSUInteger blurryImagesSeen;
@property (nonatomic, assign) uint64_t blurryBytesRunning;

- (BOOL)matchAndGroup:(ASAssetModel *)model asset:(PHAsset *)asset;

@property (atomic) BOOL pendingIncremental;
@property (atomic) BOOL incrementalScheduled;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *allAssetsFetchResult;
@property (nonatomic, strong) NSMutableDictionary<NSString*, PHAsset*> *pendingInsertedMap; // id->asset
@property (nonatomic, strong) NSMutableSet<NSString*> *pendingRemovedIDs;
@property (nonatomic, strong) dispatch_block_t incrementalDebounceBlock;

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

@property (nonatomic, strong) NSArray<ASAssetModel *> *blurryPhotos;
@property (nonatomic, strong) NSArray<ASAssetModel *> *otherPhotos;

// index
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *indexImage;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *indexVideo;

// mutable containers
@property (nonatomic, strong) NSMutableArray<ASAssetGroup *> *dupGroupsM;
@property (nonatomic, strong) NSMutableArray<ASAssetGroup *> *simGroupsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *screenshotsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *screenRecordingsM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *bigVideosM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *blurryPhotosM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *otherPhotosM;

// comparable pools
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *comparableImagesM;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *comparableVideosM;

@property (nonatomic, strong) NSMutableDictionary<NSString*, ASAssetModel*> *otherCandidateMap;
@property (atomic) uint64_t otherCandidateBytes;

// day
@property (nonatomic, strong) NSDate *currentDay;
@property (nonatomic, assign) BOOL didLoadCacheFromDisk;

@property (atomic) BOOL cancelled;
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

- (void)refreshAllAssetsFetchResult {
    self.allAssetsFetchResult = [PHAsset fetchAssetsWithOptions:[self allImageVideoFetchOptions]];
}

- (void)setModule:(ASHomeModuleType)type state:(ASModuleScanState)st {
    NSMutableArray *arr = [self.snapshot.moduleStates mutableCopy];
    if (!arr || arr.count != 9) {
        arr = [@[@0,@0,@0,@0,@0,@0,@0,@0,@0] mutableCopy];
    }
    arr[type] = @(st);
    self.snapshot.moduleStates = arr;
}

- (void)setAllModulesState:(ASModuleScanState)st {
    self.snapshot.moduleStates = @[
        @(st),@(st),@(st),@(st),@(st),@(st),@(st),@(st),@(st)
    ];
}

- (instancetype)init {
    if (self=[super init]) {
        _workQ = dispatch_queue_create("as.photo.scan.q", DISPATCH_QUEUE_SERIAL);
        _imageManager = [PHCachingImageManager new];

        _pendingInsertedMap = [NSMutableDictionary dictionary];
        _pendingRemovedIDs = [NSMutableSet set];

        _snapshot = [ASScanSnapshot new];
        _duplicateGroups = @[];
        _similarGroups = @[];
        _screenshots = @[];
        _screenRecordings = @[];
        _bigVideos = @[];
        _blurryPhotos = @[];
        _otherPhotos = @[];

        _indexImage = [NSMutableDictionary dictionary];
        _indexVideo = [NSMutableDictionary dictionary];

        _cache = [ASScanCache new];

        _visionMemo = [[NSCache alloc] init];
        _visionMemo.countLimit = 200;

        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    }
    return self;
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (void)updateBlurryTopKIncremental:(ASAssetModel *)m desiredK:(NSUInteger)desiredK {
    if (!m || m.blurScore < 0.f) return;
    if (desiredK == 0) return;

    if (!self.blurryPhotosM) self.blurryPhotosM = [NSMutableArray array];

    // 如果榜已满且不更糊，直接丢
    if (self.blurryPhotosM.count >= desiredK) {
        ASAssetModel *leastBlurry = self.blurryPhotosM.lastObject; // 升序：last 最不糊
        if (!(m.blurScore < leastBlurry.blurScore)) return;

        [self.blurryPhotosM removeLastObject];
        if (self.blurryBytesRunning >= leastBlurry.fileSizeBytes) self.blurryBytesRunning -= leastBlurry.fileSizeBytes;
        // ⚠️增量最终会 rebuild other，所以这里不需要 add back other
    }

    // 二分插入，保持升序
    NSUInteger lo = 0, hi = self.blurryPhotosM.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) >> 1;
        ASAssetModel *x = self.blurryPhotosM[mid];
        if (m.blurScore < x.blurScore) hi = mid;
        else lo = mid + 1;
    }
    [self.blurryPhotosM insertObject:m atIndex:lo];
    self.blurryBytesRunning += m.fileSizeBytes;

    self.snapshot.blurryCount = self.blurryPhotosM.count;
    self.snapshot.blurryBytes = self.blurryBytesRunning;
}

- (NSUInteger)blurryDesiredKForLibraryQuick {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.predicate = [NSPredicate predicateWithFormat:
        @"(mediaType == %d) AND NOT ((mediaSubtypes & %d) != 0)",
        PHAssetMediaTypeImage,
        PHAssetMediaSubtypePhotoScreenshot
    ];
    opt.includeHiddenAssets = YES;
    opt.includeAssetSourceTypes =
        PHAssetSourceTypeUserLibrary |
        PHAssetSourceTypeCloudShared |
        PHAssetSourceTypeiTunesSynced;

    NSUInteger total = [PHAsset fetchAssetsWithOptions:opt].count;
    NSUInteger k = (NSUInteger)lrintf((float)total * kBlurKeepPercent);
    k = MAX(kBlurKeepMin, k);
    k = MIN(kBlurKeepMax, k);
    return k;
}

#pragma mark - Public

- (void)loadCacheAndCheckIncremental {
    [self loadCacheIfExists];
    [self applyCacheToPublicState];       // 立即让 UI 显示缓存
    [self refreshAllAssetsFetchResult];
    [self checkIncrementalFromDiskAnchor];// 再做增量同步
}

- (void)subscribeProgress:(ASScanProgressBlock)progress {
    self.progressBlock = progress;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) self.progressBlock(self.snapshot);
    });
}

- (void)startFullScanWithProgress:(ASScanProgressBlock)progress
                       completion:(ASScanCompletionBlock)completion
{
    if (progress) self.progressBlock = progress;
    self.completionBlock = completion;
    self.cancelled = NO;

    self.blurryPhotosM = [NSMutableArray array];
    self.otherPhotosM  = [NSMutableArray array];

    self.snapshot = [ASScanSnapshot new];
    self.snapshot.state = ASScanStateScanning;
    [self setAllModulesState:ASModuleScanStateScanning];
    [self emitProgress];

    dispatch_async(self.workQ, ^{
        @autoreleasepool {
            NSError *error = nil;
            
            self.blurryImagesSeen = 0;
            self.blurryBytesRunning = 0;
            [self.blurryPhotosM removeAllObjects];

            [ASBlurMemo() removeAllObjects];
            gBlurDebugPrinted = 0;

            self.otherCandidateMap = [NSMutableDictionary dictionary];
            self.otherCandidateBytes = 0;

            self.comparableImagesM = [NSMutableArray array];
            self.comparableVideosM = [NSMutableArray array];

            self.dupGroupsM = [NSMutableArray array];
            self.simGroupsM = [NSMutableArray array];
            self.screenshotsM = [NSMutableArray array];
            self.screenRecordingsM = [NSMutableArray array];
            self.bigVideosM = [NSMutableArray array];

            [self.indexImage removeAllObjects];
            [self.indexVideo removeAllObjects];

            self.currentDay = nil;

            PHFetchResult<PHAsset *> *result =
                [PHAsset fetchAssetsWithOptions:[self allImageVideoFetchOptions]];

            NSDate *maxAnchor = [NSDate dateWithTimeIntervalSince1970:0];

            for (PHAsset *asset in result) {
                @autoreleasepool {
                    if (self.cancelled) {
                        error = [NSError errorWithDomain:@"ASPhotoScan"
                                                    code:-999
                                                userInfo:@{NSLocalizedDescriptionKey:@"cancelled"}];
                        break;
                    }

                    NSDate *cd = asset.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
                    NSDate *md = asset.modificationDate ?: cd;
                    if ([cd compare:maxAnchor] == NSOrderedDescending) maxAnchor = cd;
                    if ([md compare:maxAnchor] == NSOrderedDescending) maxAnchor = md;

                    NSDate *day = ASDayStart(cd);
                    if (!self.currentDay || ![day isEqualToDate:self.currentDay]) {
                        self.currentDay = day;
                        [self.indexImage removeAllObjects];
                        [self.indexVideo removeAllObjects];
                    }

                    ASAssetModel *model = [self buildModelForAsset:asset computeCompareBits:YES error:&error];
                    if (!model) { if (error) break; else continue; }

                    self.snapshot.scannedCount += 1;
                    self.snapshot.scannedBytes += model.fileSizeBytes;

                    if (ASIsScreenshot(asset)) {
                        [self.screenshotsM addObject:model];
                        self.snapshot.screenshotCount += 1;
                        self.snapshot.screenshotBytes += model.fileSizeBytes;
                        [self emitProgressMaybe];
                        continue;
                    }
                    
                    // ✅ Other：先把普通照片当作候选，扫描中就能实时看到列表/数量/大小
                    if (asset.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(asset)) {
                        [self setModule:ASHomeModuleTypeOtherPhotos state:ASModuleScanStateScanning];
                        [self otherCandidateAddIfNeeded:model asset:asset];
                        [self emitProgressMaybe];
                    }

                    // Blurry：允许和 similar/duplicate 重叠，但不包含 screenshot
                    if (asset.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(asset)) {
                        float score = [self blurScoreForAsset:asset];
                        if (score >= 0.f) {
                            model.blurScore = score;
                            [self updateBlurryTopKRealtime:model asset:asset]; // 实时 TopK
                            [self emitProgressMaybe];
                        }
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
                    }

                    if (!ASAllowedForCompare(asset)) {
                        [self emitProgressMaybe];
                        continue;
                    }

                    [self setModule:ASHomeModuleTypeSimilarImage state:ASModuleScanStateAnalyzing];
                    [self setModule:ASHomeModuleTypeSimilarVideo state:ASModuleScanStateAnalyzing];
                    [self setModule:ASHomeModuleTypeDuplicateImage state:ASModuleScanStateAnalyzing];
                    [self setModule:ASHomeModuleTypeDuplicateVideo state:ASModuleScanStateAnalyzing];

                    BOOL grouped = [self matchAndGroup:model asset:asset];
                    if (grouped && asset.mediaType == PHAssetMediaTypeImage) {
                        [self otherCandidateRemoveIfExistsLocalId:model.localId];
                    }

                    if (asset.mediaType == PHAssetMediaTypeImage) {
                        [self.comparableImagesM addObject:model];
                    } else if (asset.mediaType == PHAssetMediaTypeVideo) {
                        [self.comparableVideosM addObject:model];
                    }

                    [self recomputeCleanableStatsFast];
                    [self emitProgressMaybe];
                }
            }

            if (!error && !self.cancelled) {
                self.snapshot.state = ASScanStateFinished;
                self.snapshot.duplicateGroupCount = self.dupGroupsM.count;
                self.snapshot.similarGroupCount = self.simGroupsM.count;
                self.snapshot.lastUpdated = [NSDate date];

                [self setModule:ASHomeModuleTypeOtherPhotos state:ASModuleScanStateScanning];
                self.otherPhotosM = [[self buildOtherPhotosFromAllAssetsFetchResult:result] mutableCopy];

                self.cache.snapshot = self.snapshot;
                self.cache.duplicateGroups = [self.dupGroupsM copy];
                self.cache.similarGroups = [self.simGroupsM copy];
                self.cache.screenshots = [self.screenshotsM copy];
                self.cache.screenRecordings = [self.screenRecordingsM copy];
                self.cache.bigVideos = [self.bigVideosM copy];

                self.cache.anchorDate = maxAnchor;

                self.cache.comparableImages = [self.comparableImagesM copy];
                self.cache.comparableVideos = [self.comparableVideosM copy];

                self.cache.blurryPhotos = [self.blurryPhotosM copy];
                self.cache.otherPhotos  = [self.otherPhotosM copy];

                if ([self needRefreshHomeStat:self.cache.homeStatRefreshDate]) {
                    self.cache.homeStatRefreshDate = [NSDate date];
                }

                [self saveCache];
                [self setModule:ASHomeModuleTypeBlurryPhotos state:ASModuleScanStateFinished];
                [self setModule:ASHomeModuleTypeOtherPhotos  state:ASModuleScanStateFinished];
                [self setAllModulesState:ASModuleScanStateFinished];

                [self applyCacheToPublicStateWithCompletion:^{
                    self.blurryPhotos = self.cache.blurryPhotos ?: @[];
                    self.otherPhotos  = self.cache.otherPhotos ?: @[];
                    [self emitProgress];
                }];

                [self refreshAllAssetsFetchResult];

                if (self.pendingIncremental) {
                    self.pendingIncremental = NO;
                    [self scheduleIncrementalCheck];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.completionBlock) self.completionBlock(self.snapshot, error);
            });
        }
    });
}

- (void)otherCandidateAddIfNeeded:(ASAssetModel *)model asset:(PHAsset *)asset {
    if (asset.mediaType != PHAssetMediaTypeImage) return;
    if (ASIsScreenshot(asset)) return;

    NSString *lid = model.localId ?: @"";
    if (!lid.length) return;

    if (!self.otherCandidateMap) self.otherCandidateMap = [NSMutableDictionary dictionary];
    if (self.otherCandidateMap[lid]) return;

    self.otherCandidateMap[lid] = model;
    self.otherCandidateBytes += model.fileSizeBytes;

    if (!self.otherPhotosM) self.otherPhotosM = [NSMutableArray array];
    [self.otherPhotosM addObject:model];

    self.snapshot.otherCount = self.otherPhotosM.count;
    self.snapshot.otherBytes = self.otherCandidateBytes;
}

- (void)otherCandidateRemoveIfExistsLocalId:(NSString *)lid {
    if (!lid.length) return;
    ASAssetModel *old = self.otherCandidateMap[lid];
    if (!old) return;

    [self.otherCandidateMap removeObjectForKey:lid];
    if (self.otherCandidateBytes >= old.fileSizeBytes) self.otherCandidateBytes -= old.fileSizeBytes;
    else self.otherCandidateBytes = 0;

    [self.otherPhotosM removeObject:old];

    self.snapshot.otherCount = self.otherPhotosM.count;
    self.snapshot.otherBytes = self.otherCandidateBytes;
}

- (void)cancel {
    self.cancelled = YES;
}

- (BOOL)isCacheValid {
    BOOL ok = self.didLoadCacheFromDisk && (self.cache.snapshot.state == ASScanStateFinished);
    NSLog(@"[缓存] file=%@ didLoad=%@ state=%ld anchor=%@ lastUpdated=%@",
          [self cacheFileExists] ? @"YES" : @"NO",
          self.didLoadCacheFromDisk ? @"YES" : @"NO",
          (long)self.cache.snapshot.state,
          self.cache.anchorDate,
          self.cache.snapshot.lastUpdated);
    return ok;
}

#pragma mark - Purge deleted assets

- (void)purgeDeletedAssetsAndRecalculate {
    dispatch_async(self.workQ, ^{
        // 仅在缓存 finished 时做 purge
        if (self.cache.snapshot.state != ASScanStateFinished) return;

        // 收集 cache 里出现过的所有 localId
        NSMutableSet<NSString *> *cachedIds = [NSMutableSet set];

        for (ASAssetGroup *g in self.cache.duplicateGroups)
            for (ASAssetModel *m in g.assets) if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetGroup *g in self.cache.similarGroups)
            for (ASAssetModel *m in g.assets) if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.screenshots) if (m.localId.length) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.screenRecordings) if (m.localId.length) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.bigVideos) if (m.localId.length) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.blurryPhotos) if (m.localId.length) [cachedIds addObject:m.localId];
        for (ASAssetModel *m in self.cache.otherPhotos) if (m.localId.length) [cachedIds addObject:m.localId];

        if (cachedIds.count == 0) return;

        // 拉取现存 assets
        PHFetchResult<PHAsset *> *exist = [PHAsset fetchAssetsWithLocalIdentifiers:cachedIds.allObjects options:nil];
        NSMutableSet<NSString *> *existIds = [NSMutableSet setWithCapacity:exist.count];
        for (PHAsset *a in exist) if (a.localIdentifier.length) [existIds addObject:a.localIdentifier];

        // deleted = cached - exist
        NSMutableSet<NSString *> *deleted = [cachedIds mutableCopy];
        [deleted minusSet:existIds];

        if (deleted.count == 0) return;

        // 从 cache 可变容器加载并删除
        self.dupGroupsM = [self deepMutableGroups:self.cache.duplicateGroups];
        self.simGroupsM = [self deepMutableGroups:self.cache.similarGroups];
        self.screenshotsM = [self.cache.screenshots mutableCopy] ?: [NSMutableArray array];
        self.screenRecordingsM = [self.cache.screenRecordings mutableCopy] ?: [NSMutableArray array];
        self.bigVideosM = [self.cache.bigVideos mutableCopy] ?: [NSMutableArray array];
        self.comparableImagesM = [self.cache.comparableImages mutableCopy] ?: [NSMutableArray array];
        self.comparableVideosM = [self.cache.comparableVideos mutableCopy] ?: [NSMutableArray array];
        self.blurryPhotosM = [self.cache.blurryPhotos mutableCopy] ?: [NSMutableArray array];
        self.otherPhotosM  = [self.cache.otherPhotos mutableCopy] ?: [NSMutableArray array];

        [self removeModelsByIds:deleted];

        // rebuild index + snapshot
        [self rebuildIndexFromComparablePools];
        [self recomputeSnapshotFromCurrentContainers];

        // 写回 cache
        self.cache.snapshot = self.snapshot;
        self.cache.duplicateGroups = [self.dupGroupsM copy];
        self.cache.similarGroups   = [self.simGroupsM copy];
        self.cache.screenshots     = [self.screenshotsM copy];
        self.cache.screenRecordings = [self.screenRecordingsM copy];
        self.cache.bigVideos       = [self.bigVideosM copy];
        self.cache.comparableImages = [self.comparableImagesM copy];
        self.cache.comparableVideos = [self.comparableVideosM copy];
        self.cache.blurryPhotos    = [self.blurryPhotosM copy];
        self.cache.otherPhotos     = [self.otherPhotosM copy];

        [self saveCache];

        // 发布到公开状态
        [self applyCacheToPublicStateWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                self.snapshot.state = ASScanStateFinished;
                [self emitProgress];
            });
        }];
    });
}

#pragma mark - Other photos

static inline BOOL ASModelIsScreenshot(ASAssetModel *m) {
    return (m.mediaType == PHAssetMediaTypeImage) &&
           ((m.subtypes & PHAssetMediaSubtypePhotoScreenshot) != 0);
}

- (void)otherCandidateAddModelIfNeeded:(ASAssetModel *)model {
    if (!model) return;
    if (model.mediaType != PHAssetMediaTypeImage) return;
    if (model.subtypes & PHAssetMediaSubtypePhotoScreenshot) return;

    NSString *lid = model.localId ?: @"";
    if (!lid.length) return;

    if (!self.otherCandidateMap) self.otherCandidateMap = [NSMutableDictionary dictionary];
    if (self.otherCandidateMap[lid]) return;

    self.otherCandidateMap[lid] = model;
    self.otherCandidateBytes += model.fileSizeBytes;

    if (!self.otherPhotosM) self.otherPhotosM = [NSMutableArray array];
    [self.otherPhotosM addObject:model];

    self.snapshot.otherCount = self.otherPhotosM.count;
    self.snapshot.otherBytes = self.otherCandidateBytes;
}

- (NSArray<ASAssetModel *> *)buildOtherPhotosFromAllAssetsFetchResult:(PHFetchResult<PHAsset*> *)result {
    NSMutableSet<NSString*> *exclude = [NSMutableSet set];

    for (ASAssetGroup *g in self.dupGroupsM)
        for (ASAssetModel *m in g.assets) if(m.localId.length) [exclude addObject:m.localId];
    for (ASAssetGroup *g in self.simGroupsM)
        for (ASAssetModel *m in g.assets) if(m.localId.length) [exclude addObject:m.localId];
    for (ASAssetModel *m in self.screenshotsM) if(m.localId.length) [exclude addObject:m.localId];
    for (ASAssetModel *m in self.blurryPhotosM) if(m.localId.length) [exclude addObject:m.localId];

    NSMutableArray<ASAssetModel*> *out = [NSMutableArray array];

    for (PHAsset *a in result) {
        if (a.mediaType != PHAssetMediaTypeImage) continue;
        if (ASIsScreenshot(a)) continue;
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        if ([exclude containsObject:lid]) continue;

        NSError *err = nil;
        ASAssetModel *m = [self buildModelForAsset:a computeCompareBits:NO error:&err];
        if (!m) continue;

        [out addObject:m];
    }
    return out;
}

// --- Blur config ---

- (void)updateBlurryTopKRealtime:(ASAssetModel *)m asset:(PHAsset *)asset {
    if (m.blurScore < 0.f) return;

    self.blurryImagesSeen += 1;
    if (self.blurryImagesSeen < kBlurWarmup) return;

    NSUInteger desiredK = (NSUInteger)lrintf((float)self.blurryImagesSeen * kBlurKeepPercent);
    desiredK = MAX(kBlurKeepMin, desiredK);
    desiredK = MIN(kBlurKeepMax, desiredK);

    if (!self.blurryPhotosM) self.blurryPhotosM = [NSMutableArray array];

    // 榜满：只有更糊才进（score 越小越糊）
    if (self.blurryPhotosM.count >= desiredK) {
        ASAssetModel *leastBlurry = self.blurryPhotosM.lastObject; // 升序：last 最不糊
        if (!(m.blurScore < leastBlurry.blurScore)) return;

        // 踢出一个
        [self.blurryPhotosM removeLastObject];
        if (self.blurryBytesRunning >= leastBlurry.fileSizeBytes) self.blurryBytesRunning -= leastBlurry.fileSizeBytes;
        else self.blurryBytesRunning = 0;

        // ✅ 踢出的那张，加回 other（必须用 model-only，不能用当前 asset）
        [self otherCandidateAddModelIfNeeded:leastBlurry];
    }

    // 二分插入，保持升序（小=更糊）
    NSUInteger lo = 0, hi = self.blurryPhotosM.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) >> 1;
        ASAssetModel *x = self.blurryPhotosM[mid];
        if (m.blurScore < x.blurScore) hi = mid;
        else lo = mid + 1;
    }
    [self.blurryPhotosM insertObject:m atIndex:lo];
    self.blurryBytesRunning += m.fileSizeBytes;

    // 进了 blurry，从 other 移除
    [self otherCandidateRemoveIfExistsLocalId:m.localId];

    self.snapshot.blurryCount = self.blurryPhotosM.count;
    self.snapshot.blurryBytes = self.blurryBytesRunning;
}

static const float kASBlur_MinMeanLuma   = 35.f;
static const float kASBlur_MaxVarLap     = 140.f;
static const float kASBlur_MinTenengrad  = 14.0f;
static const float kASBlur_ROIFrac       = 0.60f;

- (float)blurScoreForAsset:(PHAsset *)asset {
    if (asset.mediaType != PHAssetMediaTypeImage) return -1.f;
    if (ASIsScreenshot(asset)) return -1.f;

    UIImage *thumb = [self requestThumbnailSyncForAsset:asset target:CGSizeMake(1024, 1024)];
    if (!thumb.CGImage) return -1.f;

    vImage_Buffer gray = {0};
    if (![self vImageGrayFromCGImage:thumb.CGImage outGray:&gray] || !gray.data) return -1.f;

    vImage_Buffer roi = [self vImageCenterROIFromGray:gray frac:0.70f];
    vImage_Buffer roi8 = [self copyROIToContiguousPlanar8:roi];

    // 过滤极暗/极平（不然夜景/纯色容易被当模糊）
    uint8_t *p = (uint8_t *)roi8.data;
    uint64_t n = (uint64_t)roi8.width * (uint64_t)roi8.height;
    double sum=0, sum2=0;
    for (uint64_t i=0;i<n;i++){ double v=p[i]; sum+=v; sum2+=v*v; }
    double mean = sum / (double)MAX(n,1);
    double var  = sum2/(double)MAX(n,1) - mean*mean;
    if (var < 0) var = 0;
    double std  = sqrt(var);

    float score = -1.f;
    if (mean > 20.0 && std > 8.0) { // ✅ 可微调，但不会再“一刀切”
        score = [self tenengradFloatOnROI8:roi8]; // 越小越模糊
    }

    free(roi8.data);
    free(gray.data);
    return score;
}

#pragma mark - vImage helpers

- (vImage_Buffer)copyROIToContiguousPlanar8:(vImage_Buffer)roi {
    vImage_Buffer out = {0};
    out.width = roi.width;
    out.height = roi.height;
    out.rowBytes = roi.width; // 连续
    out.data = malloc(out.rowBytes * out.height);
    if (!out.data) return (vImage_Buffer){0};

    for (uint32_t y = 0; y < out.height; y++) {
        memcpy((uint8_t *)out.data + y*out.rowBytes,
               (uint8_t *)roi.data + y*roi.rowBytes,
               out.width);
    }
    return out;
}


- (float)tenengradFloatOnROI8:(vImage_Buffer)roi8 {
    // roi8: Planar8, rowBytes == width（连续）
    const uint32_t w = (uint32_t)roi8.width, h = (uint32_t)roi8.height;
    if (w < 5 || h < 5) return 0.f;

    // 1) Planar8 -> PlanarF
    vImage_Buffer f = {0};
    f.width = w; f.height = h; f.rowBytes = w * sizeof(float);
    f.data = malloc(f.rowBytes * h);
    if (!f.data) return 0.f;

    // 归一化到 0~1（更稳定）
    vImageConvert_Planar8toPlanarF(&roi8, &f, 1.0f/255.0f, 0.0f, kvImageNoFlags);

    // 2) Sobel on PlanarF
    static const float kx[9] = {
        -1, 0, 1,
        -2, 0, 2,
        -1, 0, 1
    };
    static const float ky[9] = {
        -1, -2, -1,
         0,  0,  0,
         1,  2,  1
    };

    vImage_Buffer gx = {0}, gy = {0};
    gx.width = gy.width = w;
    gx.height = gy.height = h;
    gx.rowBytes = gy.rowBytes = w * sizeof(float);
    gx.data = malloc(gx.rowBytes * h);
    gy.data = malloc(gy.rowBytes * h);

    if (!gx.data || !gy.data) {
        if (gx.data) free(gx.data);
        if (gy.data) free(gy.data);
        free(f.data);
        return 0.f;
    }

    vImageConvolve_PlanarF(&f, &gx, NULL, 0, 0, kx, 3, 3, 0.0f, kvImageEdgeExtend);
    vImageConvolve_PlanarF(&f, &gy, NULL, 0, 0, ky, 3, 3, 0.0f, kvImageEdgeExtend);

    // 3) Tenengrad = sqrt(mean(gx^2 + gy^2))
    float *px = (float *)gx.data;
    float *py = (float *)gy.data;
    uint64_t n = (uint64_t)w * (uint64_t)h;

    double sum = 0.0;
    for (uint64_t i=0; i<n; i++) {
        double x = px[i], y = py[i];
        sum += (x*x + y*y);
    }
    double mean = sum / (double)MAX(n, 1);

    free(f.data);
    free(gx.data);
    free(gy.data);

    return (float)sqrt(mean);
}

- (BOOL)vImageGrayFromCGImage:(CGImageRef)cg outGray:(vImage_Buffer *)outGray {
    if (!cg || !outGray) return NO;

    const size_t w = CGImageGetWidth(cg);
    const size_t h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return NO;

    vImage_Buffer rgba = {0};
    rgba.width = w;
    rgba.height = h;
    rgba.rowBytes = w * 4;
    rgba.data = malloc(rgba.rowBytes * h);
    if (!rgba.data) return NO;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        rgba.data, w, h, 8, rgba.rowBytes, cs,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(cs);
    if (!ctx) { free(rgba.data); return NO; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    outGray->width = w;
    outGray->height = h;
    outGray->rowBytes = w;
    outGray->data = malloc(outGray->rowBytes * h);
    if (!outGray->data) { free(rgba.data); return NO; }

    vImage_Buffer argb = {0};
    argb.width = w;
    argb.height = h;
    argb.rowBytes = w * 4;
    argb.data = malloc(argb.rowBytes * h);
    if (!argb.data) { free(rgba.data); free(outGray->data); outGray->data=NULL; return NO; }

    const uint8_t permuteMap[4] = {3, 0, 1, 2};
    vImage_Error e = vImagePermuteChannels_ARGB8888(&rgba, &argb, permuteMap, kvImageNoFlags);
    free(rgba.data);
    if (e != kvImageNoError) { free(argb.data); free(outGray->data); outGray->data=NULL; return NO; }

    const int16_t mtx[4] = {0, 77, 150, 29};  // *256
    const int32_t divisor = 256;
    e = vImageMatrixMultiply_ARGB8888ToPlanar8(&argb, outGray, mtx, divisor, NULL, 0, kvImageNoFlags);

    free(argb.data);

    if (e != kvImageNoError) {
        free(outGray->data);
        outGray->data = NULL;
        return NO;
    }
    return YES;
}

- (float)edgeDensityOnGrayROI_Planar8:(vImage_Buffer)roi edgeThreshold:(int)thr {
    const uint32_t w = (uint32_t)roi.width;
    const uint32_t h = (uint32_t)roi.height;
    if (w < 5 || h < 5) return 0.f;

    const int16_t kx[9] = {
        -1, 0, 1,
        -2, 0, 2,
        -1, 0, 1
    };
    const int16_t ky[9] = {
        -1, -2, -1,
         0,  0,  0,
         1,  2,  1
    };

    vImage_Buffer gx8 = {0}, gy8 = {0};
    gx8.width = gy8.width = w;
    gx8.height = gy8.height = h;
    gx8.rowBytes = gy8.rowBytes = w;
    gx8.data = malloc((size_t)w * (size_t)h);
    gy8.data = malloc((size_t)w * (size_t)h);
    if (!gx8.data || !gy8.data) {
        if (gx8.data) free(gx8.data);
        if (gy8.data) free(gy8.data);
        return 0.f;
    }

    // 关键点：Planar8 卷积需要 bias，把结果平移到 0~255
    // 我们用 bias=128，然后用 (p-128) 当 signed 值
    vImage_Error ex = vImageConvolve_Planar8(&roi, &gx8, NULL, 0, 0, kx, 3, 3, 1, 128, kvImageEdgeExtend);
    vImage_Error ey = vImageConvolve_Planar8(&roi, &gy8, NULL, 0, 0, ky, 3, 3, 1, 128, kvImageEdgeExtend);

    if (ex != kvImageNoError || ey != kvImageNoError) {
        free(gx8.data); free(gy8.data);
        return 0.f;
    }

    uint64_t strong = 0;
    uint64_t n = (uint64_t)w * (uint64_t)h;

    uint8_t *px = (uint8_t *)gx8.data;
    uint8_t *py = (uint8_t *)gy8.data;

    for (uint64_t i = 0; i < n; i++) {
        int gx = (int)px[i] - 128;
        int gy = (int)py[i] - 128;
        int mag = abs(gx) + abs(gy);   // 近似梯度幅值
        if (mag > thr) strong++;
    }

    free(gx8.data); free(gy8.data);
    return (float)strong / (float)MAX(n, 1);
}

- (vImage_Buffer)vImageCenterROIFromGray:(vImage_Buffer)gray frac:(float)frac {
    frac = fmaxf(0.1f, fminf(frac, 1.0f));
    uint32_t rw = (uint32_t)lrintf((float)gray.width * frac);
    uint32_t rh = (uint32_t)lrintf((float)gray.height * frac);
    rw = MAX(16, rw); rh = MAX(16, rh);

    uint32_t x0 = (uint32_t)((gray.width  - rw) / 2);
    uint32_t y0 = (uint32_t)((gray.height - rh) / 2);

    vImage_Buffer roi = {0};
    roi.width = rw;
    roi.height = rh;
    roi.rowBytes = gray.rowBytes;
    roi.data = (uint8_t *)gray.data + y0 * gray.rowBytes + x0;
    return roi;
}

- (float)varOfLaplacianOnGrayROI:(vImage_Buffer)roi {
    const int16_t kernel[9] = {
         0,  1, 0,
         1, -4, 1,
         0,  1, 0
    };

    vImage_Buffer lap8 = {0};
    lap8.width = roi.width;
    lap8.height = roi.height;
    lap8.rowBytes = roi.width;
    lap8.data = malloc(lap8.rowBytes * lap8.height);
    if (!lap8.data) return FLT_MAX;

    vImage_Error e = vImageConvolve_Planar8(&roi, &lap8, NULL, 0, 0,
                                           kernel, 3, 3,
                                           1, 128, kvImageEdgeExtend);
    if (e != kvImageNoError) { free(lap8.data); return FLT_MAX; }

    uint8_t *p = (uint8_t *)lap8.data;
    uint64_t n = (uint64_t)lap8.width * (uint64_t)lap8.height;

    double sum = 0.0, sum2 = 0.0;
    for (uint64_t i=0; i<n; i++) {
        double v = (double)((int)p[i] - 128);
        sum += v;
        sum2 += v*v;
    }
    free(lap8.data);

    double mean = sum / (double)n;
    double var = (sum2 / (double)n) - mean*mean;
    if (var < 0) var = 0;
    return (float)var;
}

- (float)tenengradOnGrayROI:(vImage_Buffer)roi {
    const int16_t kx[9] = {
        -1, 0, 1,
        -2, 0, 2,
        -1, 0, 1
    };
    const int16_t ky[9] = {
        -1, -2, -1,
         0,  0,  0,
         1,  2,  1
    };

    vImage_Buffer gx8 = {0}, gy8 = {0};
    gx8.width = gy8.width = roi.width;
    gx8.height = gy8.height = roi.height;
    gx8.rowBytes = gy8.rowBytes = roi.width;
    gx8.data = malloc(gx8.rowBytes * gx8.height);
    gy8.data = malloc(gy8.rowBytes * gy8.height);
    if (!gx8.data || !gy8.data) {
        if (gx8.data) free(gx8.data);
        if (gy8.data) free(gy8.data);
        return FLT_MAX;
    }

    vImage_Error ex = vImageConvolve_Planar8(&roi, &gx8, NULL, 0, 0, kx, 3, 3, 1, 128, kvImageEdgeExtend);
    vImage_Error ey = vImageConvolve_Planar8(&roi, &gy8, NULL, 0, 0, ky, 3, 3, 1, 128, kvImageEdgeExtend);
    if (ex != kvImageNoError || ey != kvImageNoError) {
        free(gx8.data); free(gy8.data);
        return FLT_MAX;
    }

    uint8_t *px = (uint8_t *)gx8.data;
    uint8_t *py = (uint8_t *)gy8.data;
    uint64_t n = (uint64_t)roi.width * (uint64_t)roi.height;

    double sum = 0.0;
    for (uint64_t i=0; i<n; i++) {
        double x = (double)((int)px[i] - 128);
        double y = (double)((int)py[i] - 128);
        sum += (x*x + y*y);
    }

    free(gx8.data);
    free(gy8.data);
    double mean = sum / (double)n;
    return (float)sqrt(mean);
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
#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    if (self.snapshot.state == ASScanStateScanning) {
        self.pendingIncremental = YES;
        return;
    }

    PHFetchResult *fr = self.allAssetsFetchResult;
    PHFetchResultChangeDetails *changes = fr ? [changeInstance changeDetailsForFetchResult:fr] : nil;
    if (!changes) { [self scheduleIncrementalCheck]; return; }

    self.allAssetsFetchResult = changes.fetchResultAfterChanges;

    if (changes.hasIncrementalChanges) {
        NSArray<PHAsset*> *insertedRaw = changes.insertedObjects ?: @[];
        NSArray<PHAsset*> *changedRaw  = changes.changedObjects  ?: @[];
        NSArray<PHAsset*> *removedRaw  = changes.removedObjects  ?: @[];

        NSMutableArray<PHAsset*> *upserts = [NSMutableArray arrayWithArray:insertedRaw];
        [upserts addObjectsFromArray:changedRaw];

        if (upserts.count == 0 && removedRaw.count == 0) return;

        [self scheduleIncrementalRebuildWithInserted:upserts removed:removedRaw];
    } else {
        [self scheduleIncrementalCheck];
    }
}

- (void)scheduleIncrementalRebuildWithInserted:(NSArray<PHAsset *> *)inserted
                                      removed:(NSArray<PHAsset *> *)removed
{
    // 全量扫描中：只标记，等全量结束后再触发一次（你已有 pendingIncremental 逻辑）
    if (self.snapshot.state == ASScanStateScanning) {
        self.pendingIncremental = YES;
        return;
    }

    // 合并：inserted / removed 先汇总起来
    for (PHAsset *a in inserted) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        // 如果同一个 id 同时在 removed 里，优先以 inserted 为准（新增/恢复）
        [self.pendingRemovedIDs removeObject:lid];
        self.pendingInsertedMap[lid] = a;
    }

    for (PHAsset *a in removed) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        // 如果刚插入过又删掉，移出 inserted，并记为 removed
        [self.pendingInsertedMap removeObjectForKey:lid];
        [self.pendingRemovedIDs addObject:lid];
    }

    // debounce：取消上一次延迟任务，重新计时
    if (self.incrementalDebounceBlock) {
        dispatch_block_cancel(self.incrementalDebounceBlock);
        self.incrementalDebounceBlock = nil;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSArray<PHAsset *> *finalInserted = self.pendingInsertedMap.allValues ?: @[];
        NSArray<NSString *> *finalRemovedIDs = self.pendingRemovedIDs.allObjects ?: @[];

        [self.pendingInsertedMap removeAllObjects];
        [self.pendingRemovedIDs removeAllObjects];

        if (self.cache.snapshot.state != ASScanStateFinished) return;

        [self incrementalRebuildWithInserted:finalInserted removedIDs:finalRemovedIDs];
    });

    // 保存起来，后续才能 cancel
    self.incrementalDebounceBlock = block;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   self.workQ,
                   block);
}

- (void)publishSnapshotStateOnMain:(ASScanState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.snapshot.state = state;
        if (self.progressBlock) self.progressBlock(self.snapshot);
    });
}

- (void)incrementalRebuildWithInserted:(NSArray<PHAsset*> *)inserted
                            removedIDs:(NSArray<NSString*> *)removedIDs
{
    NSDate *newAnchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];

    // 1) 从缓存态加载 mutable 容器
    self.comparableImagesM = [self.cache.comparableImages mutableCopy] ?: [NSMutableArray array];
    self.comparableVideosM = [self.cache.comparableVideos mutableCopy] ?: [NSMutableArray array];

    self.dupGroupsM = [self deepMutableGroups:self.cache.duplicateGroups];
    self.simGroupsM = [self deepMutableGroups:self.cache.similarGroups];
    self.screenshotsM = [self.cache.screenshots mutableCopy] ?: [NSMutableArray array];
    self.screenRecordingsM = [self.cache.screenRecordings mutableCopy] ?: [NSMutableArray array];
    self.bigVideosM = [self.cache.bigVideos mutableCopy] ?: [NSMutableArray array];

    self.blurryPhotosM = [self.cache.blurryPhotos mutableCopy] ?: [NSMutableArray array];
    self.otherPhotosM  = [self.cache.otherPhotos  mutableCopy] ?: [NSMutableArray array];

    // ✅ 重建 blurryBytesRunning
    self.blurryBytesRunning = 0;
    for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;

    // 0) UI scanning
    [self publishSnapshotStateOnMain:ASScanStateScanning];

    [self setAllModulesState:ASModuleScanStateIdle];
    [self setModule:ASHomeModuleTypeBlurryPhotos state:ASModuleScanStateScanning];
    [self setModule:ASHomeModuleTypeOtherPhotos  state:ASModuleScanStateScanning];
    [self setModule:ASHomeModuleTypeScreenshots       state:ASModuleScanStateScanning];
    [self setModule:ASHomeModuleTypeScreenRecordings  state:ASModuleScanStateScanning];
    [self setModule:ASHomeModuleTypeBigVideos         state:ASModuleScanStateScanning];

    __block BOOL hasComparable = NO;
    for (PHAsset *a in inserted) {
        if (ASAllowedForCompare(a)) { hasComparable = YES; break; }
    }
    if (hasComparable) {
        [self setModule:ASHomeModuleTypeSimilarImage    state:ASModuleScanStateAnalyzing];
        [self setModule:ASHomeModuleTypeSimilarVideo    state:ASModuleScanStateAnalyzing];
        [self setModule:ASHomeModuleTypeDuplicateImage  state:ASModuleScanStateAnalyzing];
        [self setModule:ASHomeModuleTypeDuplicateVideo  state:ASModuleScanStateAnalyzing];
    }
    [self emitProgress];

    // 2) 删除：剔除 removed IDs
    NSMutableSet<NSString*> *deletedIDs = [NSMutableSet setWithArray:(removedIDs ?: @[])];
    if (deletedIDs.count) {
        [self removeModelsByIds:deletedIDs];

        for (NSString *lid in deletedIDs) {
            if (lid.length) [self.visionMemo removeObjectForKey:lid];
        }
        for (NSString *lid in deletedIDs) {
            if (lid.length) [ASScreenRecordingMemo() removeObjectForKey:lid];
        }

        // ✅ 删除后再校准 blurryBytesRunning
        self.blurryBytesRunning = 0;
        for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;
    }

    // 3) affectedDays：只取 inserted 的创建/修改日期
    NSMutableSet<NSDate*> *affectedDayStarts = [NSMutableSet set];
    for (PHAsset *a in inserted) {
        NSDate *cd = a.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *md = a.modificationDate ?: cd;
        [affectedDayStarts addObject:ASDayStart(cd)];
        [affectedDayStarts addObject:ASDayStart(md)];
    }

    // 4) 重建这些天：先删旧，再重建
    if (affectedDayStarts.count) {
        [self removeModelsByDayStarts:affectedDayStarts];
        // ✅ remove by day 后再校准一次
        self.blurryBytesRunning = 0;
        for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;

        newAnchor = [self rebuildDaysObjC:affectedDayStarts];
    }

    // ✅ rebuild index
    [self rebuildIndexFromComparablePools];

    // 5) snapshot + other 重建（最稳：从全库算 other）
    [self recomputeSnapshotFromCurrentContainers];

    self.otherPhotosM = [[self buildOtherPhotosFromAllAssetsFetchResult:self.allAssetsFetchResult] mutableCopy];

    // 6) 写 cache
    self.cache.snapshot = self.snapshot;
    self.cache.duplicateGroups = [self.dupGroupsM copy];
    self.cache.similarGroups   = [self.simGroupsM copy];
    self.cache.screenshots     = [self.screenshotsM copy];
    self.cache.screenRecordings = [self.screenRecordingsM copy];
    self.cache.bigVideos       = [self.bigVideosM copy];

    self.cache.comparableImages = [self.comparableImagesM copy];
    self.cache.comparableVideos = [self.comparableVideosM copy];

    // ✅ 补全：blurry / other
    self.cache.blurryPhotos = [self.blurryPhotosM copy];
    self.cache.otherPhotos  = [self.otherPhotosM  copy];

    self.cache.anchorDate = newAnchor;

    [self saveCache];
    [self setAllModulesState:ASModuleScanStateFinished];

    [self applyCacheToPublicStateWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.snapshot.state = ASScanStateFinished;
            [self emitProgress];
        });
    }];
}

#pragma mark - FetchOptions (All image+video, include hidden, include sources)

- (PHFetchOptions *)allImageVideoFetchOptions {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]
    ];

    // ✅拿到所有 image + video（不要在 predicate 里排除截屏/录屏）
    opt.predicate = [NSPredicate predicateWithFormat:
                     @"(mediaType == %d) OR (mediaType == %d)",
                     PHAssetMediaTypeImage, PHAssetMediaTypeVideo];

    opt.includeHiddenAssets = YES;
    opt.includeAssetSourceTypes =
        PHAssetSourceTypeUserLibrary |
        PHAssetSourceTypeCloudShared |
        PHAssetSourceTypeiTunesSynced;

    return opt;
}

// 仅用于相似/重复（先在 predicate 里排除截屏；录屏没法纯 predicate 判，只能在循环里判）
- (PHFetchOptions *)comparableFetchOptions {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]
    ];

    // ✅ image + video + 排除 screenshot（与 Swift 逻辑一致）
    opt.predicate = [NSPredicate predicateWithFormat:
        @"((mediaType == %d) OR (mediaType == %d)) AND NOT ((mediaSubtypes & %d) != 0)",
        PHAssetMediaTypeImage, PHAssetMediaTypeVideo,
        PHAssetMediaSubtypePhotoScreenshot
    ];

    opt.includeHiddenAssets = YES;
    opt.includeAssetSourceTypes =
        PHAssetSourceTypeUserLibrary |
        PHAssetSourceTypeCloudShared |
        PHAssetSourceTypeiTunesSynced;

    return opt;
}

- (NSArray<ASAssetGroup *> *)mergedSimilarGroupsForUIFromDup:(NSArray<ASAssetGroup *> *)dup
                                                         sim:(NSArray<ASAssetGroup *> *)sim
{
    if (!dup.count) return sim ?: @[];
    if (!sim.count) return dup ?: @[];
    return [sim arrayByAddingObjectsFromArray:dup];
}


- (void)removeModelsByDayStarts:(NSSet<NSDate*> *)dayStarts {
    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(ASAssetModel *m, NSDictionary *_) {
        NSDate *cd = m.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *d0 = ASDayStart(cd);
        return ![dayStarts containsObject:d0];
    }];

    // groups：保留不在这些天的 + 组内>=2
    NSArray *(^filterGroups)(NSArray<ASAssetGroup*>*) = ^NSArray*(NSArray *groups){
        NSMutableArray *out = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            NSMutableArray *kept = [[g.assets filteredArrayUsingPredicate:keep] mutableCopy];
            if (kept.count >= 2) {
                g.assets = kept;
                [out addObject:g];
            }
        }
        return out;
    };

    self.dupGroupsM = [[filterGroups(self.dupGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];
    self.simGroupsM = [[filterGroups(self.simGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];

    self.screenshotsM = [[self.screenshotsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.screenRecordingsM = [[self.screenRecordingsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.bigVideosM = [[self.bigVideosM filteredArrayUsingPredicate:keep] mutableCopy];
    self.comparableImagesM = [[self.comparableImagesM filteredArrayUsingPredicate:keep] mutableCopy];
    self.comparableVideosM = [[self.comparableVideosM filteredArrayUsingPredicate:keep] mutableCopy];
    self.blurryPhotosM = [[self.blurryPhotosM filteredArrayUsingPredicate:keep] mutableCopy];
    self.otherPhotosM  = [[self.otherPhotosM  filteredArrayUsingPredicate:keep] mutableCopy];
}

- (NSDate *)rebuildDaysObjC:(NSSet<NSDate*> *)dayStarts {
    NSDate *maxA = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];
    NSUInteger desiredK = [self blurryDesiredKForLibraryQuick];

    NSCalendar *cal = [NSCalendar currentCalendar];
    for (NSDate *dayStart in dayStarts) {
        NSDate *dayEnd = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];

        PHFetchOptions *opt = [self allImageVideoFetchOptions];
        opt.predicate = [NSPredicate predicateWithFormat:
            @"((mediaType == %d) OR (mediaType == %d)) AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaTypeImage, PHAssetMediaTypeVideo, dayStart, dayEnd
        ];

        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithOptions:opt];

        [self.indexImage removeAllObjects];
        [self.indexVideo removeAllObjects];

        for (PHAsset *asset in fr) {
            NSDate *cd = asset.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
            NSDate *md = asset.modificationDate ?: cd;
            if ([cd compare:maxA] == NSOrderedDescending) maxA = cd;
            if ([md compare:maxA] == NSOrderedDescending) maxA = md;

            NSError *err = nil;
            ASAssetModel *m = [self buildModelForAsset:asset computeCompareBits:YES error:&err];
            if (!m) continue;

            if (ASIsScreenshot(asset)) {
                [self.screenshotsM addObject:m];
                continue;
            }

            // ✅ blurry：用 score + 增量TopK
            if (asset.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(asset)) {
                float score = [self blurScoreForAsset:asset];
                if (score >= 0.f) {
                    m.blurScore = score;
                    [self updateBlurryTopKIncremental:m desiredK:desiredK];
                }
            }

            if (ASIsScreenRecording(asset)) {
                [self.screenRecordingsM addObject:m];
                continue;
            }

            if (asset.mediaType == PHAssetMediaTypeVideo && m.fileSizeBytes >= kBigVideoMinBytes) {
                [self.bigVideosM addObject:m];
            }

            if (!ASAllowedForCompare(asset)) continue;

            [self matchAndGroup:m asset:asset];

            if (asset.mediaType == PHAssetMediaTypeImage) {
                if (!self.comparableImagesM) self.comparableImagesM = [NSMutableArray array];
                [self.comparableImagesM addObject:m];
            } else if (asset.mediaType == PHAssetMediaTypeVideo) {
                if (!self.comparableVideosM) self.comparableVideosM = [NSMutableArray array];
                [self.comparableVideosM addObject:m];
            }
        }
    }

    // ✅ 防守：确保不超过 desiredK
    while (self.blurryPhotosM.count > desiredK) {
        ASAssetModel *tail = self.blurryPhotosM.lastObject;
        [self.blurryPhotosM removeLastObject];
        if (self.blurryBytesRunning >= tail.fileSizeBytes) self.blurryBytesRunning -= tail.fileSizeBytes;
        else self.blurryBytesRunning = 0;
    }
    self.snapshot.blurryCount = self.blurryPhotosM.count;
    self.snapshot.blurryBytes = self.blurryBytesRunning;

    return maxA;
}

- (void)scheduleIncrementalCheck {
    if (self.incrementalScheduled) return;
    self.incrementalScheduled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), self.workQ, ^{
        self.incrementalScheduled = NO;
        [self checkIncrementalFromDiskAnchor];
    });
}

#pragma mark - Incremental

- (void)checkIncrementalFromDiskAnchor {
    dispatch_async(self.workQ, ^{
        if (self.cache.snapshot.state != ASScanStateFinished) return;

        NSDate *anchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];

        // 1) delta (new/modified)
        PHFetchOptions *opt = [self allImageVideoFetchOptions];
        opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        opt.predicate = [NSPredicate predicateWithFormat:
            @"(((mediaType == %d) OR (mediaType == %d)) AND ((creationDate > %@) OR (modificationDate > %@)))",
            PHAssetMediaTypeImage, PHAssetMediaTypeVideo,
            anchor, anchor
        ];
        PHFetchResult<PHAsset *> *delta = [PHAsset fetchAssetsWithOptions:opt];

        // 2) delete check
        NSMutableSet<NSString *> *deleted = [NSMutableSet set];
        NSMutableSet<NSString *> *cachedIds = [NSMutableSet set];

        for (ASAssetGroup *g in self.cache.duplicateGroups)
            for (ASAssetModel *m in g.assets)
                if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetGroup *g in self.cache.similarGroups)
            for (ASAssetModel *m in g.assets)
                if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.screenshots)
            if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.screenRecordings)
            if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.bigVideos)
            if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.blurryPhotos)
            if (m.localId.length) [cachedIds addObject:m.localId];

        for (ASAssetModel *m in self.cache.otherPhotos)
            if (m.localId.length) [cachedIds addObject:m.localId];

        const NSUInteger kDeleteCheckMax = 5000;
        if (cachedIds.count > 0 && cachedIds.count <= kDeleteCheckMax) {
            PHFetchResult<PHAsset *> *exist =
                [PHAsset fetchAssetsWithLocalIdentifiers:cachedIds.allObjects options:nil];

            NSMutableSet<NSString *> *existIds = [NSMutableSet setWithCapacity:exist.count];
            for (PHAsset *a in exist)
                if (a.localIdentifier.length) [existIds addObject:a.localIdentifier];

            [deleted unionSet:cachedIds];
            [deleted minusSet:existIds];
        }

        // ✅ 3) no changes -> 直接退出，不要把 state 改成 Scanning
        if (delta.count == 0 && deleted.count == 0) {
            // 保持 finished；你如果希望 UI 也“确认一下”，可以回调一次 progress（可选）
            dispatch_async(dispatch_get_main_queue(), ^{
                self.snapshot.state = ASScanStateFinished;
                if (self.progressBlock) self.progressBlock(self.snapshot);
            });
            return;
        }

        // ✅ 只有真的有变化，才进入 scanning（避免 HomeVC 误触发全量扫描）
        dispatch_async(dispatch_get_main_queue(), ^{
            self.snapshot.state = ASScanStateScanning;
            if (self.progressBlock) self.progressBlock(self.snapshot);
        });

        // 4) load mutable containers from cache
        NSError *err = nil;

        self.dupGroupsM = [self deepMutableGroups:self.cache.duplicateGroups];
        self.simGroupsM = [self deepMutableGroups:self.cache.similarGroups];
        self.screenshotsM = [self.cache.screenshots mutableCopy] ?: [NSMutableArray array];
        self.screenRecordingsM = [self.cache.screenRecordings mutableCopy] ?: [NSMutableArray array];
        self.bigVideosM = [self.cache.bigVideos mutableCopy] ?: [NSMutableArray array];

        self.comparableImagesM = [self.cache.comparableImages mutableCopy] ?: [NSMutableArray array];
        self.comparableVideosM = [self.cache.comparableVideos mutableCopy] ?: [NSMutableArray array];
        self.blurryPhotosM = [self.cache.blurryPhotos mutableCopy] ?: [NSMutableArray array];
        self.otherPhotosM  = [self.cache.otherPhotos  mutableCopy] ?: [NSMutableArray array];

        // rebuild index from comparable pools
        [self rebuildIndexFromComparablePools];

        // rebuild blurryBytesRunning
        self.blurryBytesRunning = 0;
        for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;

        // 5) delete
        if (deleted.count > 0) {
            [self removeModelsByIds:deleted];

            self.blurryBytesRunning = 0;
            for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;
        }

        // 6) apply delta
        NSDate *newAnchor = anchor;
        NSInteger processed = 0;

        NSUInteger desiredK = [self blurryDesiredKForLibraryQuick];

        for (PHAsset *a in delta) {
            @autoreleasepool {
                NSString *lid = a.localIdentifier ?: @"";
                if (lid.length) {
                    [self removeModelByIdEverywhere:lid]; // 先删旧
                }

                ASAssetModel *m = [self buildModelForAsset:a computeCompareBits:YES error:&err];
                if (!m) continue;

                NSDate *cd = a.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
                NSDate *md = a.modificationDate ?: cd;
                if ([cd compare:newAnchor] == NSOrderedDescending) newAnchor = cd;
                if ([md compare:newAnchor] == NSOrderedDescending) newAnchor = md;

                if (ASIsScreenshot(a)) {
                    [self.screenshotsM addObject:m];
                } else if (ASIsScreenRecording(a)) {
                    [self.screenRecordingsM addObject:m];
                } else {
                    if (a.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(a)) {
                        float score = [self blurScoreForAsset:a];
                        if (score >= 0.f) {
                            m.blurScore = score;
                            [self updateBlurryTopKIncremental:m desiredK:desiredK];
                        }
                    }

                    if (a.mediaType == PHAssetMediaTypeVideo && m.fileSizeBytes >= kBigVideoMinBytes) {
                        [self.bigVideosM addObject:m];
                    }

                    if (ASAllowedForCompare(a)) {
                        [self matchAndGroup:m asset:a];

                        if (a.mediaType == PHAssetMediaTypeImage) {
                            [self.comparableImagesM addObject:m];
                        } else if (a.mediaType == PHAssetMediaTypeVideo) {
                            [self.comparableVideosM addObject:m];
                        }
                    }
                }

                processed++;
                if (processed % 200 == 0) {
                    [self rebuildIndexFromComparablePools];
                    [self recomputeSnapshotFromCurrentContainers];
                    [self applyCacheToPublicStateWithCompletion:^{ [self emitProgress]; }];
                }
            }
        }

        // 防守：确保不超过 desiredK
        while (self.blurryPhotosM.count > desiredK) {
            ASAssetModel *tail = self.blurryPhotosM.lastObject;
            [self.blurryPhotosM removeLastObject];
            if (self.blurryBytesRunning >= tail.fileSizeBytes) self.blurryBytesRunning -= tail.fileSizeBytes;
            else self.blurryBytesRunning = 0;
        }
        self.snapshot.blurryCount = self.blurryPhotosM.count;
        self.snapshot.blurryBytes = self.blurryBytesRunning;

        // 统一 rebuild index
        [self rebuildIndexFromComparablePools];

        // 7) finish: recompute + rebuild other + save + publish
        [self recomputeSnapshotFromCurrentContainers];

        self.otherPhotosM = [[self buildOtherPhotosFromAllAssetsFetchResult:self.allAssetsFetchResult] mutableCopy];

        self.cache.anchorDate = newAnchor;
        self.cache.snapshot = self.snapshot;
        self.cache.duplicateGroups = [self.dupGroupsM copy];
        self.cache.similarGroups = [self.simGroupsM copy];
        self.cache.screenshots = [self.screenshotsM copy];
        self.cache.screenRecordings = [self.screenRecordingsM copy];
        self.cache.bigVideos = [self.bigVideosM copy];

        self.cache.comparableImages = [self.comparableImagesM copy];
        self.cache.comparableVideos = [self.comparableVideosM copy];

        self.cache.blurryPhotos = [self.blurryPhotosM copy];
        self.cache.otherPhotos  = [self.otherPhotosM  copy];

        [self saveCache];

        [self applyCacheToPublicStateWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                self.snapshot.state = ASScanStateFinished;
                [self emitProgress];
            });
        }];
    });
}

- (void)removeFromIndexByLocalId:(NSString *)localId {
    if (!localId.length) return;

    void (^filterIndex)(NSMutableDictionary<NSNumber*, NSMutableArray<ASAssetModel*>*> *) =
    ^(NSMutableDictionary *idx){
        for (NSNumber *k in idx.allKeys) {
            NSMutableArray *pool = idx[k];
            NSIndexSet *rm = [pool indexesOfObjectsPassingTest:^BOOL(ASAssetModel *obj, NSUInteger i, BOOL *stop) {
                return [obj.localId isEqualToString:localId];
            }];
            if (rm.count) [pool removeObjectsAtIndexes:rm];
            if (pool.count == 0) [idx removeObjectForKey:k];
        }
    };

    filterIndex(self.indexImage);
    filterIndex(self.indexVideo);
}

- (void)removeModelByIdEverywhere:(NSString *)localId {
    if (!localId.length) return;
    [self removeModelsByIds:[NSSet setWithObject:localId]];

    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(ASAssetModel *m, NSDictionary *_) {
        return ![m.localId isEqualToString:localId];
    }];

    self.comparableImagesM = [[self.comparableImagesM filteredArrayUsingPredicate:keep] mutableCopy];
    self.comparableVideosM = [[self.comparableVideosM filteredArrayUsingPredicate:keep] mutableCopy];
    [self removeFromIndexByLocalId:localId]; // 把 index 里的旧 model 也移除
}

#pragma mark - Vision memo (light)

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

            CGImageRef cg = thumb.CGImage;
            if (!cg) return nil;

            CGImagePropertyOrientation ori = ASCGImageOrientationFromUIImage(thumb.imageOrientation);
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg
                                                                                orientation:ori
                                                                                    options:@{}];
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
        return dist;
    }
    return FLT_MAX;
}

#pragma mark - Build model (size + phash256 + vision)

- (ASAssetModel *)buildModelForAsset:(PHAsset *)asset
                 computeCompareBits:(BOOL)computeCompareBits
                              error:(NSError **)err {
    ASAssetModel *m = [ASAssetModel new];
    m.localId = asset.localIdentifier ?: @"";
    m.mediaType = asset.mediaType;
    m.subtypes = asset.mediaSubtypes;
    m.creationDate = asset.creationDate;
    m.modificationDate = asset.modificationDate;

    m.fileSizeBytes = [self fetchFileSizeForAsset:asset];

    if (computeCompareBits && ASAllowedForCompare(asset)) {
        UIImage *thumb = nil;

        if (asset.mediaType == PHAssetMediaTypeVideo) {
            Float64 dur = asset.duration;
            Float64 t = (dur >= 3.0) ? 3.0 : 1.0;
            const Float64 eps = 0.05;
            if (dur > eps) t = MIN(t, dur - eps);
            else t = 0;

            thumb = [self requestVideoFrameSyncForAsset:asset seconds:t target:CGSizeMake(128, 128)];
            if (!thumb) {
                thumb = [self requestVideoFrameSyncForAsset:asset seconds:0 target:CGSizeMake(128, 128)];
            }
        } else {
            thumb = [self requestThumbnailSyncForAsset:asset target:CGSizeMake(128, 128)];
        }

        if (thumb) {
            m.phash256Data = [self computeColorPHash256Data:thumb];
            // m.visionPrintData = ...
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
        opt.version = PHImageRequestOptionsVersionCurrent;

        [self.imageManager requestImageForAsset:asset
                                     targetSize:target
                                    contentMode:PHImageContentModeAspectFill
                                        options:opt
                                  resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if ([info[PHImageResultIsDegradedKey] boolValue]) return;
            if (info[PHImageCancelledKey]) return;
            if (info[PHImageErrorKey]) return;
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
            gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.2, 600);
            gen.requestedTimeToleranceAfter  = CMTimeMakeWithSeconds(0.2, 600);
            if (!CGSizeEqualToSize(target, CGSizeZero)) gen.maximumSize = target;

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

static inline void ASDCT1D_64(const float *in, float *out) {
    const float *cosT = ASDCTCosTable();
    for (int k = 0; k < 64; k++) {
        const float *row = &cosT[k*64];
        float sum = 0.f;
        for (int n = 0; n < 64; n++) {
            sum += in[n] * row[n];
        }
        out[k] = sum;
    }
}

// 建一个 DCT setup（64 点 DCT-II），复用
static vDSP_DFT_Setup ASDCTSetup64(void) {
    static vDSP_DFT_Setup setup = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // DCT-II, length=64
        setup = vDSP_DCT_CreateSetup(NULL, 64, vDSP_DCT_II);
    });
    return setup;
}

- (NSData *)computeColorPHash256Data:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg) { uint64_t z[4] = {0,0,0,0}; return [NSData dataWithBytes:z length:32]; }

    const int width = 64, height = 64;
    const int bytesPerRow = width * 4;

    uint8_t pixels[64 * 64 * 4];
    memset(pixels, 0, sizeof(pixels));

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        pixels, width, height, 8, bytesPerRow, cs,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast
    );
    CGColorSpaceRelease(cs);

    if (!ctx) { uint64_t z[4] = {0,0,0,0}; return [NSData dataWithBytes:z length:32]; }

    // Swift 没显式设置插值质量，这里也不要强行 setInterpolationQuality，避免差异
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(ctx);

    // === 1) 图像增强：完全对齐 Swift ===
    // Swift: enhanced = min(max(1.1*(0.299*r+0.587*g+0.114*b) - 10, 0), 255)
    // 然后 pixels RGB 都写成 UInt8(enhanced)
    for (int i = 0; i < width * height; i++) {
        float r = (float)pixels[i*4 + 0];
        float g = (float)pixels[i*4 + 1];
        float b = (float)pixels[i*4 + 2];

        float enhanced = 1.1f * (0.299f*r + 0.587f*g + 0.114f*b) - 10.f;
        if (enhanced < 0.f) enhanced = 0.f;
        if (enhanced > 255.f) enhanced = 255.f;

        // Swift 的 UInt8(enhanced) 是截断（toward zero）
        uint8_t e8 = (uint8_t)enhanced;

        pixels[i*4 + 0] = e8;
        pixels[i*4 + 1] = e8;
        pixels[i*4 + 2] = e8;
    }

    // === 2) 转 Float：对齐 Swift => Float(pixels[i*4]) ===
    float floatPixels[64 * 64];
    for (int i = 0; i < width * height; i++) {
        floatPixels[i] = (float)pixels[i*4 + 0];
    }

    // === 3) 2D DCT-II：先行后列（对齐 Swift vDSP.DCT(.II) 的调用方式）===
    float rowIn[64], rowOut[64];
    for (int row = 0; row < 64; row++) {
        memcpy(rowIn, &floatPixels[row * 64], sizeof(rowIn));
        ASDCT1D_64(rowIn, rowOut);
        memcpy(&floatPixels[row * 64], rowOut, sizeof(rowOut));
    }

    float colIn[64], colOut[64];
    for (int col = 0; col < 64; col++) {
        for (int row = 0; row < 64; row++) colIn[row] = floatPixels[row * 64 + col];
        ASDCT1D_64(colIn, colOut);
        for (int row = 0; row < 64; row++) floatPixels[row * 64 + col] = colOut[row];
    }

    // === 4) 取左上 16x16 ===
    float topLeft[16 * 16];
    int idx = 0;
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            topLeft[idx++] = floatPixels[r * 64 + c];
        }
    }

    // === 5) median：对齐 Swift => topLeft.sorted()[count/2] ===
    float sorted[16 * 16];
    memcpy(sorted, topLeft, sizeof(sorted));
    qsort(sorted, 256, sizeof(float), ASFloatCmp);
    float median = sorted[256 / 2];

    // === 6) pack 256-bit：对齐 Swift 的 bit order ===
    uint64_t hash[4] = {0,0,0,0};
    for (int i = 0; i < 256; i++) {
        if (topLeft[i] > median) {
            int word = i / 64;
            int offset = 63 - (i % 64);
            hash[word] |= (1ULL << (uint64_t)offset);
        }
    }

    return [NSData dataWithBytes:hash length:32];
}


#pragma mark - Vision FeaturePrint (archived data for cache)

- (NSData *)computeVisionPrintDataFromImage:(UIImage *)image {
    if (@available(iOS 13.0, *)) {
        CGImageRef cg = image.CGImage;
        if (!cg) return nil;

        VNGenerateImageFeaturePrintRequest *req = [VNGenerateImageFeaturePrintRequest new];
        CGImagePropertyOrientation ori = ASCGImageOrientationFromUIImage(image.imageOrientation);
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg
                                                                            orientation:ori
                                                                                options:@{}];
        NSError *error = nil;
        [handler performRequests:@[req] error:&error];

        if (error) return nil;

        VNFeaturePrintObservation *obs = (VNFeaturePrintObservation *)req.results.firstObject;
        if (![obs isKindOfClass:[VNFeaturePrintObservation class]]) return nil;

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

        return dist;
    }
    return FLT_MAX;
}

#pragma mark - Grouping

- (BOOL)matchAndGroup:(ASAssetModel *)model asset:(PHAsset *)asset {
    if (!model.phash256Data || model.phash256Data.length < 32) return NO;

    BOOL isImage = (asset.mediaType == PHAssetMediaTypeImage);
    NSMutableDictionary<NSNumber *, NSMutableArray<ASAssetModel *> *> *index = isImage ? self.indexImage : self.indexVideo;

    NSNumber *k = ASBucketKeyForPHash256(model.phash256Data);
    NSMutableArray<ASAssetModel *> *pool = index[k];
    if (!pool) { pool = [NSMutableArray array]; index[k] = pool; }

    ASAssetModel *hit = nil;
    BOOL hitIsDup = NO;

    ASGroupType simType = isImage ? ASGroupTypeSimilarImage : ASGroupTypeSimilarVideo;
    ASGroupType dupType = isImage ? ASGroupTypeDuplicateImage : ASGroupTypeDuplicateVideo;

    for (ASAssetModel *cand in pool) {
        if ([cand.localId isEqualToString:model.localId]) continue;
        if (!cand.phash256Data || cand.phash256Data.length < 32) continue;

        int hd = ASHamming256(model.phash256Data, cand.phash256Data);
        if (hd > kPolicySimilar.phashThreshold) continue;

        float vd = [self visionDistanceBetweenLocalId:model.localId and:cand.localId];
        if (vd == FLT_MAX) continue;
        if (vd > kPolicySimilar.visionThreshold) continue;

        hit = cand;
        hitIsDup = (hd <= kPolicyDuplicate.phashThreshold && vd <= kPolicyDuplicate.visionThreshold);
        break;
    }

    if (!hit) {
        [pool addObject:model];
        return NO; // ✅未命中，不在任何组
    }

    // ✅相似组
    if (![self appendModel:model toExistingGroupByAnyMemberId:hit.localId groupType:simType]) {
        ASAssetGroup *g = [ASAssetGroup new];
        g.type = simType;
        g.assets = [NSMutableArray arrayWithObjects:hit, model, nil];
        [self.simGroupsM addObject:g];
    }

    // ✅重复组（更严格）
    if (hitIsDup) {
        if (![self appendModel:model toExistingGroupByAnyMemberId:hit.localId groupType:dupType]) {
            ASAssetGroup *g2 = [ASAssetGroup new];
            g2.type = dupType;
            g2.assets = [NSMutableArray arrayWithObjects:hit, model, nil];
            [self.dupGroupsM addObject:g2];
        }
    }

    [pool addObject:model];
    return YES; // ✅命中并入组（相似/重复至少其一）
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

    NSMutableSet *ids = [NSMutableSet set];
    __block uint64_t scannedBytes = 0;

    void (^addArr)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr){
        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
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
    addArr(self.blurryPhotosM);
    addArr(self.otherPhotosM);

    s.scannedCount = ids.count;
    s.scannedBytes = scannedBytes;

    s.screenshotCount = self.screenshotsM.count;
    for (ASAssetModel *m in self.screenshotsM) s.screenshotBytes += m.fileSizeBytes;

    s.screenRecordingCount = self.screenRecordingsM.count;
    for (ASAssetModel *m in self.screenRecordingsM) s.screenRecordingBytes += m.fileSizeBytes;

    s.bigVideoCount = self.bigVideosM.count;
    for (ASAssetModel *m in self.bigVideosM) s.bigVideoBytes += m.fileSizeBytes;

    s.blurryCount = self.blurryPhotosM.count;
    for (ASAssetModel *m in self.blurryPhotosM) s.blurryBytes += m.fileSizeBytes;

    s.otherCount = self.otherPhotosM.count;
    for (ASAssetModel *m in self.otherPhotosM) s.otherBytes += m.fileSizeBytes;
    
    self.snapshot = s;
    [self recomputeCleanableStatsFast];
}

#pragma mark - Delete remove

- (void)removeModelsByIds:(NSSet<NSString *> *)ids {
    NSArray *(^filterGroups)(NSArray<ASAssetGroup *> *) = ^NSArray *(NSArray<ASAssetGroup *> *groups){
        NSMutableArray *out = [NSMutableArray array];
        for (ASAssetGroup *g in groups) {
            NSMutableArray *kept = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (![ids containsObject:m.localId]) [kept addObject:m];
            }
            if (kept.count >= 2) {
                g.assets = kept;
                [out addObject:g];
            }
        }
        return out;
    };

    self.dupGroupsM = [[filterGroups(self.dupGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];
    self.simGroupsM = [[filterGroups(self.simGroupsM) mutableCopy] ?: [NSMutableArray array] mutableCopy];

    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(ASAssetModel *m, NSDictionary *_) {
        return ![ids containsObject:m.localId];
    }];

    self.comparableImagesM = [[self.comparableImagesM filteredArrayUsingPredicate:keep] mutableCopy];
    self.comparableVideosM = [[self.comparableVideosM filteredArrayUsingPredicate:keep] mutableCopy];

    self.screenshotsM = [[self.screenshotsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.screenRecordingsM = [[self.screenRecordingsM filteredArrayUsingPredicate:keep] mutableCopy];
    self.bigVideosM = [[self.bigVideosM filteredArrayUsingPredicate:keep] mutableCopy];
    self.blurryPhotosM = [[self.blurryPhotosM filteredArrayUsingPredicate:keep] mutableCopy];
    self.otherPhotosM  = [[self.otherPhotosM  filteredArrayUsingPredicate:keep] mutableCopy];
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

- (void)rebuildIndexFromComparablePools {
    [self.indexImage removeAllObjects];
    [self.indexVideo removeAllObjects];

    void (^addModelToIndex)(ASAssetModel *, NSMutableDictionary<NSNumber*, NSMutableArray<ASAssetModel*>*> *) =
    ^(ASAssetModel *m, NSMutableDictionary *index) {
        if (!m.phash256Data || m.phash256Data.length < 32) return;
        NSNumber *k = ASBucketKeyForPHash256(m.phash256Data);
        NSMutableArray *pool = index[k];
        if (!pool) { pool = [NSMutableArray array]; index[k] = pool; }
        [pool addObject:m];
    };

    for (ASAssetModel *m in self.comparableImagesM) addModelToIndex(m, self.indexImage);
    for (ASAssetModel *m in self.comparableVideosM) addModelToIndex(m, self.indexVideo);
}

#pragma mark - Cache IO

- (void)loadCacheIfExists {
    self.didLoadCacheFromDisk = NO;

    NSString *path = ASCachePath();
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d || d.length == 0) {
        self.cache = [ASScanCache new];
        return;
    }

    NSError *err = nil;
    ASScanCache *c = [NSKeyedUnarchiver unarchivedObjectOfClass:[ASScanCache class]
                                                       fromData:d
                                                          error:&err];
    if (!c || err) {
        self.cache = [ASScanCache new];

        // 可选：坏缓存直接删掉，避免下次还读到
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    self.cache = c;
    self.didLoadCacheFromDisk = YES;
}

- (BOOL)cacheFileExists {
    NSString *path = ASCachePath();
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
    return (sz > 0);
}

- (void)saveCache {
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:self.cache requiringSecureCoding:YES error:&err];
    if (!d || err) return;
    [d writeToFile:ASCachePath() atomically:YES];
}

- (void)applyCacheToPublicStateWithCompletion:(dispatch_block_t)completion {
    void (^assign)(void) = ^{
        self.snapshot = self.cache.snapshot ?: [ASScanSnapshot new];
        self.duplicateGroups = self.cache.duplicateGroups ?: @[];

        // ✅ UI 上 similar = (similar + duplicate)
        NSArray *sim = self.cache.similarGroups ?: @[];
        self.similarGroups = [self mergedSimilarGroupsForUIFromDup:self.duplicateGroups sim:sim];

        self.screenshots = self.cache.screenshots ?: @[];
        self.screenRecordings = self.cache.screenRecordings ?: @[];
        self.bigVideos = self.cache.bigVideos ?: @[];
        self.blurryPhotos = self.cache.blurryPhotos ?: @[];
        self.otherPhotos  = self.cache.otherPhotos  ?: @[];
        if (completion) completion();
    };

    if ([NSThread isMainThread]) assign();
    else dispatch_async(dispatch_get_main_queue(), assign);
}

- (void)applyCacheToPublicState {
    void (^assign)(void) = ^{
        self.snapshot = self.cache.snapshot ?: [ASScanSnapshot new];
        self.duplicateGroups = self.cache.duplicateGroups ?: @[];
        NSArray *sim = self.cache.similarGroups ?: @[];
        self.similarGroups = [self mergedSimilarGroupsForUIFromDup:self.duplicateGroups sim:sim];
        self.screenshots = self.cache.screenshots ?: @[];
        self.screenRecordings = self.cache.screenRecordings ?: @[];
        self.bigVideos = self.cache.bigVideos ?: @[];
        self.blurryPhotos = self.cache.blurryPhotos ?: @[];
        self.otherPhotos  = self.cache.otherPhotos ?: @[];
    };

    if ([NSThread isMainThread]) assign();
    else dispatch_async(dispatch_get_main_queue(), assign);
}

#pragma mark - Home stat refresh rule

- (BOOL)needRefreshHomeStat:(NSDate *)last {
    NSTimeInterval dt = [[NSDate date] timeIntervalSinceDate:last ?: [NSDate dateWithTimeIntervalSince1970:0]];
    return dt > 3 * 24 * 3600;
}

#pragma mark - Progress emit

- (void)emitProgress {
    self.snapshot.lastUpdated = [NSDate date];

    // 先把当前扫描中的 mutable 容器拷贝出来（在 workQ 上）
    NSArray<ASAssetGroup *> *dupCopy = [self.dupGroupsM copy] ?: self.cache.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *simCopy = [self.simGroupsM copy] ?: self.cache.similarGroups ?: @[];
    NSArray<ASAssetModel *> *shotCopy = [self.screenshotsM copy] ?: self.cache.screenshots ?: @[];
    NSArray<ASAssetModel *> *recCopy  = [self.screenRecordingsM copy] ?: self.cache.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigCopy  = [self.bigVideosM copy] ?: self.cache.bigVideos ?: @[];

    ASScanSnapshot *snap = self.snapshot; // 同一个对象也行，这里只是引用一下

    NSArray<ASAssetModel *> *blurryCopy = [self.blurryPhotosM copy] ?: self.cache.blurryPhotos ?: @[];
    NSArray<ASAssetModel *> *otherCopy  = [self.otherPhotosM copy]  ?: self.cache.otherPhotos  ?: @[];
    //关键：在同一次 main dispatch 中，先更新公开容器，再回调 UI
    dispatch_async(dispatch_get_main_queue(), ^{
        self.duplicateGroups = dupCopy;

        // UI similar = sim + dup
        self.similarGroups = [self mergedSimilarGroupsForUIFromDup:dupCopy sim:simCopy];

        self.screenshots = shotCopy;
        self.screenRecordings = recCopy;
        self.bigVideos = bigCopy;
        self.blurryPhotos = blurryCopy;
        self.otherPhotos  = otherCopy;
        if (self.progressBlock) self.progressBlock(snap);
    });
}


- (void)emitProgressMaybe {
    static CFTimeInterval lastT = 0;
    CFTimeInterval t = CACurrentMediaTime();
    if (self.snapshot.scannedCount % 100 == 0 || (t - lastT) > 2.5) {
        lastT = t;
        [self emitProgress];
    }
}

@end
