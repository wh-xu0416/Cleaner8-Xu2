#import "ASPhotoScanManager.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <float.h>
#import <Photos/Photos.h>

typedef NS_ENUM(NSInteger, ASPhotoAuthState) {
    ASPhotoAuthStateNone   = 0, // 0
    ASPhotoAuthStateLimited= 1, // limit
    ASPhotoAuthStateFull   = 2, // full
};

static inline NSDate *ASPrimaryDateForAsset(PHAsset *a) {
    NSDate *d = a.creationDate ?: a.modificationDate;
    return d ?: [NSDate dateWithTimeIntervalSince1970:0];
}

static inline NSDate *ASPrimaryDateForModel(ASAssetModel *m) {
    NSDate *d = m.creationDate ?: m.modificationDate;
    return d ?: [NSDate dateWithTimeIntervalSince1970:0];
}

static NSString * const kASPhotoAuthStateKey = @"as_photo_auth_state_v1";

static inline ASPhotoAuthState ASNormalizeAuthStatus(PHAuthorizationStatus st) {
    switch (st) {
        case PHAuthorizationStatusAuthorized: return ASPhotoAuthStateFull;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
        case PHAuthorizationStatusLimited:    return ASPhotoAuthStateLimited;
#endif
        case PHAuthorizationStatusDenied:
        case PHAuthorizationStatusRestricted:
        case PHAuthorizationStatusNotDetermined:
        default: return ASPhotoAuthStateNone;
    }
}

static const float kBlurKeepPercent = 0.05f;   // 保留最差 5%
static const NSUInteger kBlurKeepMin = 40;     // 至少 40 张
static const NSUInteger kBlurKeepMax = 300;    // 最多 300 张
static const NSUInteger kBlurWarmup  = 80;     // 前 80 张只收集，不入榜（稳定分布）

const ASComparePolicy kPolicySimilar   = { .phashThreshold = 119, .visionThreshold = 0.56f };
const ASComparePolicy kPolicyDuplicate = { .phashThreshold = 30,  .visionThreshold = 0.20f };

static NSString * const kASCacheFileName = @"as_photo_scan_cache_v2.dat";
static NSString * const kASScanSessionKey = @"as_scan_session_id_v1";
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

#ifndef AS_INC_LOG
#define AS_INC_LOG 1
#endif

#if AS_INC_LOG
#define ASIncLog(fmt, ...) NSLog((@"[INC] " fmt), ##__VA_ARGS__)
#else
#define ASIncLog(...)
#endif

static inline NSString *ASStateName(ASScanState s) {
    switch (s) {
        case ASScanStateNotScanned:     return @"NotScanned";
        case ASScanStateScanning: return @"Scanning";
        case ASScanStateFinished: return @"Finished";
    }
    return @"Unknown";
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
@property (nonatomic, copy) NSString *calendarIdentifier; // e.g. NSCalendarIdentifierGregorian
@property (nonatomic, copy) NSString *timeZoneName;        // e.g. Asia/Shanghai
@property (nonatomic, assign) NSUInteger blurDesiredK;     // 固定K（Step 7 用）

@property (nonatomic, copy) NSString *scanSessionId;
@property (nonatomic, strong) NSDate *scanStartedAt;
@property (nonatomic, strong) NSDate *lastCheckpointAt;

// 断点续扫辅助
@property (nonatomic, strong) NSDate *currentDayStart;

// 扫描中累计的 Photos 变化（关键）
@property (nonatomic, strong) NSArray<NSString *> *pendingUpsertIDs;   // inserted + changed 的 localId
@property (nonatomic, strong) NSArray<NSString *> *pendingRemovedIDs;  // removed 的 localId

// 扫描开始时的全库 baseline（杀进程兜底对账用）
@property (nonatomic, strong) NSArray<NSString *> *baselineAllAssetIDsAtStart;

// 恢复运行态（让 blurry/other 继续“同一套”逻辑）
@property (nonatomic, assign) NSUInteger blurryImagesSeen;
@property (nonatomic, assign) uint64_t blurryBytesRunning;
@property (nonatomic, assign) uint64_t otherCandidateBytes;

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
        _calendarIdentifier = NSCalendarIdentifierGregorian;
        _timeZoneName = [NSTimeZone localTimeZone].name;
        _blurDesiredK = 0;

        _scanSessionId = [[NSUUID UUID] UUIDString];
        _scanStartedAt = [NSDate date];
        _lastCheckpointAt = [NSDate dateWithTimeIntervalSince1970:0];
        _currentDayStart = nil;

        _pendingUpsertIDs = @[];
        _pendingRemovedIDs = @[];
        _baselineAllAssetIDsAtStart = @[];

        _blurryImagesSeen = 0;
        _blurryBytesRunning = 0;
        _otherCandidateBytes = 0;

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
    [coder encodeObject:self.scanSessionId forKey:@"scanSessionId"];
    [coder encodeObject:self.scanStartedAt forKey:@"scanStartedAt"];
    [coder encodeObject:self.lastCheckpointAt forKey:@"lastCheckpointAt"];
    [coder encodeObject:self.currentDayStart forKey:@"currentDayStart"];

    [coder encodeObject:self.pendingUpsertIDs forKey:@"pendingUpsertIDs"];
    [coder encodeObject:self.pendingRemovedIDs forKey:@"pendingRemovedIDs"];
    [coder encodeObject:self.baselineAllAssetIDsAtStart forKey:@"baselineAllAssetIDsAtStart"];

    [coder encodeInteger:self.blurryImagesSeen forKey:@"blurryImagesSeen"];
    [coder encodeInt64:(int64_t)self.blurryBytesRunning forKey:@"blurryBytesRunning"];
    [coder encodeInt64:(int64_t)self.otherCandidateBytes forKey:@"otherCandidateBytes"];
    [coder encodeObject:self.calendarIdentifier forKey:@"calendarIdentifier"];
    [coder encodeObject:self.timeZoneName forKey:@"timeZoneName"];
    [coder encodeInteger:self.blurDesiredK forKey:@"blurDesiredK"];
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
        _scanSessionId = [coder decodeObjectOfClass:[NSString class] forKey:@"scanSessionId"] ?: @"";
        _scanStartedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"scanStartedAt"] ?: [NSDate dateWithTimeIntervalSince1970:0];
        _lastCheckpointAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastCheckpointAt"] ?: [NSDate dateWithTimeIntervalSince1970:0];
        _currentDayStart = [coder decodeObjectOfClass:[NSDate class] forKey:@"currentDayStart"];

        NSSet *arrStr = [NSSet setWithArray:@[NSArray.class, NSString.class]];
        _pendingUpsertIDs = [coder decodeObjectOfClasses:arrStr forKey:@"pendingUpsertIDs"] ?: @[];
        _pendingRemovedIDs = [coder decodeObjectOfClasses:arrStr forKey:@"pendingRemovedIDs"] ?: @[];
        _baselineAllAssetIDsAtStart = [coder decodeObjectOfClasses:arrStr forKey:@"baselineAllAssetIDsAtStart"] ?: @[];

        _blurryImagesSeen = (NSUInteger)[coder decodeIntegerForKey:@"blurryImagesSeen"];
        _blurryBytesRunning = (uint64_t)[coder decodeInt64ForKey:@"blurryBytesRunning"];
        _otherCandidateBytes = (uint64_t)[coder decodeInt64ForKey:@"otherCandidateBytes"];
        _calendarIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"calendarIdentifier"] ?: NSCalendarIdentifierGregorian;
        _timeZoneName = [coder decodeObjectOfClass:[NSString class] forKey:@"timeZoneName"] ?: [NSTimeZone localTimeZone].name;
        _blurDesiredK = (NSUInteger)[coder decodeIntegerForKey:@"blurDesiredK"];
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
static NSString * const kASAllAssetIDsBaselineKey = @"as_all_asset_ids_baseline_v1";
static NSString * const kASHasScannedOnceKey      = @"as_has_scanned_once_v1";

#pragma mark - Manager

@interface ASPhotoScanManager ()
@property (nonatomic, strong) NSCalendar *scanCalendar;

@property (nonatomic, strong) NSMutableSet<NSString *> *pendingUpsertIDsPersist;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingRemovedIDsPersist;

// 写盘队列（避免 workQ 卡）
@property (nonatomic, strong) dispatch_queue_t ioQ;

// checkpoint 节流
@property (nonatomic, assign) CFTimeInterval lastCheckpointT;
@property (nonatomic, assign) NSUInteger lastCheckpointCount;

@property (atomic, assign) BOOL needShowPermissionPlaceholder;

@property (nonatomic, assign) NSUInteger blurryImagesSeen;
@property (nonatomic, assign) uint64_t blurryBytesRunning;

- (BOOL)matchAndGroup:(ASAssetModel *)model asset:(PHAsset *)asset;
@property (atomic) BOOL fullScanRunning;
@property (atomic) BOOL incrementalRunning;

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

@property (nonatomic, strong) NSMutableDictionary<NSUUID *, ASScanProgressBlock> *progressObservers;
@property (nonatomic, strong) dispatch_queue_t observersQ;
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

        _ioQ = dispatch_queue_create("as.photo.scan.io", DISPATCH_QUEUE_SERIAL);
        _pendingUpsertIDsPersist = [NSMutableSet set];
        _pendingRemovedIDsPersist = [NSMutableSet set];
        _lastCheckpointT = 0;
        _lastCheckpointCount = 0;

        _progressObservers = [NSMutableDictionary dictionary];
        _observersQ = dispatch_queue_create("as.photo.scan.observers", DISPATCH_QUEUE_SERIAL);

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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(as_appDidEnterBackground)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];

    }
    return self;
}

