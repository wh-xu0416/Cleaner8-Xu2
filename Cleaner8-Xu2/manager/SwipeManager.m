#import "SwipeManager.h"
#import "Common.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

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

@interface SwipeManager () <PHPhotoLibraryChangeObserver>
@property (nonatomic, strong) PHFetchResult<PHAsset *> *allFetchResult;

@property (atomic, assign) BOOL pendingReload;
@property (atomic, assign) BOOL pendingPhotoChange;
@property (nonatomic, assign) BOOL reloadScheduled;   // 防抖：短时间多次 change 合并一次 reload

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *moduleCursorAssetIDByID;

@property (nonatomic, strong) NSMutableArray<SwipeModule *> *mutableModules;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByAssetID;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *bytesByAssetID;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *moduleSortAscendingByID;

@property (nonatomic, strong) NSMutableArray<NSString *> *random20AssetIDs;

@property (nonatomic, strong) NSMutableArray<SwipeUndoRecord *> *undoStack;   // 全局撤回栈（最后一次动作在末尾）

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) dispatch_queue_t stateQueue;

@property (nonatomic, assign) unsigned long long archivedBytesCached;
@property (nonatomic, assign) BOOL isReloading;
@property (nonatomic, assign) BOOL didRegisterObserver;
@property (nonatomic, strong) NSObject *stateLock;
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
        _stateLock = [NSObject new];
        _moduleCursorAssetIDByID = [NSMutableDictionary dictionary];
        _mutableModules = [NSMutableArray array];
        _statusByAssetID = [NSMutableDictionary dictionary];
        _bytesByAssetID = [NSMutableDictionary dictionary];
        _moduleSortAscendingByID = [NSMutableDictionary dictionary];
        _random20AssetIDs = [NSMutableArray array];
        _undoStack = [NSMutableArray array];
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

    NSDictionary *cursor = state[@"moduleCursorAssetIDByID"];

    if ([status isKindOfClass:NSDictionary.class]) self.statusByAssetID = status.mutableCopy;
    if ([bytes isKindOfClass:NSDictionary.class]) self.bytesByAssetID = bytes.mutableCopy;
    if ([sorts isKindOfClass:NSDictionary.class]) self.moduleSortAscendingByID = sorts.mutableCopy;
    if ([random20 isKindOfClass:NSArray.class]) self.random20AssetIDs = random20.mutableCopy;
    if ([archBytes isKindOfClass:NSNumber.class]) self.archivedBytesCached = archBytes.unsignedLongLongValue;

    if ([cursor isKindOfClass:NSDictionary.class]) {
        self.moduleCursorAssetIDByID = cursor.mutableCopy;
    }

    id undoObj = state[@"undoStack"];
    if ([undoObj isKindOfClass:NSArray.class]) {
        NSMutableArray<SwipeUndoRecord *> *stack = [NSMutableArray array];
        for (id item in (NSArray *)undoObj) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *aid = item[@"assetID"];
            NSNumber *prev = item[@"prevStatus"];
            if (![aid isKindOfClass:NSString.class] || ![prev isKindOfClass:NSNumber.class]) continue;

            SwipeUndoRecord *r = [SwipeUndoRecord new];
            r.assetID = aid;
            r.previousStatus = (SwipeAssetStatus)prev.integerValue;
            [stack addObject:r];
        }
        self.undoStack = stack;
    } else {
        // 旧版本里是按模块存的 undoStacksByModuleID
        // 因为旧数据没有时间顺序信息，无法可靠恢复“全局最后一步”的顺序
        // 最安全：直接清空（升级后撤回历史重置一次）
        self.undoStack = [NSMutableArray array];
    }
}

