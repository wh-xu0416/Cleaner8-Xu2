#import "SwipeManager.h"
#import <UIKit/UIKit.h>

NSString * const SwipeManagerDidUpdateNotification = @"SwipeManagerDidUpdateNotification";

#pragma mark - SwipeModule

@implementation SwipeModule

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.moduleID forKey:@"moduleID"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.subtitle forKey:@"subtitle"];
    [coder encodeObject:self.assetIDs forKey:@"assetIDs"];
    [coder encodeBool:self.sortAscending forKey:@"sortAscending"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        self.type = [coder decodeIntegerForKey:@"type"];
        self.moduleID = [coder decodeObjectOfClass:NSString.class forKey:@"moduleID"] ?: @"";
        self.title = [coder decodeObjectOfClass:NSString.class forKey:@"title"] ?: @"";
        self.subtitle = [coder decodeObjectOfClass:NSString.class forKey:@"subtitle"] ?: @"";
        self.assetIDs = [coder decodeObjectOfClasses:[NSSet setWithArray:@[NSArray.class, NSString.class]] forKey:@"assetIDs"] ?: @[];
        self.sortAscending = [coder decodeBoolForKey:@"sortAscending"];
    }
    return self;
}

@end

#pragma mark - Undo record (private)

@interface SwipeUndoRecord : NSObject
@property (nonatomic, copy) NSString *assetID;
@property (nonatomic, assign) SwipeAssetStatus previousStatus;
@end

@implementation SwipeUndoRecord
@end

#pragma mark - SwipeManager

@interface SwipeManager ()
// moduleID -> 当前待处理(未处理)的 assetID（用于下次继续）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *moduleCursorAssetIDByID;

@property (nonatomic, strong) NSMutableArray<SwipeModule *> *mutableModules;

// 状态：assetID -> status
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByAssetID;

// 尺寸缓存：assetID -> bytes（仅对已归档的有意义）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *bytesByAssetID;

// 模块排序偏好：moduleID -> BOOL
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *moduleSortAscendingByID;

// 随机20固定选择（持久化）
@property (nonatomic, strong) NSMutableArray<NSString *> *random20AssetIDs;

// moduleID -> undo stack
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SwipeUndoRecord *> *> *undoStacks;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) dispatch_queue_t stateQueue;

@property (nonatomic, assign) unsigned long long archivedBytesCached;
@property (nonatomic, assign) BOOL isReloading;
@property (nonatomic, assign) BOOL didRegisterObserver;
@end

@implementation SwipeManager

+ (instancetype)shared {
    static SwipeManager *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[SwipeManager alloc] initPrivate];
    });
    return mgr;
}

- (instancetype)init { @throw [NSException exceptionWithName:@"Singleton" reason:@"Use +shared" userInfo:nil]; }

- (instancetype)initPrivate {
    if ((self = [super init])) {
        _moduleCursorAssetIDByID = [NSMutableDictionary dictionary];
        _mutableModules = [NSMutableArray array];
        _statusByAssetID = [NSMutableDictionary dictionary];
        _bytesByAssetID = [NSMutableDictionary dictionary];
        _moduleSortAscendingByID = [NSMutableDictionary dictionary];
        _random20AssetIDs = [NSMutableArray array];
        _undoStacks = [NSMutableDictionary dictionary];
        _imageManager = [[PHCachingImageManager alloc] init];
        _stateQueue = dispatch_queue_create("swipe.manager.state.queue", DISPATCH_QUEUE_SERIAL);

        [self loadStateFromDisk];
    }
    return self;
}

- (NSArray<SwipeModule *> *)modules {
    return self.mutableModules.copy;
}

#pragma mark - Authorization & Load