- (void)as_appDidEnterBackground {
    dispatch_async(self.workQ, ^{
        if (self.fullScanRunning) {
            [self checkpointSaveAsyncForce:YES];
        }
    });
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

// 断点续扫
- (ASScanCache *)buildCheckpointCacheSnapshot {
    ASScanCache *c = [ASScanCache new];

    // 复制 cache 基本信息（scan session 等）
    c.scanSessionId = self.cache.scanSessionId ?: @"";
    c.scanStartedAt = self.cache.scanStartedAt ?: [NSDate date];
    c.baselineAllAssetIDsAtStart = self.cache.baselineAllAssetIDsAtStart ?: @[];

    c.calendarIdentifier = self.cache.calendarIdentifier ?: NSCalendarIdentifierGregorian;
    c.timeZoneName = self.cache.timeZoneName ?: [NSTimeZone localTimeZone].name;
    c.blurDesiredK = self.cache.blurDesiredK;

    c.lastCheckpointAt = [NSDate date];
    c.currentDayStart = self.currentDay;

    // snapshot：Scanning 状态
    c.snapshot = [self cloneSnapshot:self.snapshot];
    c.snapshot.state = ASScanStateScanning;

    // 复制当前容器（用 M 容器优先）
    c.duplicateGroups = [self.dupGroupsM copy] ?: self.cache.duplicateGroups ?: @[];
    c.similarGroups   = [self.simGroupsM copy] ?: self.cache.similarGroups ?: @[];
    c.screenshots     = [self.screenshotsM copy] ?: self.cache.screenshots ?: @[];
    c.screenRecordings = [self.screenRecordingsM copy] ?: self.cache.screenRecordings ?: @[];
    c.bigVideos       = [self.bigVideosM copy] ?: self.cache.bigVideos ?: @[];

    c.comparableImages = [self.comparableImagesM copy] ?: self.cache.comparableImages ?: @[];
    c.comparableVideos = [self.comparableVideosM copy] ?: self.cache.comparableVideos ?: @[];

    c.blurryPhotos = [self.blurryPhotosM copy] ?: self.cache.blurryPhotos ?: @[];
    c.otherPhotos  = [self.otherPhotosM copy]  ?: self.cache.otherPhotos  ?: @[];

    // 恢复用运行态
    c.blurryImagesSeen = self.blurryImagesSeen;
    c.blurryBytesRunning = self.blurryBytesRunning;
    c.otherCandidateBytes = self.otherCandidateBytes;

    // 扫描中变更累计集合（持久化）
    c.pendingUpsertIDs = self.pendingUpsertIDsPersist.allObjects ?: @[];
    c.pendingRemovedIDs = self.pendingRemovedIDsPersist.allObjects ?: @[];

    // anchorDate：这里可以保持原 cache.anchorDate（Finished 才有意义），Scanning 不强依赖
    c.anchorDate = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];
    c.homeStatRefreshDate = self.cache.homeStatRefreshDate ?: [NSDate dateWithTimeIntervalSince1970:0];

    return c;
}

- (void)checkpointSaveAsyncForce:(BOOL)force {
    CFTimeInterval now = CACurrentMediaTime();

    // 节流 每 100 张或 3 秒一次
    BOOL hitCount = (self.snapshot.scannedCount - self.lastCheckpointCount) >= 100;
    BOOL hitTime  = (now - self.lastCheckpointT) >= 3;

    if (!force && !(hitCount || hitTime)) return;

    self.lastCheckpointT = now;
    self.lastCheckpointCount = self.snapshot.scannedCount;

    ASScanCache *snap = [self buildCheckpointCacheSnapshot];

    self.cache = snap;
    [self saveCacheAsync];
}

#pragma mark - Baseline IDs (Swift-style)

- (NSArray<NSString *> *)as_loadBaselineAllAssetIDs {
    NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:kASAllAssetIDsBaselineKey];
    if ([arr isKindOfClass:NSArray.class]) return arr;
    return @[];
}

- (void)as_saveBaselineAllAssetIDs:(NSArray<NSString *> *)ids {
    if (!ids) ids = @[];
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kASAllAssetIDsBaselineKey];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kASHasScannedOnceKey];
}

- (void)prepareScanCalendarFromCache {
    NSString *cid = self.cache.calendarIdentifier ?: NSCalendarIdentifierGregorian;
    NSString *tzName = self.cache.timeZoneName ?: [NSTimeZone localTimeZone].name;

    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:cid];
    cal.timeZone = [NSTimeZone timeZoneWithName:tzName] ?: [NSTimeZone localTimeZone];

    self.scanCalendar = cal;
}

- (NSDate *)as_dayStart:(NSDate *)date {
    NSDate *d = date ?: [NSDate dateWithTimeIntervalSince1970:0];
    NSCalendar *cal = self.scanCalendar ?: [NSCalendar currentCalendar];

    if (@available(iOS 8.0, *)) {
        return [cal startOfDayForDate:d];
    }
    NSDateComponents *c = [cal components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:d];
    return [cal dateFromComponents:c] ?: d;
}

- (NSArray<NSString *> *)as_currentAllAssetIDsFromFetchResult:(PHFetchResult<PHAsset *> *)fr {
    if (!fr) return @[];
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:fr.count];
    for (PHAsset *a in fr) {
        NSString *lid = a.localIdentifier ?: @"";
        if (lid.length) [ids addObject:lid];
    }
    return ids;
}

#pragma mark - Force fallback diff (Swift parity)

- (void)checkIncrementalFromDiskAnchorForceFallback {
    if ([self as_currentAuthState] == ASPhotoAuthStateNone) return;
    if (self.fullScanRunning || self.incrementalRunning) return;
    if (self.cache.snapshot.state != ASScanStateFinished) return;

    [self refreshAllAssetsFetchResult];
    PHFetchResult<PHAsset *> *allFR = self.allAssetsFetchResult;
    if (!allFR) return;

    NSArray<NSString *> *baselineArr = [self as_loadBaselineAllAssetIDs];

    NSSet<NSString *> *baselineSet = nil;
    if (baselineArr.count > 0) {
        baselineSet = [NSSet setWithArray:baselineArr];
    } else {
        baselineSet = [self as_collectCachedIdsFromCache];
    }

    NSMutableSet<NSString *> *currentSet = [NSMutableSet setWithCapacity:allFR.count];
    NSMutableArray<NSString *> *insertedIds = [NSMutableArray array];

    for (PHAsset *a in allFR) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;

        [currentSet addObject:lid];
        if (![baselineSet containsObject:lid]) {
            [insertedIds addObject:lid];
        }
    }

    NSMutableSet<NSString *> *removedSet = [NSMutableSet setWithSet:baselineSet ?: [NSSet set]];
    [removedSet minusSet:currentSet];

    ASIncLog(@"FORCE-FALLBACK diff | inserted=%lu removed=%lu baseline=%lu current=%lu",
             (unsigned long)insertedIds.count,
             (unsigned long)removedSet.count,
             (unsigned long)baselineSet.count,
             (unsigned long)currentSet.count);

    if (insertedIds.count == 0 && removedSet.count == 0) {
        // baseline 为空或不完整时，写一次当前全量
        if (baselineArr.count == 0 || baselineSet.count != currentSet.count) {
            [self as_saveBaselineAllAssetIDs:currentSet.allObjects ?: @[]];
        }
        return;
    }

    NSArray<PHAsset *> *insertedAssets = [self as_fetchAssetsByLocalIdsChunked:insertedIds];

    [self incrementalRebuildWithInserted:insertedAssets
                              removedIDs:removedSet.allObjects ?: @[]];

    [self as_saveBaselineAllAssetIDs:currentSet.allObjects ?: @[]];
}


- (void)updateBlurryTopKIncremental:(ASAssetModel *)m desiredK:(NSUInteger)desiredK {
    if (!m || m.blurScore < 0.f) return;
    if (desiredK == 0) return;

    if (!self.blurryPhotosM) self.blurryPhotosM = [NSMutableArray array];

    if (self.blurryPhotosM.count >= desiredK) {
        ASAssetModel *leastBlurry = self.blurryPhotosM.lastObject; // 升序：last 最不糊
        if (!(m.blurScore < leastBlurry.blurScore)) return;

        [self.blurryPhotosM removeLastObject];
        if (self.blurryBytesRunning >= leastBlurry.fileSizeBytes) self.blurryBytesRunning -= leastBlurry.fileSizeBytes;
    }

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

- (NSUUID *)addProgressObserver:(ASScanProgressBlock)block {
    if (!block) return nil;

    NSUUID *token = [NSUUID UUID];

    dispatch_async(self.observersQ, ^{
        self.progressObservers[token] = [block copy];
    });

    ASScanSnapshot *snap = self.snapshot;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(snap);
    });

    return token;
}

- (void)removeProgressObserver:(NSUUID *)token {
    if (!token) return;
    dispatch_async(self.observersQ, ^{
        [self.progressObservers removeObjectForKey:token];
    });
}

- (void)notifyProgressObserversOnMain:(ASScanSnapshot *)snap {
    __block NSArray<ASScanProgressBlock> *blocks = nil;
    dispatch_sync(self.observersQ, ^{
        blocks = self.progressObservers.allValues ?: @[];
    });

    for (ASScanProgressBlock b in blocks) {
        b(snap);
    }
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

#pragma mark - Auth state (current / stored)

- (PHAuthorizationStatus)as_rawPhotoAuthStatus {
    if (@available(iOS 14.0, *)) {
        return [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    }
    return [PHPhotoLibrary authorizationStatus];
}

- (ASPhotoAuthState)as_currentAuthState {
    return ASNormalizeAuthStatus([self as_rawPhotoAuthStatus]);
}

- (NSInteger)as_storedAuthStateRaw {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kASPhotoAuthStateKey];
}

- (BOOL)as_hasStoredAuthState {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kASPhotoAuthStateKey] != nil;
}

- (void)as_storeAuthState:(ASPhotoAuthState)st {
    [[NSUserDefaults standardUserDefaults] setInteger:st forKey:kASPhotoAuthStateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)as_requestPhotoPermission:(void(^)(ASPhotoAuthState st))done {
    if (@available(iOS 14.0, *)) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
            ASPhotoAuthState st = ASNormalizeAuthStatus(status);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done) done(st);
            });
        }];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            ASPhotoAuthState st = ASNormalizeAuthStatus(status);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done) done(st);
            });
        }];
    }
}

#pragma mark - Startup policy (YOUR RULES)