- (void)saveStateToDisk {
    dispatch_async(self.stateQueue, ^{

        NSDictionary *statusSnap = nil;
        NSDictionary *bytesSnap  = nil;
        NSDictionary *sortSnap   = nil;
        NSArray      *randomSnap = nil;
        NSDictionary *cursorSnap = nil;
        NSNumber     *archSnap   = nil;
        NSDictionary *undoSerSnap = nil;
        NSArray *undoSnap = nil;

        @synchronized (self.stateLock) {
            statusSnap = [self.statusByAssetID copy] ?: @{};
            bytesSnap  = [self.bytesByAssetID copy] ?: @{};
            sortSnap   = [self.moduleSortAscendingByID copy] ?: @{};
            randomSnap = [self.random20AssetIDs copy] ?: @[];
            cursorSnap = [self.moduleCursorAssetIDByID copy] ?: @{};
            archSnap   = @(self.archivedBytesCached);


            NSArray *stackSnap = [self.undoStack copy] ?: @[];
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:stackSnap.count];
            for (SwipeUndoRecord *r in stackSnap) {
                if (!r.assetID) continue;
                [arr addObject:@{@"assetID": r.assetID, @"prevStatus": @(r.previousStatus)}];
            }
            undoSnap = [arr copy] ?: @[];
        }

        NSDictionary *state = @{
            @"statusByAssetID": statusSnap,
            @"bytesByAssetID": bytesSnap,
            @"moduleSortAscendingByID": sortSnap,
            @"random20AssetIDs": randomSnap,
            @"archivedBytesCached": archSnap,
            @"moduleCursorAssetIDByID": cursorSnap,
            @"undoStack": undoSnap,
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

    @synchronized (self.stateLock) {
        if (assetID.length == 0) {
            [self.moduleCursorAssetIDByID removeObjectForKey:moduleID];
        } else {
            self.moduleCursorAssetIDByID[moduleID] = assetID;
        }
    }
    [self saveStateToDisk];
}

#pragma mark - Title / Subtitle helpers

- (NSString *)dayTitleForDate:(NSDate *)date calendar:(NSCalendar *)cal weekdayFormatter:(NSDateFormatter *)weekdayFmt {
    if ([cal isDateInToday:date]) return NSLocalizedString(@"Today", nil);
    if ([cal isDateInYesterday:date]) return NSLocalizedString(@"Yesterday", nil);
    return [weekdayFmt stringFromDate:date]; // e.g. Wednesday
}

- (NSString *)daySubtitleForDate:(NSDate *)date shortDateFormatter:(NSDateFormatter *)shortFmt {
    return [shortFmt stringFromDate:date];   // e.g. Jan 5
}

- (NSString *)monthTitleForYear:(NSInteger)year month:(NSInteger)month calendar:(NSCalendar *)cal monthFormatter:(NSDateFormatter *)monthFmt {
    NSDateComponents *dc = [NSDateComponents new];
    dc.year = year;
    dc.month = month;
    dc.day = 1;
    NSDate *d = [cal dateFromComponents:dc];

    NSString *m = [monthFmt stringFromDate:d]; // e.g. Dec
    if (![m hasSuffix:@"."]) m = [m stringByAppendingString:@"."]; // Dec.
    return m;
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
    @synchronized (self.stateLock) {
        if (self.isReloading) {
            self.pendingReload = YES;
            return;
        }
        self.isReloading = YES;
    }
   
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<SwipeModule *> *modules = [NSMutableArray array];

            @synchronized (self.stateLock) {
                PHFetchResult<PHAsset *> *all = [self fetchAllImageAssets];
                NSArray<NSString *> *allIDs = [self assetIDsFromFetchResult:all];
                NSSet *allIDSet = [NSSet setWithArray:allIDs];

                // 如果你确实需要缓存 fetchResult，放在 lock 内写
                self.allFetchResult = all;

                // 1) 清理状态：相册已删除的asset
                NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
                [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
                    if (![allIDSet containsObject:key]) [toRemove addObject:key];
                }];
                for (NSString *aid in toRemove) {
                    SwipeAssetStatus st = (SwipeAssetStatus)self.statusByAssetID[aid].integerValue;

                    if (st == SwipeAssetStatusArchived) {
                        NSNumber *b = self.bytesByAssetID[aid];
                        if (b) {
                            unsigned long long v = b.unsignedLongLongValue;
                            if (self.archivedBytesCached >= v) self.archivedBytesCached -= v;
                        }
                        // bytesByAssetID 后面也会 remove
                    }

                    [self.statusByAssetID removeObjectForKey:aid];
                    [self.bytesByAssetID removeObjectForKey:aid];
                    [self.random20AssetIDs removeObject:aid];
                }

                // 清理 moduleCursor
                NSMutableArray *cursorKeysToRemove = [NSMutableArray array];
                [self.moduleCursorAssetIDByID enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
                    if (![allIDSet containsObject:obj]) [cursorKeysToRemove addObject:key];
                }];
                for (NSString *k in cursorKeysToRemove) {
                    [self.moduleCursorAssetIDByID removeObjectForKey:k];
                }

                // 清理 undoStack：移除相册已不存在的 asset
                NSIndexSet *bad = [self.undoStack indexesOfObjectsPassingTest:^BOOL(SwipeUndoRecord *r, NSUInteger idx, BOOL *stop) {
                    return (r.assetID.length == 0) || ![allIDSet containsObject:r.assetID];
                }];
                if (bad.count > 0) {
                    [self.undoStack removeObjectsAtIndexes:bad];
                }

        // 最近7天：每天一个模块
            {
                NSCalendar *cal = [NSCalendar currentCalendar];
                NSDate *now = [NSDate date];

                NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

                NSDateFormatter *weekdayFmt = [NSDateFormatter new];
                weekdayFmt.locale = en;
                weekdayFmt.dateFormat = @"EEEE"; // Wednesday

                NSDateFormatter *shortDateFmt = [NSDateFormatter new];
                shortDateFmt.locale = en;
                shortDateFmt.dateFormat = @"MMM d"; // Jan 5

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

                    m.title = [self dayTitleForDate:day calendar:cal weekdayFormatter:weekdayFmt]; // Today/Yesterday/Wednesday
                    m.subtitle = ymd;
                    m.assetIDs = [self assetIDsFromFetchResult:r];

                    NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
                    m.sortAscending = sortPref ? sortPref.boolValue : NO;

                    [modules addObject:[self moduleByApplyingSort:m]];
                }
            }


        // 每月一个模块
            {
                NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *bucket = [NSMutableDictionary dictionary];
                NSCalendar *cal = [NSCalendar currentCalendar];

                NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

                NSDateFormatter *monthFmt = [NSDateFormatter new];
                monthFmt.locale = en;
                monthFmt.dateFormat = @"MMM"; // Dec

                [all enumerateObjectsUsingBlock:^(PHAsset * _Nonnull asset, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSDate *d = asset.creationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
                    NSDateComponents *c = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:d];
                    NSString *key = [NSString stringWithFormat:@"%04ld-%02ld", (long)c.year, (long)c.month];
                    if (!bucket[key]) bucket[key] = [NSMutableArray array];
                    [bucket[key] addObject:asset.localIdentifier];
                }];

                NSArray *keys = [[bucket allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                    return [b compare:a]; // 降序
                }];

                for (NSString *key in keys) {
                    NSArray *ids = bucket[key].copy;
                    if (ids.count == 0) continue;

                    // 从 "YYYY-MM" 解析 year/month
                    NSArray<NSString *> *parts = [key componentsSeparatedByString:@"-"];
                    NSInteger year = parts.count > 0 ? parts[0].integerValue : 1970;
                    NSInteger month = parts.count > 1 ? parts[1].integerValue : 1;

                    SwipeModule *m = [SwipeModule new];
                    m.type = SwipeModuleTypeMonth;
                    m.moduleID = [@"month_" stringByAppendingString:key];

                    m.title = [self monthTitleForYear:year month:month calendar:cal monthFormatter:monthFmt];
                    m.subtitle = [NSString stringWithFormat:@"%ld", (long)year];

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
            m.moduleID = @"Random";
            m.title = NSLocalizedString(@"Random", nil);
            m.subtitle = NSLocalizedString(@"Random", nil);

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
                m.moduleID = @"Selfies";
                m.title = NSLocalizedString(@"Selfies", nil);
                m.subtitle = NSLocalizedString(@"Selfies", nil);
                m.assetIDs = [self assetIDsFromFetchResult:r];

                NSNumber *sortPref = self.moduleSortAscendingByID[m.moduleID];
                m.sortAscending = sortPref ? sortPref.boolValue : NO;

                if (m.assetIDs.count > 0) {
                    [modules addObject:[self moduleByApplyingSort:m]];
                }
            }
        }

                [self normalizeArchivedBytesCacheLocked];

        // 3) 写回 & 通知
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.mutableModules = modules;

                    BOOL needAgain = NO;
                    @synchronized (self.stateLock) {
                        self.isReloading = NO;
                        needAgain = self.pendingReload;
                        self.pendingReload = NO;
                    }

                    [self saveStateToDisk];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification
                                                                        object:self];

                    if (needAgain) {
                        [self scheduleReloadModules];
                    }
                });
        }

    });
}