- (void)requestAuthorizationAndLoadIfNeeded:(void(^)(BOOL granted))completion {
    void (^afterAuth)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status){
        BOOL granted = (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
        if (granted) {
            [self ensurePhotoLibraryObserver];
            [self reloadModules];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(granted);
            });
        }
    };

    if (@available(iOS 14, *)) {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (s == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:afterAuth];
        } else {
            afterAuth(s);
        }
    } else {
        PHAuthorizationStatus s = [PHPhotoLibrary authorizationStatus];
        if (s == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:afterAuth];
        } else {
            afterAuth(s);
        }
    }
}

- (void)ensurePhotoLibraryObserver {
    if (self.didRegisterObserver) return;
    self.didRegisterObserver = YES;
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

#pragma mark - Persistence

- (NSString *)stateFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"swipe.app";
    NSString *folder = [dir stringByAppendingPathComponent:bundle];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder stringByAppendingPathComponent:@"swipe_state.dat"];
}

- (void)loadStateFromDisk {
    NSData *data = [NSData dataWithContentsOfFile:[self stateFilePath]];
    if (!data) return;

    NSError *err = nil;
    NSSet *classes = [NSSet setWithArray:@[
        NSDictionary.class, NSArray.class, NSString.class, NSNumber.class
    ]];

    NSDictionary *state = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&err];
    if (![state isKindOfClass:NSDictionary.class] || err) return;

    NSDictionary *status = state[@"statusByAssetID"];
    NSDictionary *bytes  = state[@"bytesByAssetID"];
    NSDictionary *sorts  = state[@"moduleSortAscendingByID"];
    NSArray *random20    = state[@"random20AssetIDs"];
    NSNumber *archBytes  = state[@"archivedBytesCached"];

    NSDictionary *cursor = state[@"moduleCursorAssetIDByID"];   // ✅ 新增
    NSDictionary *undo   = state[@"undoStacksByModuleID"];      // ✅ 新增（序列化形式）

    if ([status isKindOfClass:NSDictionary.class]) self.statusByAssetID = status.mutableCopy;
    if ([bytes isKindOfClass:NSDictionary.class]) self.bytesByAssetID = bytes.mutableCopy;
    if ([sorts isKindOfClass:NSDictionary.class]) self.moduleSortAscendingByID = sorts.mutableCopy;
    if ([random20 isKindOfClass:NSArray.class]) self.random20AssetIDs = random20.mutableCopy;
    if ([archBytes isKindOfClass:NSNumber.class]) self.archivedBytesCached = archBytes.unsignedLongLongValue;

    if ([cursor isKindOfClass:NSDictionary.class]) {
        self.moduleCursorAssetIDByID = cursor.mutableCopy;
    }

    // undo stacks 反序列化：moduleID -> [ {assetID, prevStatus} ... ]
    if ([undo isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *stacks = [NSMutableDictionary dictionary];
        [undo enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            if (![obj isKindOfClass:NSArray.class]) return;
            NSMutableArray<SwipeUndoRecord *> *stack = [NSMutableArray array];
            for (id item in (NSArray *)obj) {
                if (![item isKindOfClass:NSDictionary.class]) continue;
                NSString *aid = item[@"assetID"];
                NSNumber *prev = item[@"prevStatus"];
                if (![aid isKindOfClass:NSString.class] || ![prev isKindOfClass:NSNumber.class]) continue;
                SwipeUndoRecord *r = [SwipeUndoRecord new];
                r.assetID = aid;
                r.previousStatus = (SwipeAssetStatus)prev.integerValue;
                [stack addObject:r];
            }
            if (stack.count > 0) stacks[key] = stack;
        }];
        self.undoStacks = stacks;
    }
}