/// 首页启动入口：按规则决定
/// - 有权限+有缓存：先展示缓存 -> 再增量
/// - 有权限+无缓存：全量
/// - 无权限：请求权限（首次）/ 或提示按钮占位（后续）
/// - 权限发生变化（0<->limit/full，limit<->full）：全量（无视缓存）
//  建议把返回值改成 token（Home 持有并在离开时 remove）
-(nullable NSUUID *)startupForHomeWithProgress:(ASScanProgressBlock)progress
                                     completion:(ASScanCompletionBlock)completion
                      showPermissionPlaceholder:(dispatch_block_t)showPermissionPlaceholder
{
    // 0) 注册进度观察者：立刻推一帧 snapshot
    NSUUID *token = nil;
    if (progress) {
        token = [self addProgressObserver:progress];
    }
    if (completion) self.completionBlock = [completion copy];

    // 统一：展示权限占位（保证主线程）
    void (^showPlaceholderOnMain)(void) = ^{
        self.needShowPermissionPlaceholder = YES;
        if (showPermissionPlaceholder) {
            dispatch_async(dispatch_get_main_queue(), showPermissionPlaceholder);
        }
    };

    PHAuthorizationStatus raw = [self as_rawPhotoAuthStatus];
    ASPhotoAuthState current = [self as_currentAuthState];

    BOOL hasStored = [self as_hasStoredAuthState];
    ASPhotoAuthState last = hasStored ? (ASPhotoAuthState)[self as_storedAuthStateRaw] : ASPhotoAuthStateNone;

    BOOL busy = self.fullScanRunning || self.incrementalRunning;

    // 1) 忙时：只处理“权限被撤销/未决定”
    if (busy) {
        if (current == ASPhotoAuthStateNone || raw == PHAuthorizationStatusNotDetermined) {
            [self cancel];
            [self as_storeAuthState:ASPhotoAuthStateNone];
            showPlaceholderOnMain();
            [self resetPublicStateForNoPermission];
            [self emitProgress];
        }
        return token;
    }

    // 2) 未决定：请求权限
    if (raw == PHAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [self as_requestPhotoPermission:^(ASPhotoAuthState st) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [self as_storeAuthState:st];

            if (st == ASPhotoAuthStateNone) {
                showPlaceholderOnMain();
                [self resetPublicStateForNoPermission];
                [self emitProgress];
                return;
            }

            [self dropCacheFile];
            [self startFullScanWithProgress:nil completion:self.completionBlock];
        }];
        return token;
    }

    // 3) 已经无权限
    if (current == ASPhotoAuthStateNone) {
        [self as_storeAuthState:ASPhotoAuthStateNone];
        showPlaceholderOnMain();
        [self resetPublicStateForNoPermission];
        [self emitProgress];
        return token;
    }

    // 4) 历史权限没记录：当作变化，全量
    if (!hasStored) {
        [self as_storeAuthState:current];
        [self dropCacheFile];
        [self startFullScanWithProgress:nil completion:self.completionBlock];
        return token;
    }

    // 5) 权限变化：无视缓存，全量
    if (last != current) {
        [self as_storeAuthState:current];
        [self dropCacheFile];
        [self startFullScanWithProgress:nil completion:self.completionBlock];
        return token;
    }

    // 6) 权限没变：先用缓存（必须 finished），然后 schedule 增量
    [self as_storeAuthState:current];

    if ([self loadCacheIfExists]) {
        __weak typeof(self) weakSelf = self;
        [self applyCacheToPublicStateWithCompletion:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            ASScanState st = self.cache.snapshot.state;

            if (st == ASScanStateFinished) {
                // 你原来的逻辑：emit + purge + scheduleIncrementalCheck
                [self emitProgress];
                dispatch_async(self.workQ, ^{
                    [self refreshAllAssetsFetchResult];
                    [self purgeDeletedAssetsAndRecalculate];
                    [self scheduleIncrementalCheck];
                });
            } else if (st == ASScanStateScanning) {
                // ✅ 新逻辑：展示半成品 + 继续扫描
                [self emitProgress];
                dispatch_async(self.workQ, ^{
                    [self resumeFullScanFromCache];
                });
            }

        }];
        return token;
    }

    // 7) 没缓存：全量
    [self startFullScanWithProgress:nil completion:self.completionBlock];
    return token;
}

- (void)resumeFullScanFromCache {
    if (self.fullScanRunning || self.incrementalRunning) return;
    if ([self as_currentAuthState] == ASPhotoAuthStateNone) return;
    if (!self.cache || !self.cache.snapshot) return;
    if (self.cache.snapshot.state != ASScanStateScanning) return;

    NSUInteger desiredK = self.cache.blurDesiredK ?: [self blurryDesiredKForLibraryQuick];
    self.cache.blurDesiredK = desiredK;
    
    [self prepareScanCalendarFromCache];

    self.fullScanRunning = YES;
    self.cancelled = NO;

    // 1) 从 cache 恢复所有 M 容器（复用你 incrementalRebuild 的初始化方式）
    self.dupGroupsM = [self deepMutableGroups:self.cache.duplicateGroups];
    self.simGroupsM = [self deepMutableGroups:self.cache.similarGroups];
    self.screenshotsM = [self.cache.screenshots mutableCopy] ?: [NSMutableArray array];
    self.screenRecordingsM = [self.cache.screenRecordings mutableCopy] ?: [NSMutableArray array];
    self.bigVideosM = [self.cache.bigVideos mutableCopy] ?: [NSMutableArray array];
    self.comparableImagesM = [self.cache.comparableImages mutableCopy] ?: [NSMutableArray array];
    self.comparableVideosM = [self.cache.comparableVideos mutableCopy] ?: [NSMutableArray array];
    self.blurryPhotosM = [self.cache.blurryPhotos mutableCopy] ?: [NSMutableArray array];
    self.otherPhotosM  = [self.cache.otherPhotos  mutableCopy] ?: [NSMutableArray array];

    self.snapshot = [self cloneSnapshot:self.cache.snapshot];
    self.snapshot.state = ASScanStateScanning;

    self.currentDay = self.cache.currentDayStart;

    // 恢复运行态
    self.blurryImagesSeen = self.cache.blurryImagesSeen;
    self.blurryBytesRunning = self.cache.blurryBytesRunning;
    self.otherCandidateBytes = self.cache.otherCandidateBytes;

    // 2) 恢复 otherCandidateMap（用 otherPhotosM 重建）
    self.otherCandidateMap = [NSMutableDictionary dictionary];
    for (ASAssetModel *m in self.otherPhotosM) {
        if (m.localId.length) self.otherCandidateMap[m.localId] = m;
    }

    // 3) 关键：构建 “已处理 ID 集合” （用于跳过已扫）
    NSMutableSet<NSString *> *processed = [self as_collectCachedIdsFromCache];

    // 4) 关键：构建 day -> seed index（保证同一天续扫不会漏匹配）
    NSMutableDictionary<NSDate*, NSMutableArray<ASAssetModel*>*> *seedImg = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSDate*, NSMutableArray<ASAssetModel*>*> *seedVid = [NSMutableDictionary dictionary];

    for (ASAssetModel *m in self.comparableImagesM) {
        NSDate *d0 = [self as_dayStart:ASPrimaryDateForModel(m)];
        if (!seedImg[d0]) seedImg[d0] = [NSMutableArray array];
        [seedImg[d0] addObject:m];
    }
    for (ASAssetModel *m in self.comparableVideosM) {
        NSDate *d0 = [self as_dayStart:ASPrimaryDateForModel(m)];
        if (!seedVid[d0]) seedVid[d0] = [NSMutableArray array];
        [seedVid[d0] addObject:m];
    }

    // 5) 重置 index（每进新 day 需要 seed）
    [self.indexImage removeAllObjects];
    [self.indexVideo removeAllObjects];

    // 6) 开始继续扫描（依旧按 creationDate desc）
    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithOptions:[self allImageVideoFetchOptions]];

    NSDate *maxAnchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];

    for (PHAsset *asset in result) {
        @autoreleasepool {
            if (self.cancelled) break;

            NSString *lid = asset.localIdentifier ?: @"";
            if (lid.length && [processed containsObject:lid]) {
                continue; //  已经扫过，跳过
            }

            NSDate *cd = ASPrimaryDateForAsset(asset);
            NSDate *md = asset.modificationDate ?: cd;
            if ([cd compare:maxAnchor] == NSOrderedDescending) maxAnchor = cd;
            if ([md compare:maxAnchor] == NSOrderedDescending) maxAnchor = md;

            NSDate *day = [self as_dayStart:cd];

            if (!self.currentDay || ![day isEqualToDate:self.currentDay]) {
                self.currentDay = day;

                // 切天：清 index + seed
                [self.indexImage removeAllObjects];
                [self.indexVideo removeAllObjects];

                NSArray *si = seedImg[day] ?: @[];
                for (ASAssetModel *m in si) {
                    if (m.phash256Data.length >= 32) {
                        NSNumber *k = ASBucketKeyForPHash256(m.phash256Data);
                        if (!self.indexImage[k]) self.indexImage[k] = [NSMutableArray array];
                        [self.indexImage[k] addObject:m];
                    }
                }

                NSArray *sv = seedVid[day] ?: @[];
                for (ASAssetModel *m in sv) {
                    if (m.phash256Data.length >= 32) {
                        NSNumber *k = ASBucketKeyForPHash256(m.phash256Data);
                        if (!self.indexVideo[k]) self.indexVideo[k] = [NSMutableArray array];
                        [self.indexVideo[k] addObject:m];
                    }
                }
            }

            NSError *error = nil;
            ASAssetModel *model = [self buildModelForAsset:asset computeCompareBits:YES error:&error];
            if (!model) continue;

            // 下面这段基本复用你 full scan 的分类逻辑（截图/模糊/录屏/大视频/分组）
            self.snapshot.scannedCount += 1;
            self.snapshot.scannedBytes += model.fileSizeBytes;

            if (ASIsScreenshot(asset)) {
                [self.screenshotsM addObject:model];
                self.snapshot.screenshotCount += 1;
                self.snapshot.screenshotBytes += model.fileSizeBytes;
                [self emitProgressMaybe];
                [self checkpointSaveAsyncForce:NO];
                continue;
            }

            if (asset.mediaType == PHAssetMediaTypeImage) {
                [self setModule:ASHomeModuleTypeOtherPhotos state:ASModuleScanStateScanning];
                [self otherCandidateAddIfNeeded:model asset:asset];
            }

            if (asset.mediaType == PHAssetMediaTypeImage) {
                float score = [self blurScoreForAsset:asset];
                if (score >= 0.f) {
                    model.blurScore = score;
                    [self updateBlurryTopKFixed:model desiredK:desiredK];
                }
            }

            if (ASIsScreenRecording(asset)) {
                [self.screenRecordingsM addObject:model];
                self.snapshot.screenRecordingCount += 1;
                self.snapshot.screenRecordingBytes += model.fileSizeBytes;
                [self emitProgressMaybe];
                [self checkpointSaveAsyncForce:NO];
                continue;
            }

            if (asset.mediaType == PHAssetMediaTypeVideo && model.fileSizeBytes >= kBigVideoMinBytes) {
                [self.bigVideosM addObject:model];
                self.snapshot.bigVideoCount += 1;
                self.snapshot.bigVideoBytes += model.fileSizeBytes;
            }

            if (ASAllowedForCompare(asset)) {
                BOOL grouped = [self matchAndGroup:model asset:asset];
                if (grouped && asset.mediaType == PHAssetMediaTypeImage) {
                    [self otherCandidateRemoveIfExistsLocalId:model.localId];
                }

                if (asset.mediaType == PHAssetMediaTypeImage) [self.comparableImagesM addObject:model];
                else if (asset.mediaType == PHAssetMediaTypeVideo) [self.comparableVideosM addObject:model];

                [self recomputeCleanableStatsFast];
            }

            [self emitProgressMaybe];
            [self checkpointSaveAsyncForce:NO];

            self.cache.anchorDate = [self as_safeAnchorDate:maxAnchor];
        }
    }

    // ✅ 用最终的 result 重建 Other（排除 dup/sim/screenshot/blurry）
    self.otherPhotosM = [[self buildOtherPhotosFromAllAssetsFetchResult:result] mutableCopy];

    // ✅ 重算 otherBytes & snapshot
    self.otherCandidateBytes = 0;
    for (ASAssetModel *m in self.otherPhotosM) self.otherCandidateBytes += m.fileSizeBytes;

    self.snapshot.otherCount = self.otherPhotosM.count;
    self.snapshot.otherBytes = self.otherCandidateBytes;

    // 7) 扫完：置 Finished、写最终 cache、apply、emit
    self.snapshot.state = ASScanStateFinished;
    [self setAllModulesState:ASModuleScanStateFinished];

    self.cache.snapshot = [self cloneSnapshot:self.snapshot];
    self.cache.duplicateGroups = [self.dupGroupsM copy];
    self.cache.similarGroups = [self.simGroupsM copy];
    self.cache.screenshots = [self.screenshotsM copy];
    self.cache.screenRecordings = [self.screenRecordingsM copy];
    self.cache.bigVideos = [self.bigVideosM copy];
    self.cache.comparableImages = [self.comparableImagesM copy];
    self.cache.comparableVideos = [self.comparableVideosM copy];
    self.cache.blurryPhotos = [self.blurryPhotosM copy];
    self.cache.otherPhotos  = [self.otherPhotosM copy];

    self.cache.currentDayStart = self.currentDay;
    self.cache.blurryImagesSeen = self.blurryImagesSeen;
    self.cache.blurryBytesRunning = self.blurryBytesRunning;
    self.cache.otherCandidateBytes = self.otherCandidateBytes;

    self.cache.pendingUpsertIDs = self.pendingUpsertIDsPersist.allObjects ?: @[];
    self.cache.pendingRemovedIDs = self.pendingRemovedIDsPersist.allObjects ?: @[];

    [self saveCacheAsync];

    [self applyCacheToPublicStateWithCompletion:^{
        [self emitProgress];
    }];

    [self refreshAllAssetsFetchResult];
    NSArray *ids = [self as_currentAllAssetIDsFromFetchResult:self.allAssetsFetchResult];
    [self as_saveBaselineAllAssetIDs:ids];

    // 8) Finished 后：做一次“对账式增量”（Step 8 会实现）
    dispatch_async(self.workQ, ^{
        [self reconcilePendingChangesAfterFullScan];
    });

    self.fullScanRunning = NO;
    [self debugValidateConsistency:@"resume-finished"];
}