- (unsigned long long)archivedBytesInModule:(SwipeModule *)module {
    if (!module) return 0;

    unsigned long long sum = 0;
    for (NSString *aid in module.assetIDs) {
        if ([self statusForAssetID:aid] != SwipeAssetStatusArchived) continue;

        NSNumber *b = self.bytesByAssetID[aid];
        if (b) {
            sum += b.unsignedLongLongValue;
        } else {
            unsigned long long v = [self quickAssetBytes:aid];
            if (v > 0) {
                self.bytesByAssetID[aid] = @(v);
                sum += v;
            }
        }
    }
    return sum;
}

- (SwipeModule *)moduleByApplyingSort:(SwipeModule *)module {
    if (module.sortAscending) {
        module.assetIDs = [[module.assetIDs reverseObjectEnumerator] allObjects];
    }
    return module;
}

#pragma mark - Recover (Selected)

- (void)recoverAssetIDsToUnprocessed:(NSArray<NSString *> *)assetIDs {
    if (assetIDs.count == 0) return;

    dispatch_async(self.stateQueue, ^{
        @synchronized (self.stateLock) {

            for (NSString *aid in assetIDs) {
                if (aid.length == 0) continue;

                SwipeAssetStatus prev = [self statusForAssetID:aid];
                if (prev == SwipeAssetStatusUnknown) {
                    // 已经是未处理，不用动
                    continue;
                }

                // 如果之前是 Archived，必须扣掉缓存并清掉 bytes 记录
                if (prev == SwipeAssetStatusArchived) {
                    unsigned long long v = 0;
                    NSNumber *b = self.bytesByAssetID[aid];
                    if (b) {
                        v = b.unsignedLongLongValue;
                    } else {
                        // bytes 缺失：补算一次，保证缓存能扣回去
                        v = [self quickAssetBytes:aid];
                    }

                    if (v > 0 && self.archivedBytesCached >= v) {
                        self.archivedBytesCached -= v;
                    }
                    [self.bytesByAssetID removeObjectForKey:aid];
                }

                // 变回未处理：直接移除 key（等价 Unknown）
                [self.statusByAssetID removeObjectForKey:aid];
            }

            [self.undoStack removeAllObjects];
            [self normalizeArchivedBytesCacheLocked];
        }

        [self saveStateToDisk];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
        });
    });
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

    if (!assetID.length) return;

    @synchronized (self.stateLock) {
        SwipeAssetStatus prev = [self statusForAssetID:assetID];
        if (prev == status) return;

        // undo record (global)
        if (recordUndo) {
            SwipeUndoRecord *r = [SwipeUndoRecord new];
            r.assetID = assetID;
            r.previousStatus = prev;
            [self.undoStack addObject:r];
        }

        // archived bytes cache update...
        if (prev == SwipeAssetStatusArchived && status != SwipeAssetStatusArchived) {
            NSNumber *b = self.bytesByAssetID[assetID];
            if (b) {
                unsigned long long v = b.unsignedLongLongValue;
                if (self.archivedBytesCached >= v) self.archivedBytesCached -= v;
                [self.bytesByAssetID removeObjectForKey:assetID];
            }
        } else if (prev != SwipeAssetStatusArchived && status == SwipeAssetStatusArchived) {
            unsigned long long bytes = [self quickAssetBytes:assetID];
            if (bytes > 0) {
                self.bytesByAssetID[assetID] = @(bytes);
                self.archivedBytesCached += bytes;
            }
        }

        self.statusByAssetID[assetID] = @(status);
    }

    [self saveStateToDisk];
    [[NSNotificationCenter defaultCenter] postNotificationName:SwipeManagerDidUpdateNotification object:self];
}