- (void)saveStateToDisk {
    dispatch_async(self.stateQueue, ^{
        // undo stacks 序列化
        NSMutableDictionary *undoSer = [NSMutableDictionary dictionary];
        [self.undoStacks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<SwipeUndoRecord *> *stack, BOOL *stop) {
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:stack.count];
            for (SwipeUndoRecord *r in stack) {
                if (!r.assetID) continue;
                [arr addObject:@{@"assetID": r.assetID, @"prevStatus": @(r.previousStatus)}];
            }
            if (arr.count > 0) undoSer[key] = arr;
        }];

        NSDictionary *state = @{
            @"statusByAssetID": self.statusByAssetID ?: @{},
            @"bytesByAssetID": self.bytesByAssetID ?: @{},
            @"moduleSortAscendingByID": self.moduleSortAscendingByID ?: @{},
            @"random20AssetIDs": self.random20AssetIDs ?: @[],
            @"archivedBytesCached": @(self.archivedBytesCached),

            // ✅ 新增
            @"moduleCursorAssetIDByID": self.moduleCursorAssetIDByID ?: @{},
            @"undoStacksByModuleID": undoSer ?: @{},
        };

        NSError *err = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:NO error:&err];
        if (data && !err) {
            [data writeToFile:[self stateFilePath] atomically:YES];
        }
    });
}

- (nullable NSString *)currentUnprocessedAssetIDForModuleID:(NSString *)moduleID {
    if (!moduleID.length) return nil;
    return self.moduleCursorAssetIDByID[moduleID];
}

- (void)setCurrentUnprocessedAssetID:(nullable NSString *)assetID forModuleID:(NSString *)moduleID {
    if (!moduleID.length) return;

    if (assetID.length == 0) {
        [self.moduleCursorAssetIDByID removeObjectForKey:moduleID];
    } else {
        self.moduleCursorAssetIDByID[moduleID] = assetID;
    }
    [self saveStateToDisk];
}

#pragma mark - Core scan & modules

- (PHFetchResult<PHAsset *> *)fetchAllImageAssets {
    PHFetchOptions *opt = [[PHFetchOptions alloc] init];
    opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    opt.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    return [PHAsset fetchAssetsWithOptions:opt];
}

- (NSArray<NSString *> *)assetIDsFromFetchResult:(PHFetchResult<PHAsset *> *)result {
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:result.count];
    [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier) [ids addObject:obj.localIdentifier];
    }];
    return ids.copy;
}