- (void)debugValidateConsistency:(NSString *)tag {
#if DEBUG
    uint64_t shotB=0, recB=0, bigB=0, blurB=0, otherB=0;
    for (ASAssetModel *m in self.screenshotsM) shotB += m.fileSizeBytes;
    for (ASAssetModel *m in self.screenRecordingsM) recB += m.fileSizeBytes;
    for (ASAssetModel *m in self.bigVideosM) bigB += m.fileSizeBytes;
    for (ASAssetModel *m in self.blurryPhotosM) blurB += m.fileSizeBytes;
    for (ASAssetModel *m in self.otherPhotosM) otherB += m.fileSizeBytes;

    NSLog(@"[VALIDATE %@] shot(%lu/%llu) rec(%lu/%llu) big(%lu/%llu) blur(%lu/%llu) other(%lu/%llu)",
          tag,
          (unsigned long)self.screenshotsM.count, shotB,
          (unsigned long)self.screenRecordingsM.count, recB,
          (unsigned long)self.bigVideosM.count, bigB,
          (unsigned long)self.blurryPhotosM.count, blurB,
          (unsigned long)self.otherPhotosM.count, otherB);

    NSCAssert(self.snapshot.screenshotCount == self.screenshotsM.count, @"screenshotCount mismatch");
    NSCAssert(self.snapshot.screenRecordingCount == self.screenRecordingsM.count, @"screenRecordingCount mismatch");
    NSCAssert(self.snapshot.bigVideoCount == self.bigVideosM.count, @"bigVideoCount mismatch");
    NSCAssert(self.snapshot.blurryCount == self.blurryPhotosM.count, @"blurryCount mismatch");
    NSCAssert(self.snapshot.otherCount == self.otherPhotosM.count, @"otherCount mismatch");
#endif
}

/// 无权限时，让首页有一个“空态”
- (void)resetPublicStateForNoPermission {
    // stop pending incremental timers / debounce
    if (self.incrementalDebounceBlock) {
        dispatch_block_cancel(self.incrementalDebounceBlock);
        self.incrementalDebounceBlock = nil;
    }
    self.pendingIncremental = NO;
    self.incrementalScheduled = NO;
    [self.pendingInsertedMap removeAllObjects];
    [self.pendingRemovedIDs removeAllObjects];
    self.allAssetsFetchResult = nil;

    // public empty state
    self.snapshot = [ASScanSnapshot new];
    self.snapshot.state = ASScanStateNotScanned;
    [self setAllModulesState:ASModuleScanStateIdle];

    self.duplicateGroups = @[];
    self.similarGroups = @[];
    self.screenshots = @[];
    self.screenRecordings = @[];
    self.bigVideos = @[];
    self.blurryPhotos = @[];
    self.otherPhotos = @[];

    [self emitProgress];
}


#pragma mark - Public

- (void)loadCacheAndCheckIncremental {
    if ([self as_currentAuthState] == ASPhotoAuthStateNone) {
        [self resetPublicStateForNoPermission];
        return;
    }

    if ([self loadCacheIfExists]) {
        __weak typeof(self) weakSelf = self;
        [self applyCacheToPublicStateWithCompletion:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [self emitProgress];

            dispatch_async(self.workQ, ^{
                [self refreshAllAssetsFetchResult];
                [self scheduleIncrementalCheck];
            });
        }];
    } else {
        [self refreshAllAssetsFetchResult];
        [self scheduleIncrementalCheck];
    }
}

- (NSUUID *)subscribeProgress:(ASScanProgressBlock)progress {
    return [self addProgressObserver:progress];
}

- (void)startFullScanWithProgress:(ASScanProgressBlock)progress
                       completion:(ASScanCompletionBlock)completion
{
    self.fullScanRunning = YES;
    self.cancelled = NO;

    // progress：当成“临时 observer”，避免覆盖别的页面的 observer
    __block NSUUID *tempToken = nil;
    if (progress) {
        tempToken = [self addProgressObserver:progress];
    }

    // completion：局部 copy，避免被覆盖/改写
    ASScanCompletionBlock completionCopy = [completion copy];

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

            // 建立新的 scan session
            self.cache.scanSessionId = [[NSUUID UUID] UUIDString];
            self.cache.scanStartedAt = [NSDate date];
            
            self.cache.calendarIdentifier = NSCalendarIdentifierGregorian;
            self.cache.timeZoneName = [NSTimeZone localTimeZone].name;
            [self prepareScanCalendarFromCache];

            // 记录 scan-start baseline（兜底用）
            [self refreshAllAssetsFetchResult];
            NSArray *baseline = [self as_currentAllAssetIDsFromFetchResult:self.allAssetsFetchResult];
            self.cache.baselineAllAssetIDsAtStart = baseline ?: @[];

            // 清空持久化 pending
            [self.pendingUpsertIDsPersist removeAllObjects];
            [self.pendingRemovedIDsPersist removeAllObjects];

            // 第一次 checkpoint，确保“开始扫描”也能恢复
            [self checkpointSaveAsyncForce:YES];

            // 固定K：全程不变，断点恢复也用同一个
            self.cache.blurDesiredK = [self blurryDesiredKForLibraryQuick];
            NSUInteger desiredK = self.cache.blurDesiredK;

            for (PHAsset *asset in result) {
                @autoreleasepool {
                    if (self.cancelled) {
                        error = [NSError errorWithDomain:@"ASPhotoScan"
                                                    code:-999
                                                userInfo:@{NSLocalizedDescriptionKey:@"cancelled"}];
                        break;
                    }
                    
                    NSDate *cd = ASPrimaryDateForAsset(asset);
                    NSDate *md = asset.modificationDate ?: cd;

                    if ([cd compare:maxAnchor] == NSOrderedDescending) maxAnchor = cd;
                    if ([md compare:maxAnchor] == NSOrderedDescending) maxAnchor = md;

                    NSDate *day = [self as_dayStart:cd];
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
                        [self checkpointSaveAsyncForce:NO];
                        continue;
                    }

                    // Other：先把普通照片当作候选，扫描中就能实时看到列表/数量/大小
                    if (asset.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(asset)) {
                        [self setModule:ASHomeModuleTypeOtherPhotos state:ASModuleScanStateScanning];
                        [self otherCandidateAddIfNeeded:model asset:asset];
                        [self emitProgressMaybe];
                        [self checkpointSaveAsyncForce:NO];
                    }

                    // Blurry：允许和 similar/duplicate 重叠，但不包含 screenshot
                    if (asset.mediaType == PHAssetMediaTypeImage && !ASIsScreenshot(asset)) {
                        float score = [self blurScoreForAsset:asset];
                        if (score >= 0.f) {
                            model.blurScore = score;
                            [self updateBlurryTopKFixed:model desiredK:desiredK];
                            [self emitProgressMaybe];
                            [self checkpointSaveAsyncForce:NO];
                        }
                    }

                    if (ASIsScreenRecording(asset)) {
                        [self.screenRecordingsM addObject:model];
                        self.snapshot.screenRecordingCount += 1;
                        self.snapshot.screenRecordingBytes += model.fileSizeBytes;
                        [self emitProgressMaybe];
                        [self checkpointSaveAsyncForce:NO];
                        continue;
                    }

                    if (asset.mediaType == PHAssetMediaTypeVideo && model.fileSizeBytes >= kBigVideoMinBytes) {
                        [self.bigVideosM addObject:model];
                        self.snapshot.bigVideoCount += 1;
                        self.snapshot.bigVideoBytes += model.fileSizeBytes;
                    }

                    if (!ASAllowedForCompare(asset)) {
                        [self emitProgressMaybe];
                        [self checkpointSaveAsyncForce:NO];
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
                    [self checkpointSaveAsyncForce:NO];
                }
            }

            if (!error && !self.cancelled) {
                self.snapshot.state = ASScanStateFinished;
                self.snapshot.duplicateGroupCount = self.dupGroupsM.count;
                self.snapshot.similarGroupCount = self.simGroupsM.count;
                self.snapshot.lastUpdated = [NSDate date];

                [self setModule:ASHomeModuleTypeOtherPhotos state:ASModuleScanStateScanning];
                self.otherPhotosM = [[self buildOtherPhotosFromAllAssetsFetchResult:result] mutableCopy];

                self.cache.snapshot = [self cloneSnapshot:self.snapshot];
                self.cache.duplicateGroups = [self.dupGroupsM copy];
                self.cache.similarGroups = [self.simGroupsM copy];
                self.cache.screenshots = [self.screenshotsM copy];
                self.cache.screenRecordings = [self.screenRecordingsM copy];
                self.cache.bigVideos = [self.bigVideosM copy];

                self.cache.anchorDate = [self as_safeAnchorDate:maxAnchor];

                self.cache.comparableImages = [self.comparableImagesM copy];
                self.cache.comparableVideos = [self.comparableVideosM copy];

                self.cache.blurryPhotos = [self.blurryPhotosM copy];
                self.cache.otherPhotos  = [self.otherPhotosM copy];

                if ([self needRefreshHomeStat:self.cache.homeStatRefreshDate]) {
                    self.cache.homeStatRefreshDate = [NSDate date];
                }
                
                self.cache.pendingUpsertIDs = self.pendingUpsertIDsPersist.allObjects ?: @[];
                self.cache.pendingRemovedIDs = self.pendingRemovedIDsPersist.allObjects ?: @[];
                self.cache.currentDayStart = self.currentDay;
                self.cache.blurryImagesSeen = self.blurryImagesSeen;
                self.cache.blurryBytesRunning = self.blurryBytesRunning;
                self.cache.otherCandidateBytes = self.otherCandidateBytes;

                [self saveCacheAsync];
                [self setModule:ASHomeModuleTypeBlurryPhotos state:ASModuleScanStateFinished];
                [self setModule:ASHomeModuleTypeOtherPhotos  state:ASModuleScanStateFinished];
                [self setAllModulesState:ASModuleScanStateFinished];

                [self applyCacheToPublicStateWithCompletion:^{
                    self.blurryPhotos = self.cache.blurryPhotos ?: @[];
                    self.otherPhotos  = self.cache.otherPhotos ?: @[];
                    [self emitProgress];
                }];

                [self refreshAllAssetsFetchResult];
                NSArray *ids = [self as_currentAllAssetIDsFromFetchResult:self.allAssetsFetchResult];
                [self as_saveBaselineAllAssetIDs:ids];

                if (self.pendingIncremental) {
                    self.pendingIncremental = NO;
                    [self scheduleIncrementalCheck];
                }
            }

            self.fullScanRunning = NO;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionCopy) completionCopy(self.snapshot, error);
                if (tempToken) [self removeProgressObserver:tempToken];
            });

            if (self.pendingIncremental) {
                self.pendingIncremental = NO;
                [self scheduleIncrementalCheck];
            }
            
            [self debugValidateConsistency:@"full-finished"];
        }
    });
}