- (void)resetStatusForAssetID:(NSString *)assetID sourceModule:(nullable NSString *)moduleID recordUndo:(BOOL)recordUndo {
    [self setStatus:SwipeAssetStatusUnknown forAssetID:assetID sourceModule:moduleID recordUndo:recordUndo];
}

- (BOOL)undoLastActionInModuleID:(NSString *)moduleID {
    return ([self undoLastActionAssetIDInModuleID:moduleID] != nil);
}

- (nullable NSString *)undoLastActionAssetIDInModuleID:(NSString *)moduleID {
    (void)moduleID; // 不再使用

    SwipeUndoRecord *last = nil;

    @synchronized (self.stateLock) {
        // 可能遇到栈顶 asset 已不存在：循环丢弃直到找到可用的
        while (self.undoStack.count > 0) {
            last = self.undoStack.lastObject;
            [self.undoStack removeLastObject];

            if (last.assetID.length == 0) { last = nil; continue; }
            if ([self assetForID:last.assetID] == nil) { last = nil; continue; } // 已被删除
            break;
        }
    }

    if (!last) return nil;

    // 恢复到之前状态，避免再入栈
    [self setStatus:last.previousStatus
         forAssetID:last.assetID
        sourceModule:nil
          recordUndo:NO];

    return last.assetID;
}


