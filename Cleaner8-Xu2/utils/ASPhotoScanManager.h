#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    uint32_t phashThreshold;
    float    visionThreshold;
} ASComparePolicy;

extern const ASComparePolicy kPolicySimilar;
extern const ASComparePolicy kPolicyDuplicate;

typedef NS_ENUM(NSUInteger, ASScanState) {
    ASScanStateNotScanned = 0,
    ASScanStateScanning,
    ASScanStateFinished
};

typedef NS_ENUM(NSUInteger, ASGroupType) {
    ASGroupTypeDuplicateImage = 0,
    ASGroupTypeSimilarImage,
    ASGroupTypeDuplicateVideo,
    ASGroupTypeSimilarVideo
};

@class ASAssetModel, ASAssetGroup, ASScanSnapshot;

typedef NS_ENUM(NSInteger, ASModuleScanState) {
    ASModuleScanStateIdle = 0,     // 等待/未开始
    ASModuleScanStateScanning,     // 扫描中（遍历相册、收集素材）
    ASModuleScanStateAnalyzing,    // 分析中（相似/重复比对阶段）
    ASModuleScanStateFinished,     // 完成
};

/// ⚠️ moduleStates 固定长度 = 9，对应 .m 内 ASHomeModuleType 顺序：
/// 0 SimilarImage
/// 1 SimilarVideo
/// 2 DuplicateImage
/// 3 DuplicateVideo
/// 4 Screenshots
/// 5 ScreenRecordings
/// 6 BigVideos
/// 7 BlurryPhotos
/// 8 OtherPhotos
@interface ASScanSnapshot : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSArray<NSNumber *> *moduleStates; // 长度固定=9

@property (nonatomic) ASScanState state;

@property (nonatomic) NSUInteger scannedCount;
@property (nonatomic) uint64_t   scannedBytes;

@property (nonatomic) NSUInteger cleanableCount;  // 相似/重复的每组除第一个
@property (nonatomic) uint64_t   cleanableBytes;

@property (nonatomic) NSUInteger screenshotCount;
@property (nonatomic) uint64_t   screenshotBytes;

@property (nonatomic) NSUInteger screenRecordingCount;
@property (nonatomic) uint64_t   screenRecordingBytes;

@property (nonatomic) NSUInteger bigVideoCount;   // >20MB
@property (nonatomic) uint64_t   bigVideoBytes;

@property (nonatomic) NSUInteger duplicateGroupCount;
@property (nonatomic) NSUInteger similarGroupCount;

@property (nonatomic) NSUInteger blurryCount;
@property (nonatomic) uint64_t   blurryBytes;

@property (nonatomic) NSUInteger otherCount;
@property (nonatomic) uint64_t   otherBytes;

@property (nonatomic, strong) NSDate *lastUpdated;
@property (nonatomic, strong, nullable) NSData *phash256Data;

@end

@interface ASAssetModel : NSObject <NSSecureCoding>
@property (nonatomic, assign) float blurScore; // 越小越模糊（Tenengrad）
@property (nonatomic, copy) NSString *localId;
@property (nonatomic) PHAssetMediaType mediaType;
@property (nonatomic) PHAssetMediaSubtype subtypes;

@property (nonatomic, strong, nullable) NSDate *creationDate;
@property (nonatomic, strong, nullable) NSDate *modificationDate;

@property (nonatomic) uint64_t fileSizeBytes;

@property (nonatomic, strong, nullable) NSData *phash256Data;

@property (nonatomic) uint64_t pHash;
@property (nonatomic, strong, nullable) NSData *visionPrintData;
@end

@interface ASAssetGroup : NSObject <NSSecureCoding>
@property (nonatomic) ASGroupType type;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *assets;
@end

typedef void(^ASScanProgressBlock)(ASScanSnapshot *snapshot);
typedef void(^ASScanCompletionBlock)(ASScanSnapshot *snapshot, NSError *_Nullable error);

@interface ASPhotoScanManager : NSObject <PHPhotoLibraryChangeObserver>

@property (nonatomic, readonly) ASScanSnapshot *snapshot;

@property (nonatomic, readonly) NSArray<ASAssetGroup *> *duplicateGroups;
@property (nonatomic, readonly) NSArray<ASAssetGroup *> *similarGroups;
@property (nonatomic, readonly) NSArray<ASAssetModel *> *screenshots;
@property (nonatomic, readonly) NSArray<ASAssetModel *> *screenRecordings;
@property (nonatomic, readonly) NSArray<ASAssetModel *> *bigVideos;
@property (nonatomic, readonly) NSArray<ASAssetModel *> *blurryPhotos;
@property (nonatomic, readonly) NSArray<ASAssetModel *> *otherPhotos;

/// 手动触发一次「删除资产清理 + 重新统计 + 保存缓存」
///（可用于你想显式做一次 purge 的场景）
- (void)purgeDeletedAssetsAndRecalculate;

+ (instancetype)shared;
- (BOOL)isCacheValid;

// 启动：读取缓存 + 检测是否需要增量更新（杀死App后也能）
- (void)loadCacheAndCheckIncremental;

// 全量扫描（从最新到最远）
- (void)startFullScanWithProgress:(ASScanProgressBlock)progress
                       completion:(ASScanCompletionBlock)completion;

// 停止扫描（中断）
- (void)cancel;
- (void)subscribeProgress:(ASScanProgressBlock)progress;

// 选择相关：只提供“可清理全选/反选”，其他类别是真全选
- (NSArray<ASAssetModel *> *)allCleanableAssets;     // 相似/重复每组除第一个
- (NSArray<ASAssetModel *> *)allScreenshotAssets;
- (NSArray<ASAssetModel *> *)allScreenRecordingAssets;
- (NSArray<ASAssetModel *> *)allBigVideoAssets;

@end

NS_ASSUME_NONNULL_END