- (void)reconcilePendingChangesAfterFullScan {
    if ([self as_currentAuthState] == ASPhotoAuthStateNone) return;
    if (self.cache.snapshot.state != ASScanStateFinished) return;
    if (self.fullScanRunning || self.incrementalRunning) return;

    // 1) baseline diff 兜底（防 scan 中被杀导致未记录 change）
    [self refreshAllAssetsFetchResult];
    NSArray<NSString *> *currentAll = [self as_currentAllAssetIDsFromFetchResult:self.allAssetsFetchResult];
    NSSet *currentSet = [NSSet setWithArray:(currentAll ?: @[])];

    NSArray<NSString *> *base = self.cache.baselineAllAssetIDsAtStart ?: @[];
    NSSet *baseSet = [NSSet setWithArray:base];

    // inserted = current - base
    NSMutableSet<NSString*> *inserted = [NSMutableSet setWithSet:currentSet.mutableCopy];
    [inserted minusSet:baseSet];

    // removed = base - current
    NSMutableSet<NSString*> *removed = [NSMutableSet setWithSet:baseSet.mutableCopy];
    [removed minusSet:currentSet];

    // 2) 合并进持久化 pending
    [self.pendingUpsertIDsPersist unionSet:inserted];
    [self.pendingRemovedIDsPersist unionSet:removed];

    // removed 覆盖 upsert
    for (NSString *rid in self.pendingRemovedIDsPersist) {
        [self.pendingUpsertIDsPersist removeObject:rid];
    }

    if (self.pendingUpsertIDsPersist.count == 0 && self.pendingRemovedIDsPersist.count == 0) {
        // 对账完也要刷新 baseline（以后正常增量用）
        [self as_saveBaselineAllAssetIDs:currentAll ?: @[]];
        return;
    }

    // 3) 真正跑一次 incrementalRebuild（此时 cache 已 finished，安全）
    NSArray<PHAsset*> *upserts = [self as_fetchAssetsByLocalIdsChunked:self.pendingUpsertIDsPersist.allObjects];
    NSArray<NSString*> *rmIDs = self.pendingRemovedIDsPersist.allObjects;

    // 清空 pending（先清，避免增量里又触发重复）
    [self.pendingUpsertIDsPersist removeAllObjects];
    [self.pendingRemovedIDsPersist removeAllObjects];
    self.cache.pendingUpsertIDs = @[];
    self.cache.pendingRemovedIDs = @[];
    [self saveCacheAsync];

    [self incrementalRebuildWithInserted:upserts removedIDs:rmIDs];

    // 注意：incrementalRebuild 结束时你会调用 as_saveBaselineAllAssetIDs
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
    if (!self.didLoadCacheFromDisk) {
        [self loadCacheIfExists];   // 失败会返回 NO 并 drop 无效文件
    }
    return [self isSnapshotCacheUsableForUI:self.cache.snapshot];
}

- (BOOL)hasUsableCacheOnDisk {
    if (![self cacheFileExists]) return NO;
    if (!self.didLoadCacheFromDisk) {
        if (![self loadCacheIfExists]) return NO;
    }
    return [self isSnapshotCacheUsableForUI:self.cache.snapshot];
}

