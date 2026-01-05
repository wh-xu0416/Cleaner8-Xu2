#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SwipeAssetStatus) {
    SwipeAssetStatusUnknown = 0,   // 未处理
    SwipeAssetStatusKept    = 1,   // 保留（已处理）
    SwipeAssetStatusArchived= 2    // 归档（已处理）
};

typedef NS_ENUM(NSInteger, SwipeModuleType) {
    SwipeModuleTypeRecentDay = 0,
    SwipeModuleTypeMonth     = 1,
    SwipeModuleTypeRandom20  = 2,
    SwipeModuleTypeSelfie    = 3
};

FOUNDATION_EXPORT NSString * const SwipeManagerDidUpdateNotification;

@interface SwipeModule : NSObject <NSSecureCoding>
@property (nonatomic, assign) SwipeModuleType type;
@property (nonatomic, copy) NSString *moduleID;          // 唯一ID，如 day_2026-01-05 / month_2026-01 / random20 / selfie
@property (nonatomic, copy) NSString *title;             // 展示用标题
@property (nonatomic, copy) NSString *subtitle;          // 展示用副标题（日期、年月）
@property (nonatomic, strong) NSArray<NSString *> *assetIDs; // PHAsset.localIdentifier 列表
@property (nonatomic, assign) BOOL sortAscending;        // 按时间升序/降序
@end

@interface SwipeManager : NSObject <PHPhotoLibraryChangeObserver>

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<SwipeModule *> *modules;
/// 模块“处理到哪里了”：记录当前待处理（未处理）的 assetID
- (nullable NSString *)currentUnprocessedAssetIDForModuleID:(NSString *)moduleID;
- (void)setCurrentUnprocessedAssetID:(nullable NSString *)assetID forModuleID:(NSString *)moduleID;

/// 请求权限并加载（会触发扫描/分组/持久化校验）
- (void)requestAuthorizationAndLoadIfNeeded:(void(^)(BOOL granted))completion;

/// 重新扫描并生成模块（内部会清理已不存在的状态、更新随机20）
- (void)reloadModules;

/// 状态读写
- (SwipeAssetStatus)statusForAssetID:(NSString *)assetID;
- (void)setStatus:(SwipeAssetStatus)status
      forAssetID:(NSString *)assetID
     sourceModule:(nullable NSString *)moduleID
       recordUndo:(BOOL)recordUndo;
- (void)resetStatusForAssetID:(NSString *)assetID sourceModule:(nullable NSString *)moduleID recordUndo:(BOOL)recordUndo;

/// 模块进度
- (NSUInteger)totalCountInModule:(SwipeModule *)module;
- (NSUInteger)processedCountInModule:(SwipeModule *)module;
- (NSUInteger)archivedCountInModule:(SwipeModule *)module;
- (BOOL)isModuleCompleted:(SwipeModule *)module;

/// 全局进度
- (NSUInteger)totalAssetCount;
- (NSUInteger)totalProcessedCount;
- (NSUInteger)totalArchivedCount;

/// 归档总大小（去重）— 读取缓存值（归档/撤销时会更新）
- (unsigned long long)totalArchivedBytesCached;

/// 异步刷新归档总大小（对缓存做一次校验/补齐，可能较慢）
- (void)refreshArchivedBytesIfNeeded:(void(^)(unsigned long long bytes))completion;

/// 获取 PHAsset（常用）
- (nullable PHAsset *)assetForID:(NSString *)assetID;
- (NSArray<PHAsset *> *)assetsForIDs:(NSArray<NSString *> *)assetIDs;

/// 模块排序设置（会持久化模块排序偏好）
- (void)setSortAscending:(BOOL)ascending forModuleID:(NSString *)moduleID;

/// 模块 undo：无限撤回（只在内存中维护栈；状态本身会持久化）
- (BOOL)undoLastActionInModuleID:(NSString *)moduleID;

/// 归档资产ID集合（去重）
- (NSSet<NSString *> *)archivedAssetIDSet;

/// 删除资产（从系统相册删除，成功后会清理状态并刷新模块）
- (void)deleteAssetsWithIDs:(NSArray<NSString *> *)assetIDs completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