- (void)reloadModules {
    if (self.isReloading) return;
    self.isReloading = YES;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        PHFetchResult<PHAsset *> *all = [self fetchAllImageAssets];
        NSArray<NSString *> *allIDs = [self assetIDsFromFetchResult:all];
        NSSet *allIDSet = [NSSet setWithArray:allIDs];

        // 1) 清理状态：相册已删除的asset
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
            if (![allIDSet containsObject:key]) [toRemove addObject:key];
        }];
        for (NSString *aid in toRemove) {
            [self.statusByAssetID removeObjectForKey:aid];
            [self.bytesByAssetID removeObjectForKey:aid];
            [self.random20AssetIDs removeObject:aid];
        }
        
        // 清理 moduleCursor：相册删除导致指向无效 asset
        NSMutableArray *cursorKeysToRemove = [NSMutableArray array];
        [self.moduleCursorAssetIDByID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
            if (![allIDSet containsObject:obj]) [cursorKeysToRemove addObject:key];
        }];
        for (NSString *k in cursorKeysToRemove) {
            [self.moduleCursorAssetIDByID removeObjectForKey:k];
        }

        // 清理 undoStacks：去掉已不存在 asset 的记录
        NSMutableArray *moduleKeysToRemove = [NSMutableArray array];
        [self.undoStacks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<SwipeUndoRecord *> *stack, BOOL *stop) {
            NSIndexSet *bad = [stack indexesOfObjectsPassingTest:^BOOL(SwipeUndoRecord * _Nonnull r, NSUInteger idx, BOOL * _Nonnull stop2) {
                return !r.assetID || ![allIDSet containsObject:r.assetID];
            }];
            if (bad.count > 0) [stack removeObjectsAtIndexes:bad];
            if (stack.count == 0) [moduleKeysToRemove addObject:key];
        }];
        for (NSString *k in moduleKeysToRemove) {
            [self.undoStacks removeObjectForKey:k];
        }

        // 2) 生成模块
        NSMutableArray<SwipeModule *> *modules = [NSMutableArray array];

        // 最近7天：每天一个模块
        {
            NSCalendar *cal = [NSCalendar currentCalendar];
            NSDate *now = [NSDate date];
            for (NSInteger i = 0; i < 7; i++) {
                NSDate *day = [cal dateByAddingUnit:NSCalendarUnitDay value:-i toDate:now options:0];
                NSDateComponents *c = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:day];

                NSDate *start = [cal dateFromComponents:c];
                NSDateComponents *c2 = [NSDateComponents new];
                c2.day = 1;
                NSDate *end = [cal dateByAddingComponents:c2 toDate:start options:0];

                PHFetchOptions *opt = [PHFetchOptions new];
                opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
                opt.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                                 PHAssetMediaTypeImage, start, end];
                PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithOptions:opt];
                if (r.count == 0) continue;

                SwipeModule *m = [SwipeModule new];
                m.type = SwipeModuleTypeRecentDay;

                NSString *ymd = [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)c.year, (long)c.month, (long)c.day];
                m.moduleID = [@"day_" stringByAppendingString:ymd];

                m.title = @"最近";
                m.subtitle = ymd;
                m.assetIDs = [self assetIDsFromFetchResult:r];

                NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
                m.sortAscending = sortPref ? sortPref.boolValue : NO;

                [modules addObject:[self moduleByApplyingSort:m]];
            }
        }

        // 每月一个模块
        {
            // 遍历 all（creationDate 降序）
            NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *bucket = [NSMutableDictionary dictionary];
            NSCalendar *cal = [NSCalendar currentCalendar];

            [all enumerateObjectsUsingBlock:^(PHAsset * _Nonnull asset, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDate *d = asset.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
                NSDateComponents *c = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:d];
                NSString *key = [NSString stringWithFormat:@"%04ld-%02ld", (long)c.year, (long)c.month];
                if (!bucket[key]) bucket[key] = [NSMutableArray array];
                [bucket[key] addObject:asset.localIdentifier];
            }];

            // key 按年月降序
            NSArray *keys = [[bucket allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                return [b compare:a]; // 降序
            }];

            for (NSString *key in keys) {
                NSArray *ids = bucket[key].copy;
                if (ids.count == 0) continue;

                SwipeModule *m = [SwipeModule new];
                m.type = SwipeModuleTypeMonth;
                m.moduleID = [@"month_" stringByAppendingString:key];
                m.title = @"月份";
                m.subtitle = key;
                m.assetIDs = ids;

                NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
                m.sortAscending = sortPref ? sortPref.boolValue : NO;

                [modules addObject:[self moduleByApplyingSort:m]];
            }
        }

        // 随机20：持久化固定选择；不足补齐
        {
            SwipeModule *m = [SwipeModule new];
            m.type = SwipeModuleTypeRandom20;
            m.moduleID = @"random20";
            m.title = @"随机";
            m.subtitle = @"20张";

            // 先过滤掉已不存在的
            NSMutableArray<NSString *> *valid = [NSMutableArray array];
            for (NSString *aid in self.random20AssetIDs) {
                if ([allIDSet containsObject:aid]) [valid addObject:aid];
            }
            self.random20AssetIDs = valid;

            // 补齐到20
            if (self.random20AssetIDs.count < 20 && allIDs.count > 0) {
                NSMutableSet *used = [NSMutableSet setWithArray:self.random20AssetIDs];
                NSUInteger tries = 0;
                while (self.random20AssetIDs.count < 20 && tries < allIDs.count * 3) {
                    tries++;
                    NSString *pick = allIDs[arc4random_uniform((u_int32_t)allIDs.count)];
                    if (![used containsObject:pick]) {
                        [used addObject:pick];
                        [self.random20AssetIDs addObject:pick];
                    }
                }
            }

            m.assetIDs = self.random20AssetIDs.copy;

            NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
            m.sortAscending = sortPref ? sortPref.boolValue : NO;

            [modules addObject:[self moduleByApplyingSort:m]];
        }

        // 自拍模块
        {
            PHFetchResult<PHAssetCollection *> *selfies =
            [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum
                                                    subtype:PHAssetCollectionSubtypeSmartAlbumSelfPortraits
                                                    options:nil];

            PHAssetCollection *selfieAlbum = selfies.firstObject;
            if (selfieAlbum) {
                PHFetchOptions *opt = [PHFetchOptions new];
                opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
                PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsInAssetCollection:selfieAlbum options:opt];

                SwipeModule *m = [SwipeModule new];
                m.type = SwipeModuleTypeSelfie;
                m.moduleID = @"selfie";
                m.title = @"自拍";
                m.subtitle = @"Selfies";
                m.assetIDs = [self assetIDsFromFetchResult:r];

                NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
                m.sortAscending = sortPref ? sortPref.boolValue : NO;

                if (m.assetIDs.count > 0) {
                    [modules addObject:[self moduleByApplyingSort:m]];
                }
            }
        }

        // 3) 写回 & 通知
        dispatch_async(dispatch_get_main_queue(), ^{
            self.mutableModules = modules;
            self.isReloading = NO;

            [self saveStateToDisk];
            [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
        });
    });
}