#pragma mark - Sorting pref

- (void)setSortAscending:(BOOL)ascending forModuleID:(NSString *)moduleID {
    if (!moduleID.length) return;

    @synchronized (self.stateLock) {
        self.moduleSortAscendingByID[moduleID] = @(ascending);

        [self.moduleCursorAssetIDByID removeObjectForKey:moduleID];
    }
    [self saveStateToDisk];

    [self reloadModules];
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

- (void)normalizeArchivedBytesCacheLocked {
    // 必须在 @synchronized(self.stateLock) 内调用
    __block BOOL hasArchived = NO;

    [self.statusByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *aid, NSNumber *st, BOOL *stop) {
        if (st.integerValue == SwipeAssetStatusArchived) {
            hasArchived = YES;
            *stop = YES;
        }
    }];

    if (!hasArchived) {
        self.archivedBytesCached = 0;
        [self.bytesByAssetID removeAllObjects];
        return;
    }

    // 清理 bytesByAssetID 中“非 Archived”的残留 key
    NSMutableArray<NSString *> *badKeys = [NSMutableArray array];
    [self.bytesByAssetID enumerateKeysAndObjectsUsingBlock:^(NSString *aid, NSNumber *b, BOOL *stop) {
        NSNumber *st = self.statusByAssetID[aid];
        if (st.integerValue != SwipeAssetStatusArchived) {
            [badKeys addObject:aid];
        }
    }];
    if (badKeys.count) {
        [self.bytesByAssetID removeObjectsForKeys:badKeys];
    }

    // 重新汇总（只用现有 bytesByAssetID，缺的后面 refreshArchivedBytesIfNeeded 再补）
    unsigned long long sum = 0;
    for (NSNumber *b in self.bytesByAssetID.allValues) {
        sum += b.unsignedLongLongValue;
    }
    self.archivedBytesCached = sum;
}