- (ASScanSnapshot *)cloneSnapshot:(ASScanSnapshot *)src {
    ASScanSnapshot *s = [ASScanSnapshot new];
    if (!src) return s;

    s.state = src.state;
    s.scannedCount = src.scannedCount;
    s.scannedBytes = src.scannedBytes;

    s.cleanableCount = src.cleanableCount;
    s.cleanableBytes = src.cleanableBytes;

    s.screenshotCount = src.screenshotCount;
    s.screenshotBytes = src.screenshotBytes;

    s.screenRecordingCount = src.screenRecordingCount;
    s.screenRecordingBytes = src.screenRecordingBytes;

    s.bigVideoCount = src.bigVideoCount;
    s.bigVideoBytes = src.bigVideoBytes;

    s.blurryCount = src.blurryCount;
    s.blurryBytes = src.blurryBytes;

    s.otherCount = src.otherCount;
    s.otherBytes = src.otherBytes;

    s.duplicateGroupCount = src.duplicateGroupCount;
    s.similarGroupCount = src.similarGroupCount;

    s.lastUpdated = src.lastUpdated ?: [NSDate date];
    s.phash256Data = [src.phash256Data copy];
    s.moduleStates = [src.moduleStates copy] ?: @[@0,@0,@0,@0,@0,@0,@0,@0,@0];
    return s;
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
        self.cache.snapshot = [self cloneSnapshot:self.snapshot];
        self.cache.duplicateGroups = [self.dupGroupsM copy];
        self.cache.similarGroups   = [self.simGroupsM copy];
        self.cache.screenshots     = [self.screenshotsM copy];
        self.cache.screenRecordings = [self.screenRecordingsM copy];
        self.cache.bigVideos       = [self.bigVideosM copy];
        self.cache.comparableImages = [self.comparableImagesM copy];
        self.cache.comparableVideos = [self.comparableVideosM copy];
        self.cache.blurryPhotos    = [self.blurryPhotosM copy];
        self.cache.otherPhotos     = [self.otherPhotosM copy];

        [self saveCacheAsync];

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

    uint8_t *p = (uint8_t *)roi8.data;
    uint64_t n = (uint64_t)roi8.width * (uint64_t)roi8.height;
    double sum=0, sum2=0;
    for (uint64_t i=0;i<n;i++){ double v=p[i]; sum+=v; sum2+=v*v; }
    double mean = sum / (double)MAX(n,1);
    double var  = sum2/(double)MAX(n,1) - mean*mean;
    if (var < 0) var = 0;
    double std  = sqrt(var);

    float score = -1.f;
    if (mean > 20.0 && std > 8.0) {
        score = [self tenengradFloatOnROI8:roi8];
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
    const uint32_t w = (uint32_t)roi8.width, h = (uint32_t)roi8.height;
    if (w < 5 || h < 5) return 0.f;

    vImage_Buffer f = {0};
    f.width = w; f.height = h; f.rowBytes = w * sizeof(float);
    f.data = malloc(f.rowBytes * h);
    if (!f.data) return 0.f;

    vImageConvert_Planar8toPlanarF(&roi8, &f, 1.0f/255.0f, 0.0f, kvImageNoFlags);

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

- (void)updateBlurryTopKFixed:(ASAssetModel *)m desiredK:(NSUInteger)desiredK {
    if (!m || m.blurScore < 0.f || desiredK == 0) return;
    if (!self.blurryPhotosM) self.blurryPhotosM = [NSMutableArray array];

    // 榜满：只有更糊才进（score 越小越糊）
    if (self.blurryPhotosM.count >= desiredK) {
        ASAssetModel *leastBlurry = self.blurryPhotosM.lastObject; // last 最不糊
        if (!(m.blurScore < leastBlurry.blurScore)) return;

        [self.blurryPhotosM removeLastObject];
        if (self.blurryBytesRunning >= leastBlurry.fileSizeBytes) self.blurryBytesRunning -= leastBlurry.fileSizeBytes;
        else self.blurryBytesRunning = 0;

        // 踢出的回 other
        [self otherCandidateAddModelIfNeeded:leastBlurry];
    }

    // 二分插入（升序：小=更糊）
    NSUInteger lo = 0, hi = self.blurryPhotosM.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) >> 1;
        ASAssetModel *x = self.blurryPhotosM[mid];
        if (m.blurScore < x.blurScore) hi = mid;
        else lo = mid + 1;
    }
    [self.blurryPhotosM insertObject:m atIndex:lo];
    self.blurryBytesRunning += m.fileSizeBytes;

    // 进 blurry，从 other 移除
    [self otherCandidateRemoveIfExistsLocalId:m.localId];

    self.snapshot.blurryCount = self.blurryPhotosM.count;
    self.snapshot.blurryBytes = self.blurryBytesRunning;
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
        int mag = abs(gx) + abs(gy);
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
#pragma mark - Incremental Fix Helpers

static const NSUInteger kASLocalIdChunk = 3500;

- (NSDate *)as_safeAnchorDate:(NSDate *)candidate {
    NSDate *now = [NSDate date];
    if (!candidate) return now;

    if ([candidate timeIntervalSinceDate:now] > 60.0) return now;
    return candidate;
}

- (NSMutableSet<NSString *> *)as_collectCachedIdsFromCache {
    NSMutableSet<NSString *> *cachedIds = [NSMutableSet set];

    NSArray<ASAssetGroup *> *dup = self.cache.duplicateGroups ?: @[];
    for (ASAssetGroup *g in dup)
        for (ASAssetModel *m in g.assets)
            if (m.localId.length) [cachedIds addObject:m.localId];

    NSArray<ASAssetGroup *> *sim = self.cache.similarGroups ?: @[];
    for (ASAssetGroup *g in sim)
        for (ASAssetModel *m in g.assets)
            if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.screenshots ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.screenRecordings ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.bigVideos ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.blurryPhotos ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.otherPhotos ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.comparableImages ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    for (ASAssetModel *m in (self.cache.comparableVideos ?: @[]))
        if (m.localId.length) [cachedIds addObject:m.localId];

    return cachedIds;
}

- (NSArray<PHAsset *> *)as_fetchAssetsByLocalIdsChunked:(NSArray<NSString *> *)ids {
    if (ids.count == 0) return @[];

    NSMutableArray<PHAsset *> *out = [NSMutableArray arrayWithCapacity:ids.count];

    for (NSUInteger i = 0; i < ids.count; i += kASLocalIdChunk) {
        NSRange r = NSMakeRange(i, MIN(kASLocalIdChunk, ids.count - i));
        NSArray<NSString *> *slice = [ids subarrayWithRange:r];
        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:slice options:nil];
        for (PHAsset *a in fr) {
            if (a.localIdentifier.length) [out addObject:a];
        }
    }
    return out;
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
    dispatch_async(self.workQ, ^{
        BOOL busy = self.fullScanRunning || self.incrementalRunning;

        PHFetchResult *fr = self.allAssetsFetchResult;
        PHFetchResultChangeDetails *changes = fr ? [changeInstance changeDetailsForFetchResult:fr] : nil;

        if (changes && changes.hasIncrementalChanges) {
            self.allAssetsFetchResult = changes.fetchResultAfterChanges;

            NSArray<PHAsset*> *insertedRaw = changes.insertedObjects ?: @[];
            NSArray<PHAsset*> *changedRaw  = changes.changedObjects  ?: @[];
            NSArray<PHAsset*> *removedRaw  = changes.removedObjects  ?: @[];

            for (PHAsset *a in insertedRaw) {
                if (a.localIdentifier.length) [self.pendingUpsertIDsPersist addObject:a.localIdentifier];
            }
            for (PHAsset *a in changedRaw) {
                if (a.localIdentifier.length) [self.pendingUpsertIDsPersist addObject:a.localIdentifier];
            }
            for (PHAsset *a in removedRaw) {
                if (a.localIdentifier.length) [self.pendingRemovedIDsPersist addObject:a.localIdentifier];
            }
            // removed 覆盖 upsert
            for (NSString *rid in self.pendingRemovedIDsPersist) {
                [self.pendingUpsertIDsPersist removeObject:rid];
            }

            // 扫描中/增量中：只累计 + checkpoint，不做 rebuild
            if (busy || self.cache.snapshot.state != ASScanStateFinished) {
                self.pendingIncremental = YES;
                [self checkpointSaveAsyncForce:NO];
                return;
            }

            // cache finished 且不 busy：走你原有 debounce incremental（保持原逻辑）
            NSMutableArray<PHAsset*> *upserts = [NSMutableArray arrayWithArray:insertedRaw];
            [upserts addObjectsFromArray:changedRaw];
            [self scheduleIncrementalRebuildWithInserted:upserts removed:removedRaw];
            return;
        }

        // 没有 changeDetails：扫描中只记 pending，Finished 则 scheduleIncrementalCheck
        if (busy || self.cache.snapshot.state != ASScanStateFinished) {
            self.pendingIncremental = YES;
            [self checkpointSaveAsyncForce:NO];
            return;
        }
        [self scheduleIncrementalCheck];
    });
}

- (void)scheduleIncrementalRebuildWithInserted:(NSArray<PHAsset *> *)inserted
                                      removed:(NSArray<PHAsset *> *)removed
{
    BOOL busy = self.fullScanRunning || self.incrementalRunning;

    ASIncLog(@"PHChange fired | busy=%d snap=%@ cache=%@ pendingInc=%d",
             (int)busy,
             ASStateName(self.snapshot.state),
             ASStateName(self.cache.snapshot.state),
             (int)self.pendingIncremental);

    if (busy) {
        ASIncLog(@"skip: rebuild running -> pendingIncremental=YES");
        self.pendingIncremental = YES;
        return;
    }

    // 合并：inserted / removed 先汇总起来
    for (PHAsset *a in inserted) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        [self.pendingRemovedIDs removeObject:lid];
        self.pendingInsertedMap[lid] = a;
    }

    for (PHAsset *a in removed) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        [self.pendingInsertedMap removeObjectForKey:lid];
        [self.pendingRemovedIDs addObject:lid];
    }
    
    ASIncLog(@"debounce queued | pendingInserted=%lu pendingRemoved=%lu",
             (unsigned long)self.pendingInsertedMap.count,
             (unsigned long)self.pendingRemovedIDs.count);

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
        
        if (self.cache.snapshot.state != ASScanStateFinished) {
            ASIncLog(@"skip: cache not finished (cacheState=%@)", ASStateName(self.cache.snapshot.state));
            return;
        }
        
        ASIncLog(@"debounce fire | finalInserted=%lu finalRemoved=%lu cacheState=%@",
                 (unsigned long)finalInserted.count,
                 (unsigned long)finalRemovedIDs.count,
                 ASStateName(self.cache.snapshot.state));
        
        [self.pendingInsertedMap removeAllObjects];
        [self.pendingRemovedIDs removeAllObjects];

        if (self.cache.snapshot.state != ASScanStateFinished) return;

        [self incrementalRebuildWithInserted:finalInserted removedIDs:finalRemovedIDs];
    });

    self.incrementalDebounceBlock = block;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   self.workQ,
                   block);
}

- (void)publishSnapshotStateOnMain:(ASScanState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.snapshot.state = state;
        [self notifyProgressObserversOnMain:self.snapshot];
    });
}

- (void)incrementalRebuildWithInserted:(NSArray<PHAsset*> *)inserted
                            removedIDs:(NSArray<NSString*> *)removedIDs
{
    self.incrementalRunning = YES;

    ASIncLog(@"rebuild begin | inserted=%lu removed=%lu oldAnchor=%@",
             (unsigned long)inserted.count,
             (unsigned long)(removedIDs.count),
             self.cache.anchorDate);

    NSDate *newAnchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];

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

    NSArray<ASAssetModel *> *oldBlur = [self.blurryPhotosM copy] ?: @[];

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

    NSMutableSet<NSDate*> *affectedDayStarts = [NSMutableSet set];

    // inserted：新 day（creation）
    NSMutableSet<NSString *> *upsertIds = [NSMutableSet set];
    for (PHAsset *a in inserted) {
        NSString *lid = a.localIdentifier ?: @"";
        if (lid.length) [upsertIds addObject:lid];

        NSDate *cd = ASPrimaryDateForAsset(a);
        [affectedDayStarts addObject:[self as_dayStart:cd]];
    }

    // removed：用缓存模型的 creation day
    NSSet<NSString*> *removedIdSet = [NSSet setWithArray:(removedIDs ?: @[])];
    [self as_collectDayStartsForLocalIds:removedIdSet into:affectedDayStarts];

    // upsert old-day：如果 creationDate 被改导致跨天，补上旧 day
    [self as_collectDayStartsForLocalIds:upsertIds into:affectedDayStarts];

    NSMutableSet<NSString*> *deletedIDs = [NSMutableSet setWithArray:(removedIDs ?: @[])];
    if (deletedIDs.count) {
        [self removeModelsByIds:deletedIDs];

        for (NSString *lid in deletedIDs) {
            if (lid.length) [self.visionMemo removeObjectForKey:lid];
        }
        for (NSString *lid in deletedIDs) {
            if (lid.length) [ASScreenRecordingMemo() removeObjectForKey:lid];
        }

        self.blurryBytesRunning = 0;
        for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;
    }

    if (affectedDayStarts.count) {
        [self removeModelsByDayStarts:affectedDayStarts];

        self.blurryBytesRunning = 0;
        for (ASAssetModel *bm in self.blurryPhotosM) self.blurryBytesRunning += bm.fileSizeBytes;

        newAnchor = [self rebuildDaysObjC:affectedDayStarts];
    }

    [self rebuildIndexFromComparablePools];

    NSMutableSet<NSDate*> *otherRefreshDays = [affectedDayStarts mutableCopy];
    [self as_addBlurChangedDayStartsFromOld:oldBlur toNew:(self.blurryPhotosM ?: @[]) into:otherRefreshDays];
    [self as_replaceOtherForDayStarts:otherRefreshDays];

    [self recomputeSnapshotFromCurrentContainers];

    self.cache.snapshot = [self cloneSnapshot:self.snapshot];
    self.cache.duplicateGroups = [self.dupGroupsM copy];
    self.cache.similarGroups   = [self.simGroupsM copy];
    self.cache.screenshots     = [self.screenshotsM copy];
    self.cache.screenRecordings = [self.screenRecordingsM copy];
    self.cache.bigVideos       = [self.bigVideosM copy];

    self.cache.comparableImages = [self.comparableImagesM copy];
    self.cache.comparableVideos = [self.comparableVideosM copy];

    self.cache.blurryPhotos = [self.blurryPhotosM copy];
    self.cache.otherPhotos  = [self.otherPhotosM  copy];

    self.cache.anchorDate = [self as_safeAnchorDate:newAnchor];

    [self saveCacheAsync];

    [self refreshAllAssetsFetchResult];
    NSArray *ids = [self as_currentAllAssetIDsFromFetchResult:self.allAssetsFetchResult];
    [self as_saveBaselineAllAssetIDs:ids];

    [self setAllModulesState:ASModuleScanStateFinished];

    ASIncLog(@"rebuild done | dup=%lu sim=%lu shot=%lu rec=%lu big=%lu blurry=%lu other=%lu newAnchor=%@",
             (unsigned long)self.dupGroupsM.count,
             (unsigned long)self.simGroupsM.count,
             (unsigned long)self.screenshotsM.count,
             (unsigned long)self.screenRecordingsM.count,
             (unsigned long)self.bigVideosM.count,
             (unsigned long)self.blurryPhotosM.count,
             (unsigned long)self.otherPhotosM.count,
             self.cache.anchorDate);

    [self applyCacheToPublicStateWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.snapshot.state = ASScanStateFinished;
            [self emitProgress];

            self.incrementalRunning = NO;

            if (self.pendingIncremental) {
                self.pendingIncremental = NO;
                dispatch_async(self.workQ, ^{
                    [self scheduleIncrementalCheck];
                });
            }
        });
    }];
}