- (SwipeModule *)moduleByApplyingSort:(SwipeModule *)module {
    // module.assetIDs 默认常为 creationDate 降序（我们构造时就是）
    // 若需要升序则翻转
    if (module.sortAscending) {
        module.assetIDs = [[module.assetIDs reverseObjectEnumerator] allObjects];
    }
    return module;
}

#pragma mark - Status

- (SwipeAssetStatus)statusForAssetID:(NSString *)assetID {
    NSNumber *n = self.statusByAssetID[assetID];
    if (!n) return SwipeAssetStatusUnknown;
    return (SwipeAssetStatus)n.integerValue;
}

- (void)setStatus:(SwipeAssetStatus)status
      forAssetID:(NSString *)assetID
     sourceModule:(nullable NSString *)moduleID
       recordUndo:(BOOL)recordUndo {

    SwipeAssetStatus prev = [self statusForAssetID:assetID];
    if (prev == status) return;

    // undo record
    if (recordUndo && moduleID.length > 0) {
        NSMutableArray *stack = self.undoStacks[moduleID];
        if (!stack) {
            stack = [NSMutableArray array];
            self.undoStacks[moduleID] = stack;
        }
        SwipeUndoRecord *r = [SwipeUndoRecord new];
        r.assetID = assetID;
        r.previousStatus = prev;
        [stack addObject:r];
    }

    // archived bytes cache update (去重：只要状态切换成 Archived 才计入；切出 Archived 则扣除)
    if (prev == SwipeAssetStatusArchived && status != SwipeAssetStatusArchived) {
        NSNumber *b = self.bytesByAssetID[assetID];
        if (b) {
            unsigned long long v = b.unsignedLongLongValue;
            if (self.archivedBytesCached >= v) self.archivedBytesCached -= v;
            [self.bytesByAssetID removeObjectForKey:assetID];
        }
    } else if (prev != SwipeAssetStatusArchived && status == SwipeAssetStatusArchived) {
        // 计算当前 asset 大小并加入缓存（同步尽量快；失败再异步补齐）
        unsigned long long bytes = [self quickAssetBytes:assetID];
        if (bytes > 0) {
            self.bytesByAssetID[assetID] = @(bytes);
            self.archivedBytesCached += bytes;
        } else {
            // 先不加，异步 refresh 时补齐
        }
    }

    self.statusByAssetID[assetID] = @(status);

    [self saveStateToDisk];
    [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
}

- (void)resetStatusForAssetID:(NSString *)assetID sourceModule:(nullable NSString *)moduleID recordUndo:(BOOL)recordUndo {
    [self setStatus:SwipeAssetStatusUnknown forAssetID:assetID sourceModule:moduleID recordUndo:recordUndo];
}

- (BOOL)undoLastActionInModuleID:(NSString *)moduleID {
    NSMutableArray<SwipeUndoRecord *> *stack = self.undoStacks[moduleID];
    SwipeUndoRecord *last = stack.lastObject;
    if (!last) return NO;

    [stack removeLastObject];
    [self setStatus:last.previousStatus forAssetID:last.assetID sourceModule:nil recordUndo:NO];
    return YES;
}

#pragma mark - Sorting pref

- (void)setSortAscending:(BOOL)ascending forModuleID:(NSString *)moduleID {
    if (!moduleID.length) return;
    self.moduleSortAscendingByID[moduleID] = @(ascending);
    [self saveStateToDisk];
}

#pragma mark - Module progress

- (NSUInteger)totalCountInModule:(SwipeModule *)module {
    return module.assetIDs.count;
}

- (NSUInteger)processedCountInModule:(SwipeModule *)module {
    __block NSUInteger count = 0;
    for (NSString *aid in module.assetIDs) {
        if ([self statusForAssetID:aid] != SwipeAssetStatusUnknown) count++;
    }
    return count;
}

- (NSUInteger)archivedCountInModule:(SwipeModule *)module {
    __block NSUInteger count = 0;
    for (NSString *aid in module.assetIDs) {
        if ([self statusForAssetID:aid] == SwipeAssetStatusArchived) count++;
    }
    return count;
}

- (BOOL)isModuleCompleted:(SwipeModule *)module {
    if (module.assetIDs.count == 0) return YES;
    return [self processedCountInModule:module] == module.assetIDs.count;
}

#pragma mark - Global progress

- (NSUInteger)totalAssetCount {
    PHFetchResult<PHAsset *> *all = [self fetchAllImageAssets];
    return all.count;
}

- (NSUInteger)totalProcessedCount {
    // 只统计仍存在的图片
    PHFetchResult<PHAsset *> *all = [self fetchAllImageAssets];
    NSMutableSet *allSet = [NSMutableSet setWithCapacity:all.count];
    [all enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier) [allSet addObject:obj.localIdentifier];
    }];

    __block NSUInteger count = 0;
    [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
        if ([allSet containsObject:key] && obj.integerValue != SwipeAssetStatusUnknown) count++;
    }];
    return count;
}