- (unsigned long long)quickAssetBytes:(NSString *)assetID {
    PHAsset *asset = [self assetForID:assetID];
    if (!asset) return 0;

    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    if (resources.count == 0) return 0;

    PHAssetResource *res = resources.firstObject;
    @try {
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
                @synchronized (self.stateLock) {
                    if ([self statusForAssetID:aid] == SwipeAssetStatusArchived && !self.bytesByAssetID[aid]) {
                        self.bytesByAssetID[aid] = @(v);
                        add += v;
                    }
                }
                dispatch_group_leave(g);
                continue;
            }

            // fallback：读取数据累计
            __block unsigned long long bytes = 0;
            [[PHAssetResourceManager defaultManager] requestDataForAssetResource:res
                                                                        options:nil
                                                                 dataReceivedHandler:^(NSData * _Nonnull data) {
                bytes += data.length;
            } completionHandler:^(__unused NSError * _Nullable error) {
                if (bytes > 0) {
                    @synchronized (self.stateLock) {
                        if ([self statusForAssetID:aid] == SwipeAssetStatusArchived && !self.bytesByAssetID[aid]) {
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
            @synchronized (self.stateLock) {
                self.archivedBytesCached += add;
            }
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

    NSMutableDictionary<NSString*, NSNumber*> *toSubtract = [NSMutableDictionary dictionary];

    @synchronized (self.stateLock) {
        for (NSString *aid in assetIDs) {
            if ([self statusForAssetID:aid] != SwipeAssetStatusArchived) continue;

            NSNumber *b = self.bytesByAssetID[aid];
            unsigned long long v = b ? b.unsignedLongLongValue : [self quickAssetBytes:aid];
            if (v > 0) toSubtract[aid] = @(v);
        }
    }

    NSArray<PHAsset *> *assets = [self assetsForIDs:assetIDs];
    if (assets.count == 0) {
        @synchronized (self.stateLock) {
            for (NSString *aid in assetIDs) {
                [self.statusByAssetID removeObjectForKey:aid];
                [self.bytesByAssetID removeObjectForKey:aid];
                [self.random20AssetIDs removeObject:aid];
            }

            NSSet *delSet = [NSSet setWithArray:assetIDs];
            NSIndexSet *bad = [self.undoStack indexesOfObjectsPassingTest:^BOOL(SwipeUndoRecord *r, NSUInteger idx, BOOL *stop) {
                return r.assetID.length == 0 || [delSet containsObject:r.assetID];
            }];
            if (bad.count > 0) [self.undoStack removeObjectsAtIndexes:bad];

            [self normalizeArchivedBytesCacheLocked];
        }

        [self saveStateToDisk];

        // 强制触发 modules 刷新（reload 完成后会 post SwipeManagerDidUpdateNotification）
        [self scheduleReloadModules];

        if (completion) completion(YES, nil);
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                unsigned long long sub = 0;
                for (NSNumber *n in toSubtract.allValues) sub += n.unsignedLongLongValue;

                @synchronized (self.stateLock) {
                    if (self.archivedBytesCached >= sub) self.archivedBytesCached -= sub;

                    for (NSString *aid in assetIDs) {
                        [self.statusByAssetID removeObjectForKey:aid];
                        [self.bytesByAssetID removeObjectForKey:aid];
                        [self.random20AssetIDs removeObject:aid];
                    }

                    NSSet *delSet = [NSSet setWithArray:assetIDs];
                    NSIndexSet *bad = [self.undoStack indexesOfObjectsPassingTest:^BOOL(SwipeUndoRecord *r, NSUInteger idx, BOOL *stop) {
                        return r.assetID.length == 0 || [delSet containsObject:r.assetID];
                    }];
                    if (bad.count > 0) [self.undoStack removeObjectsAtIndexes:bad];

                    [self normalizeArchivedBytesCacheLocked];
                }

                [self saveStateToDisk];

                // reload modules（reload 完成后会发通知）
                [self scheduleReloadModules];
            });
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }
    }];
}

- (nullable NSString *)undoLastActionAssetIDInScopeAssetIDSet:(NSSet<NSString *> *)scope {
    if (scope.count == 0) return nil;

    SwipeUndoRecord *picked = nil;
    NSInteger pickedIndex = NSNotFound;

    @synchronized (self.stateLock) {

        // 1) 清掉栈里已经不存在的 asset（可选但推荐）
        for (NSInteger i = (NSInteger)self.undoStack.count - 1; i >= 0; i--) {
            SwipeUndoRecord *r = self.undoStack[i];
            if (r.assetID.length == 0 || [self assetForID:r.assetID] == nil) {
                [self.undoStack removeObjectAtIndex:i];
            }
        }

        // 2) 倒序找第一条 “asset 在当前 scope 里” 的记录
        for (NSInteger i = (NSInteger)self.undoStack.count - 1; i >= 0; i--) {
            SwipeUndoRecord *r = self.undoStack[i];
            if (![scope containsObject:r.assetID]) continue;

            picked = r;
            pickedIndex = i;
            break;
        }

        if (picked && pickedIndex != NSNotFound) {
            [self.undoStack removeObjectAtIndex:pickedIndex];
        }
    }

    if (!picked || picked.assetID.length == 0) return nil;

    // 3) 恢复到之前状态（recordUndo:NO 避免再入栈）
    [self setStatus:picked.previousStatus
         forAssetID:picked.assetID
        sourceModule:nil
          recordUndo:NO];

    return picked.assetID;
}

#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    [self scheduleReloadModules];
}

- (void)reloadModulesCoalesced {
    // 如果正在 reload，就只标记 pendingReload，等这轮结束再来一次
    @synchronized (self.stateLock) {
        if (self.isReloading) {
            self.pendingReload = YES;
            return;
        }
    }
    [self reloadModules];
}

- (void)scheduleReloadModules {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 如果正在 reload，直接标记 pending，等 reload 结束会自动 schedule
        @synchronized (self.stateLock) {
            if (self.isReloading) {
                self.pendingReload = YES;
                return;
            }
        }

        if (self.reloadScheduled) return;
        self.reloadScheduled = YES;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self.reloadScheduled = NO;
            [self reloadModules];
        });
    });
}

@end