#pragma mark - Other Incremental (affectedDays only)

- (NSMutableSet<NSString *> *)as_buildExcludeIdsForOther {
    NSMutableSet<NSString *> *ex = [NSMutableSet set];

    for (ASAssetGroup *g in self.dupGroupsM) {
        for (ASAssetModel *m in g.assets) if (m.localId.length) [ex addObject:m.localId];
    }
    for (ASAssetGroup *g in self.simGroupsM) {
        for (ASAssetModel *m in g.assets) if (m.localId.length) [ex addObject:m.localId];
    }
    for (ASAssetModel *m in self.blurryPhotosM) if (m.localId.length) [ex addObject:m.localId];

    return ex;
}

- (NSMutableDictionary<NSString *, ASAssetModel *> *)as_buildComparableImageMap {
    NSMutableDictionary<NSString *, ASAssetModel *> *map =
        [NSMutableDictionary dictionaryWithCapacity:self.comparableImagesM.count];

    for (ASAssetModel *m in self.comparableImagesM) {
        if (m.localId.length) map[m.localId] = m;
    }
    return map;
}

- (NSArray<ASAssetModel *> *)as_buildOtherForDayStart:(NSDate *)dayStart
                                             exclude:(NSSet<NSString *> *)exclude
                                         modelByLocal:(NSDictionary<NSString*, ASAssetModel*> *)modelByLocal
{
    if (!dayStart) return @[];

    NSCalendar *cal = self.scanCalendar ?: [NSCalendar currentCalendar];
    NSDate *dayEnd = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];

    PHFetchOptions *opt = [self allImageVideoFetchOptions];
    opt.predicate = [NSPredicate predicateWithFormat:
        @"(mediaType == %d) AND NOT ((mediaSubtypes & %d) != 0) AND creationDate >= %@ AND creationDate < %@",
        PHAssetMediaTypeImage, PHAssetMediaSubtypePhotoScreenshot,
        dayStart, dayEnd
    ];

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithOptions:opt];
    if (!fr) return @[];

    NSMutableArray<ASAssetModel *> *out = [NSMutableArray arrayWithCapacity:fr.count];

    for (PHAsset *a in fr) {
        NSString *lid = a.localIdentifier ?: @"";
        if (!lid.length) continue;
        if ([exclude containsObject:lid]) continue;

        ASAssetModel *m = modelByLocal[lid];
        if (m) {
            [out addObject:m];
        } else {
            NSError *err = nil;
            ASAssetModel *fallback = [self buildModelForAsset:a computeCompareBits:NO error:&err];
            if (fallback) [out addObject:fallback];
        }
    }

    return out;
}

- (void)as_replaceOtherForDayStarts:(NSSet<NSDate *> *)dayStarts {
    if (dayStarts.count == 0) return;
    if (!self.otherPhotosM) self.otherPhotosM = [NSMutableArray array];

    NSMutableArray<ASAssetModel *> *kept = [NSMutableArray arrayWithCapacity:self.otherPhotosM.count];
    for (ASAssetModel *m in self.otherPhotosM) {
        NSDate *cd = ASPrimaryDateForModel(m);
        NSDate *d0 = [self as_dayStart:cd];
        if (![dayStarts containsObject:d0]) [kept addObject:m];
    }
    self.otherPhotosM = kept;

    NSSet<NSString *> *exclude = [self as_buildExcludeIdsForOther];
    NSDictionary<NSString*, ASAssetModel*> *modelByLocal = [self as_buildComparableImageMap];

    NSArray<NSDate *> *sortedDays = [[dayStarts allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [b compare:a]; // desc
    }];

    NSCalendar *cal = self.scanCalendar ?: [NSCalendar currentCalendar];

    for (NSDate *dayStart in sortedDays) {
        NSArray<ASAssetModel *> *dayOther =
            [self as_buildOtherForDayStart:dayStart exclude:exclude modelByLocal:modelByLocal];
        if (dayOther.count == 0) continue;

        NSDate *dayEnd = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];

        NSUInteger lo = 0, hi = self.otherPhotosM.count;
        while (lo < hi) {
            NSUInteger mid = (lo + hi) >> 1;
            NSDate *md = self.otherPhotosM[mid].creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];

            if ([md compare:dayEnd] != NSOrderedAscending) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        NSIndexSet *idx = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(lo, dayOther.count)];
        [self.otherPhotosM insertObjects:dayOther atIndexes:idx];
    }
}

- (void)as_collectDayStartsForLocalIds:(NSSet<NSString*> *)ids into:(NSMutableSet<NSDate*> *)out {
    if (ids.count == 0 || !out) return;

    void (^scan)(NSArray<ASAssetModel*> *) = ^(NSArray<ASAssetModel*> *arr) {
        for (ASAssetModel *m in arr) {
            if (!m.localId.length) continue;
            if (![ids containsObject:m.localId]) continue;
            NSDate *cd = ASPrimaryDateForModel(m);
            [out addObject:[self as_dayStart:cd]];
        }
    };

    scan(self.comparableImagesM);
    scan(self.screenshotsM);
    scan(self.blurryPhotosM);
    scan(self.otherPhotosM);
}

- (void)as_addBlurChangedDayStartsFromOld:(NSArray<ASAssetModel*> *)oldBlur
                                  toNew:(NSArray<ASAssetModel*> *)newBlur
                                   into:(NSMutableSet<NSDate*> *)dayStarts
{
    if (!dayStarts) return;

    NSMutableSet<NSString*> *oldIds = [NSMutableSet set];
    for (ASAssetModel *m in oldBlur) if (m.localId.length) [oldIds addObject:m.localId];

    NSMutableSet<NSString*> *newIds = [NSMutableSet set];
    for (ASAssetModel *m in newBlur) if (m.localId.length) [newIds addObject:m.localId];

    NSMutableSet<NSString*> *removed = [oldIds mutableCopy];
    [removed minusSet:newIds];

    NSMutableSet<NSString*> *added = [newIds mutableCopy];
    [added minusSet:oldIds];

    if (removed.count) {
        for (ASAssetModel *m in oldBlur) {
            if ([removed containsObject:m.localId]) {
                NSDate *cd = ASPrimaryDateForModel(m);
                [dayStarts addObject:[self as_dayStart:cd]];
            }
        }
    }
    if (added.count) {
        for (ASAssetModel *m in newBlur) {
            if ([added containsObject:m.localId]) {
                NSDate *cd = ASPrimaryDateForModel(m);
                [dayStarts addObject:[self as_dayStart:cd]];
            }
        }
    }
}


#pragma mark - FetchOptions (All image+video, include hidden, include sources)

- (PHFetchOptions *)allImageVideoFetchOptions {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]
    ];

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

- (PHFetchOptions *)comparableFetchOptions {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]
    ];

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
        NSDate *cd = ASPrimaryDateForModel(m);
        NSDate *d0 = [self as_dayStart:cd];
        return ![dayStarts containsObject:d0];
    }];

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

    NSCalendar *cal = self.scanCalendar ?: [NSCalendar currentCalendar];
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
    if (self.cache.snapshot.state != ASScanStateFinished) return;
    if ([self as_currentAuthState] == ASPhotoAuthStateNone) return;

    if (self.fullScanRunning || self.incrementalRunning) {
        self.pendingIncremental = YES;
        return;
    }
    if (self.incrementalScheduled) return;

    self.incrementalScheduled = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   self.workQ, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        self.incrementalScheduled = NO;

        [self checkIncrementalFromDiskAnchor];
    });
}

#pragma mark - Incremental