- (NSUInteger)totalArchivedCount {
    __block NSUInteger count = 0;
    [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
        if (obj.integerValue == SwipeAssetStatusArchived) count++;
    }];
    return count;
}

- (unsigned long long)totalArchivedBytesCached {
    return self.archivedBytesCached;
}

- (NSSet<NSString *> *)archivedAssetIDSet {
    NSMutableSet *set = [NSMutableSet set];
    [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
        if (obj.integerValue == SwipeAssetStatusArchived) [set addObject:key];
    }];
    return set.copy;
}

#pragma mark - Asset fetching

- (nullable PHAsset *)assetForID:(NSString *)assetID {
    if (!assetID.length) return nil;
    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetID] options:nil];
    return r.firstObject;
}

- (NSArray<PHAsset *> *)assetsForIDs:(NSArray<NSString *> *)assetIDs {
    if (assetIDs.count == 0) return @[];
    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:assetIDs options:nil];
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:r.count];
    [r enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [arr addObject:obj];
    }];
    return arr.copy;
}

#pragma mark - Bytes helper

/// 尝试快速获取 asset bytes（优先走 PHAssetResource KVC：不保证所有系统都可用；失败返回0）
- (unsigned long long)quickAssetBytes:(NSString *)assetID {
    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return 0;

    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    if (resources.count == 0) return 0;

    // 一般第一项是主资源
    PHAssetResource *res = resources.firstObject;
    @try {
        // 非公开字段，某些版本可用；若不可用会抛异常
        unsigned long long v = [[res valueForKey:@"fileSize"] unsignedLongLongValue];
        return v;
    } @catch (__unused NSException *e) {
        return 0;
    }
}

