#import "ASPrivateMediaStore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ASPrivateMediaStore ()
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation ASPrivateMediaStore

+ (instancetype)shared {
    static ASPrivateMediaStore *s; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ASPrivateMediaStore new]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _fm = [NSFileManager defaultManager];
    }
    return self;
}

- (NSURL *)rootDir {
    NSURL *doc = [self.fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *root = [doc URLByAppendingPathComponent:@"PrivateAlbum" isDirectory:YES];
    if (![self.fm fileExistsAtPath:root.path]) {
        [self.fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return root;
}

- (NSURL *)dirForType:(ASPrivateMediaType)type {
    NSString *name = (type == ASPrivateMediaTypePhoto) ? @"Photos" : @"Videos";
    NSURL *dir = [[self rootDir] URLByAppendingPathComponent:name isDirectory:YES];
    if (![self.fm fileExistsAtPath:dir.path]) {
        [self.fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

- (NSArray<NSURL *> *)allItems:(ASPrivateMediaType)type {
    NSURL *dir = [self dirForType:type];
    NSArray *files = [self.fm contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil];
    // 稳定排序：按文件名
    return [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent compare:b.lastPathComponent];
    }];
}

- (void)deleteItems:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        [self.fm removeItemAtURL:u error:nil];
    }
}

// 兼容旧接口：内部调用新接口
- (void)importFromPickerResults:(NSArray<PHPickerResult *> *)results
                           type:(ASPrivateMediaType)type
                     completion:(void(^)(BOOL ok))completion {
    [self importFromPickerResults:results type:type onOneDone:nil completion:completion];
}

- (void)importFromPickerResults:(NSArray<PHPickerResult *> *)results
                           type:(ASPrivateMediaType)type
                      onOneDone:(void(^)(NSURL * _Nullable dstURL, BOOL ok))onOneDone
                     completion:(void(^)(BOOL ok))completion {

    if (results.count == 0) {
        if (completion) completion(YES);
        return;
    }

    UTType *ut = (type == ASPrivateMediaTypePhoto) ? UTTypeImage : UTTypeMovie;
    NSURL *destDir = [self dirForType:type];

    __block NSInteger idx = 0;
    __block BOOL allOK = YES;

    __weak typeof(self) ws = self;

    void (^step)(void) = ^{
        if (idx >= results.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(allOK);
            });
            return;
        }

        PHPickerResult *r = results[idx++];
        NSItemProvider *p = r.itemProvider;

        // 不符合类型就跳过继续
        if (![p hasItemConformingToTypeIdentifier:ut.identifier]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                step();
            });
            return;
        }

        NSString *typeId = ut.identifier;

        [p loadFileRepresentationForTypeIdentifier:typeId completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {

            void (^finishOne)(NSURL *dst, BOOL ok) = ^(NSURL *dst, BOOL ok){
                if (!ok) allOK = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (onOneDone) onOneDone(ok ? dst : nil, ok);
                    step();
                });
            };

            if (!error && url) {
                @autoreleasepool {
                    NSString *ext = url.pathExtension.length ? url.pathExtension : ((type==ASPrivateMediaTypePhoto)?@"jpg":@"mp4");
                    uint64_t ms = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
                    NSString *name = [NSString stringWithFormat:@"%llu_%@.%@",
                                      (unsigned long long)ms, NSUUID.UUID.UUIDString, ext];
                    NSURL *dst = [destDir URLByAppendingPathComponent:name];

                    NSError *copyErr = nil;
                    [ws.fm copyItemAtURL:url toURL:dst error:&copyErr];
                    finishOne(dst, copyErr == nil);
                }
                return;
            }

            // ✅ fallback：loadDataRepresentation（对受限资源更稳）
            [p loadDataRepresentationForTypeIdentifier:typeId completionHandler:^(NSData * _Nullable data, NSError * _Nullable err2) {
                @autoreleasepool {
                    if (err2 || data.length == 0) {
                        finishOne(nil, NO);
                        return;
                    }

                    NSString *ext = (type==ASPrivateMediaTypePhoto)?@"jpg":@"mp4";
                    uint64_t ms = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
                    NSString *name = [NSString stringWithFormat:@"%llu_%@.%@",
                                      (unsigned long long)ms, NSUUID.UUID.UUIDString, ext];
                    NSURL *dst = [destDir URLByAppendingPathComponent:name];

                    NSError *werr = nil;
                    [data writeToURL:dst options:NSDataWritingAtomic error:&werr];
                    finishOne(dst, werr == nil);
                }
            }];
        }];
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        step();
    });
}

- (NSString *)idsPlistPath:(ASPrivateMediaType)type {
    NSURL *doc = [self.fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *name = (type==ASPrivateMediaTypePhoto) ? @"private_photo_ids.plist" : @"private_video_ids.plist";
    return [[doc URLByAppendingPathComponent:name] path];
}

- (NSArray<NSString *> *)loadIds:(ASPrivateMediaType)type {
    NSString *p = [self idsPlistPath:type];
    NSArray *arr = [NSArray arrayWithContentsOfFile:p];
    if (![arr isKindOfClass:NSArray.class]) return @[];
    return arr;
}

- (void)saveIds:(NSArray<NSString *> *)ids type:(ASPrivateMediaType)type {
    NSString *p = [self idsPlistPath:type];
    [ids writeToFile:p atomically:YES];
}

- (void)appendAssetIdentifiers:(NSArray<NSString *> *)ids type:(ASPrivateMediaType)type {
    if (ids.count == 0) return;
    NSMutableArray *old = [[self loadIds:type] mutableCopy];
    NSMutableSet *set = [NSMutableSet setWithArray:old];
    for (NSString *lid in ids) {
        if (!lid.length) continue;
        if (![set containsObject:lid]) { [old addObject:lid]; [set addObject:lid]; }
    }
    [self saveIds:old type:type];
}

- (void)deleteAssetIdentifiers:(NSArray<NSString *> *)ids type:(ASPrivateMediaType)type {
    if (ids.count == 0) return;
    NSMutableArray *old = [[self loadIds:type] mutableCopy];
    NSSet *rm = [NSSet setWithArray:ids];
    NSIndexSet *toRemove = [old indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        return [rm containsObject:obj];
    }];
    [old removeObjectsAtIndexes:toRemove];
    [self saveIds:old type:type];
}

- (NSArray<PHAsset *> *)allAssets:(ASPrivateMediaType)type {
    NSArray<NSString *> *ids = [self loadIds:type];
    if (ids.count == 0) return @[];

    PHFetchResult<PHAsset *> *r = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];

    // 保持与 ids 相同顺序
    NSMutableDictionary<NSString*, PHAsset*> *map = [NSMutableDictionary dictionary];
    [r enumerateObjectsUsingBlock:^(PHAsset *obj, NSUInteger idx, BOOL *stop) {
        map[obj.localIdentifier] = obj;
    }];

    NSMutableArray<PHAsset*> *out = [NSMutableArray array];
    for (NSString *lid in ids) {
        PHAsset *a = map[lid];
        if (a) [out addObject:a];
    }
    return out;
}

@end