- (void)checkIncrementalFromDiskAnchor {
    ASIncLog(@"checkFromAnchor begin | cacheState=%@ didLoad=%d rawAnchor=%@",
             ASStateName(self.cache.snapshot.state),
             (int)self.didLoadCacheFromDisk,
             self.cache.anchorDate);

    if (self.cache.snapshot.state != ASScanStateFinished) return;
    if (self.fullScanRunning || self.incrementalRunning) return;

    [self refreshAllAssetsFetchResult];
    PHFetchResult<PHAsset *> *allFR = self.allAssetsFetchResult;
    if (!allFR) return;

    NSDate *rawAnchor = self.cache.anchorDate ?: [NSDate dateWithTimeIntervalSince1970:0];
    NSDate *anchor = [self as_safeAnchorDate:rawAnchor];
    if (anchor != rawAnchor && ![anchor isEqualToDate:rawAnchor]) {
        self.cache.anchorDate = anchor;
        [self saveCacheAsync];
    }

    PHFetchOptions *opt = [self allImageVideoFetchOptions];
    opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    opt.predicate = [NSPredicate predicateWithFormat:
        @"(((mediaType == %d) OR (mediaType == %d)) AND ((creationDate > %@) OR (modificationDate > %@)))",
        PHAssetMediaTypeImage, PHAssetMediaTypeVideo, anchor, anchor
    ];
    PHFetchResult<PHAsset *> *deltaFR = [PHAsset fetchAssetsWithOptions:opt];

    NSMutableSet<NSString *> *cachedIds = [self as_collectCachedIdsFromCache];
    NSMutableSet<NSString *> *deleted = [NSMutableSet set];

    if (cachedIds.count > 0) {
        NSMutableSet<NSString *> *existIds = [NSMutableSet setWithCapacity:cachedIds.count];
        NSArray<NSString *> *allCached = cachedIds.allObjects;

        for (NSUInteger i = 0; i < allCached.count; i += kASLocalIdChunk) {
            NSRange r = NSMakeRange(i, MIN(kASLocalIdChunk, allCached.count - i));
            NSArray<NSString *> *slice = [allCached subarrayWithRange:r];
            PHFetchResult<PHAsset *> *existFR = [PHAsset fetchAssetsWithLocalIdentifiers:slice options:nil];
            for (PHAsset *a in existFR) {
                if (a.localIdentifier.length) [existIds addObject:a.localIdentifier];
            }
        }

        [deleted unionSet:cachedIds];
        [deleted minusSet:existIds];
    }

    ASIncLog(@"time-delta result | deltaFR=%lu deleted=%lu anchor=%@",
             (unsigned long)deltaFR.count,
             (unsigned long)deleted.count,
             anchor);

    if (deltaFR.count == 0 && deleted.count == 0) {
        [self checkIncrementalFromDiskAnchorForceFallback];
        return;
    }

    NSMutableArray<PHAsset *> *deltaAssets = [NSMutableArray arrayWithCapacity:deltaFR.count];
    for (PHAsset *a in deltaFR) {
        if (a.localIdentifier.length) [deltaAssets addObject:a];
    }

    [self incrementalRebuildWithInserted:deltaAssets removedIDs:deleted.allObjects];
    [self refreshAllAssetsFetchResult];

    ASIncLog(@"delta path done | delta=%lu deleted=%lu current=%lu cached=%lu",
             (unsigned long)deltaAssets.count,
             (unsigned long)deleted.count,
             (unsigned long)allFR.count,
             (unsigned long)self.cache.snapshot.scannedCount);
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

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(ctx);

    for (int i = 0; i < width * height; i++) {
        float r = (float)pixels[i*4 + 0];
        float g = (float)pixels[i*4 + 1];
        float b = (float)pixels[i*4 + 2];

        float enhanced = 1.1f * (0.299f*r + 0.587f*g + 0.114f*b) - 10.f;
        if (enhanced < 0.f) enhanced = 0.f;
        if (enhanced > 255.f) enhanced = 255.f;

        uint8_t e8 = (uint8_t)enhanced;

        pixels[i*4 + 0] = e8;
        pixels[i*4 + 1] = e8;
        pixels[i*4 + 2] = e8;
    }

    float floatPixels[64 * 64];
    for (int i = 0; i < width * height; i++) {
        floatPixels[i] = (float)pixels[i*4 + 0];
    }

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

    float topLeft[16 * 16];
    int idx = 0;
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            topLeft[idx++] = floatPixels[r * 64 + c];
        }
    }

    float sorted[16 * 16];
    memcpy(sorted, topLeft, sizeof(sorted));
    qsort(sorted, 256, sizeof(float), ASFloatCmp);
    float median = sorted[256 / 2];

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

    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    __block uint64_t scannedBytes = 0;

    void (^addArr)(NSArray<ASAssetModel *> *) = ^(NSArray<ASAssetModel *> *arr){
        for (ASAssetModel *m in (arr ?: @[])) {
            if (!m.localId.length) continue;
            if ([ids containsObject:m.localId]) continue;
            [ids addObject:m.localId];
            scannedBytes += m.fileSizeBytes;
        }
    };

    // 覆盖全库：comparable(非截屏图片 + 非录屏视频) + screenshots + screenRecordings
    addArr(self.comparableImagesM);
    addArr(self.comparableVideosM);
    addArr(self.screenshotsM);
    addArr(self.screenRecordingsM);

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

    s.duplicateGroupCount = self.dupGroupsM.count;
    s.similarGroupCount   = self.simGroupsM.count;
    s.lastUpdated = [NSDate date];

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

#pragma mark - Cache Path

- (NSString *)cacheFilePath {
    return ASCachePath();
}

- (void)dropCacheFile {
    NSString *path = ASCachePath();
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

#pragma mark - Cache Validate / Normalize

- (BOOL)normalizeSnapshotIfNeeded:(ASScanSnapshot *)s {
    if (!s) return NO;

    // moduleStates 强制长度=9（兼容旧缓存/脏数据）
    NSMutableArray<NSNumber *> *ms = nil;
    if ([s.moduleStates isKindOfClass:NSArray.class]) {
        ms = [s.moduleStates mutableCopy];
    } else {
        ms = [NSMutableArray array];
    }
    while (ms.count < 9) [ms addObject:@(ASModuleScanStateIdle)];
    if (ms.count > 9) [ms removeObjectsInRange:NSMakeRange(9, ms.count - 9)];
    s.moduleStates = ms;

    if (!s.lastUpdated) s.lastUpdated = [NSDate date];
    return YES;
}

- (BOOL)isSnapshotCacheUsableForUI:(ASScanSnapshot *)s {
    if (!s) return NO;
    if (s.state != ASScanStateFinished && s.state != ASScanStateScanning) return NO;
    if (![s.moduleStates isKindOfClass:NSArray.class]) return NO;
    if (s.moduleStates.count != 9) return NO;
    return YES;
}

- (BOOL)isSnapshotCacheUsableForIncremental:(ASScanSnapshot *)s {
    if (!s) return NO;
    if (s.state != ASScanStateFinished) return NO;
    if (![s.moduleStates isKindOfClass:NSArray.class]) return NO;
    if (s.moduleStates.count != 9) return NO;
    return YES;
}

#pragma mark - Load Cache

-(BOOL)loadCacheIfExists {
    if (self.didLoadCacheFromDisk && self.snapshot != nil) {
        return YES;
    }
    NSString *path = ASCachePath();
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSLog(@"[CACHE] load path=%@ size=%llu", path, [attr[NSFileSize] unsignedLongLongValue]);
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (data.length == 0) return NO;

    NSError *err = nil;
    ASScanCache *obj = nil;

    if (@available(iOS 11.0, *)) {
        NSSet *classes = [NSSet setWithArray:@[
            NSArray.class, NSMutableArray.class,
            NSDictionary.class, NSMutableDictionary.class,
            NSString.class, NSNumber.class, NSDate.class, NSData.class,
            ASScanSnapshot.class,
            ASAssetModel.class,
            ASAssetGroup.class,
            ASScanCache.class
        ]];
        obj = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&err];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        @try { obj = [NSKeyedUnarchiver unarchiveObjectWithData:data]; }
        @catch (__unused NSException *e) { obj = nil; }
#pragma clang diagnostic pop
    }

    if (!obj || err) {
        NSLog(@"[缓存] unarchive failed: %@ -> drop", err);
        [self dropCacheFile];
        return NO;
    }

    ASScanSnapshot *snap = obj.snapshot;
    if (![self normalizeSnapshotIfNeeded:snap] || ![self isSnapshotCacheUsableForUI:snap]) {
        NSLog(@"[缓存] invalid -> drop");
        [self dropCacheFile];
        return NO;
    }
    // obj 校验通过之后
    self.cache = obj;

    // 从 obj / self.cache（已是 obj）恢复 pending
    [self.pendingUpsertIDsPersist removeAllObjects];
    [self.pendingRemovedIDsPersist removeAllObjects];

    NSArray<NSString *> *up = self.cache.pendingUpsertIDs ?: @[];
    NSArray<NSString *> *rm = self.cache.pendingRemovedIDs ?: @[];

    [self.pendingUpsertIDsPersist addObjectsFromArray:up];
    [self.pendingRemovedIDsPersist addObjectsFromArray:rm];

    // removed 覆盖 upsert（防止脏数据）
    for (NSString *rid in self.pendingRemovedIDsPersist) {
        [self.pendingUpsertIDsPersist removeObject:rid];
    }

    self.didLoadCacheFromDisk = YES;
    return YES;
}

- (void)saveCacheAsync {
    dispatch_async(self.ioQ, ^{
        [self saveCache];
    });
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
    NSLog(@"[CACHE] archive bytes=%lu err=%@", (unsigned long)d.length, err);

    if (!d || err || d.length == 0) return;

    NSString *path = ASCachePath();
    BOOL ok = [d writeToFile:path atomically:YES];
    NSLog(@"[CACHE] write path=%@ ok=%d", path, (int)ok);
    if (!ok) return;

    NSError *pe = nil;
    [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                     ofItemAtPath:path
                                            error:&pe];
    NSLog(@"[CACHE] protect err=%@", pe);
}

- (void)applyCacheToPublicStateWithCompletion:(dispatch_block_t)completion {
    void (^assign)(void) = ^{
        self.snapshot = [self cloneSnapshot:self.cache.snapshot];

        self.duplicateGroups = self.cache.duplicateGroups ?: @[];

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
        self.snapshot = [self cloneSnapshot:self.cache.snapshot];
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

    NSArray<ASAssetGroup *> *dupCopy = [self.dupGroupsM copy] ?: self.cache.duplicateGroups ?: @[];
    NSArray<ASAssetGroup *> *simCopy = [self.simGroupsM copy] ?: self.cache.similarGroups ?: @[];
    NSArray<ASAssetModel *> *shotCopy = [self.screenshotsM copy] ?: self.cache.screenshots ?: @[];
    NSArray<ASAssetModel *> *recCopy  = [self.screenRecordingsM copy] ?: self.cache.screenRecordings ?: @[];
    NSArray<ASAssetModel *> *bigCopy  = [self.bigVideosM copy] ?: self.cache.bigVideos ?: @[];

    ASScanSnapshot *snap = self.snapshot;

    NSArray<ASAssetModel *> *blurryCopy = [self.blurryPhotosM copy] ?: self.cache.blurryPhotos ?: @[];
    NSArray<ASAssetModel *> *otherCopy  = [self.otherPhotosM copy]  ?: self.cache.otherPhotos  ?: @[];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.duplicateGroups = dupCopy;
        self.similarGroups = [self mergedSimilarGroupsForUIFromDup:dupCopy sim:simCopy];
        self.screenshots = shotCopy;
        self.screenRecordings = recCopy;
        self.bigVideos = bigCopy;
        self.blurryPhotos = blurryCopy;
        self.otherPhotos  = otherCopy;

        [self notifyProgressObserversOnMain:snap];
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