- (void)refreshArchivedBytesIfNeeded:(void(^)(unsigned long long bytes))completion {
    // 对已归档但 bytes 缺失的做补齐（可能慢：会读取资源数据）
    NSSet<NSString *> *archived = [self archivedAssetIDSet];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *aid in archived) {
        if (!self.bytesByAssetID[aid]) [missing addObject:aid];
    }

    if (missing.count == 0) {
        if (completion) completion(self.archivedBytesCached);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __block unsigned long long add = 0;

        dispatch_group_t g = dispatch_group_create();
        for (NSString *aid in missing) {
            dispatch_group_enter(g);
            PHAsset *asset = [self assetForID:aid];
            if (!asset) { dispatch_group_leave(g); continue; }

            NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
            PHAssetResource *res = resources.firstObject;
            if (!res) { dispatch_group_leave(g); continue; }

            // 尝试KVC再次读取
            unsigned long long v = 0;
            @try { v = [[res valueForKey:@"fileSize"] unsignedLongLongValue]; } @catch (__unused NSException *e) {}

            if (v > 0) {
                @synchronized (self) {
                    if (!self.bytesByAssetID[aid]) {
                        self.bytesByAssetID[aid] = @(v);
                        add += v;
                    }
                }
                dispatch_group_leave(g);
                continue;
            }

            // fallback：读取数据累计（可能慢）
            __block unsigned long long bytes = 0;
            [[PHAssetResourceManager defaultManager] requestDataForAssetResource:res
                                                                        options:nil
                                                                 dataReceivedHandler:^(NSData * _Nonnull data) {
                bytes += data.length;
            } completionHandler:^(__unused NSError * _Nullable error) {
                if (bytes > 0) {
                    @synchronized (self) {
                        if (!self.bytesByAssetID[aid]) {
                            self.bytesByAssetID[aid] = @(bytes);
                            add += bytes;
                        }
                    }
                }
                dispatch_group_leave(g);
            }];
        }

        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.archivedBytesCached += add;
            [self saveStateToDisk];
            [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
            if (completion) completion(self.archivedBytesCached);
        });
    });
}

#pragma mark - Delete assets

- (void)deleteAssetsWithIDs:(NSArray<NSString *> *)assetIDs completion:(void(^)(BOOL success, NSError * _Nullable error))completion {
    if (assetIDs.count == 0) {
        if (completion) completion(YES, nil);
        return;
    }

    NSArray<PHAsset *> *assets = [self assetsForIDs:assetIDs];
    if (assets.count == 0) {
        // 清理状态
        for (NSString *aid in assetIDs) {
            [self.statusByAssetID removeObjectForKey:aid];
            [self.bytesByAssetID removeObjectForKey:aid];
        }
        [self saveStateToDisk];
        [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
        if (completion) completion(YES, nil);
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            // 状态清理：删除后 change observer 也会触发 reload
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSString *aid in assetIDs) {
                    // 如果删除的是归档的，扣除缓存
                    SwipeAssetStatus prev = [self statusForAssetID:aid];
                    if (prev == SwipeAssetStatusArchived) {
                        NSNumber *b = self.bytesByAssetID[aid];
                        if (b && self.archivedBytesCached >= b.unsignedLongLongValue) {
                            self.archivedBytesCached -= b.unsignedLongLongValue;
                        }
                    }
                    [self.statusByAssetID removeObjectForKey:aid];
                    [self.bytesByAssetID removeObjectForKey:aid];
                    [self.random20AssetIDs removeObject:aid];
                }
                [self saveStateToDisk];
                [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
            });
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }
    }];
}

#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    // 相册变化：增量更新这里简单做全量刷新（你后续可按需细化为增量diff）
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadModules];
    });
}

@end
