#import "ASPrivateMediaStore.h"
#import "Common.h"
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
    NSString *name = (type == ASPrivateMediaTypePhoto) ? NSLocalizedString(@"Photos", nil) : NSLocalizedString(@"Videos", nil);
    NSURL *dir = [[self rootDir] URLByAppendingPathComponent:name isDirectory:YES];
    if (![self.fm fileExistsAtPath:dir.path]) {
        [self.fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

- (NSArray<NSURL *> *)allItems:(ASPrivateMediaType)type {
    NSURL *dir = [self dirForType:type];
    NSError *err = nil;
    NSArray *files = [self.fm contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:&err];
    if (![files isKindOfClass:NSArray.class]) files = @[];

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

    fprintf(stderr, "📥 importFromPickerResults count=%lu\n", (unsigned long)results.count);

    if (results.count == 0) {
        if (completion) completion(YES);
        return;
    }

    UTType *want = (type == ASPrivateMediaTypePhoto) ? UTTypeImage : UTTypeMovie;
    NSURL *destDir = [self dirForType:type];

    dispatch_group_t group = dispatch_group_create();
    __block BOOL allOK = YES;

    for (PHPickerResult *r in results) {
        NSItemProvider *p = r.itemProvider;

        // 选择一个更“具体”的 typeId（不要死用 public.image / public.movie）
        __block NSString *typeId = nil;
        for (NSString *tid in p.registeredTypeIdentifiers) {
            UTType *t = [UTType typeWithIdentifier:tid];
            if (t && [t conformsToType:want]) { typeId = tid; break; }
        }

        if (!typeId) {
            fprintf(stderr, "❌ no matching typeId, providerTypes=%s\n",
                    [[p.registeredTypeIdentifiers description] UTF8String]);
            allOK = NO;
            continue;
        }

        fprintf(stderr, "✅ use typeId=%s\n", typeId.UTF8String);

        dispatch_group_enter(group);

        [p loadFileRepresentationForTypeIdentifier:typeId completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {

            void (^finish)(NSURL *dst, BOOL ok) = ^(NSURL *dst, BOOL ok) {
                if (!ok) allOK = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (onOneDone) onOneDone(ok ? dst : nil, ok);
                });
                dispatch_group_leave(group);
            };

            if (url && !error) {
                NSString *ext = url.pathExtension.length ? url.pathExtension : ((type==ASPrivateMediaTypePhoto)?@"jpg":@"mp4");
                uint64_t ms = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
                NSString *name = [NSString stringWithFormat:@"%llu_%@.%@", (unsigned long long)ms, NSUUID.UUID.UUIDString, ext];
                NSURL *dst = [destDir URLByAppendingPathComponent:name];

                NSError *copyErr = nil;
                BOOL ok = [self.fm copyItemAtURL:url toURL:dst error:&copyErr];
                fprintf(stderr, "📦 copy ok=%d err=%s\n", ok, (copyErr.localizedDescription ?: @"").UTF8String);
                finish(dst, ok);
                return;
            }

            // fallback：loadDataRepresentation
            [p loadDataRepresentationForTypeIdentifier:typeId completionHandler:^(NSData * _Nullable data, NSError * _Nullable err2) {
                if (err2 || data.length == 0) {
                    fprintf(stderr, "❌ data failed err=%s\n", (err2.localizedDescription ?: @"").UTF8String);
                    finish(nil, NO);
                    return;
                }

                NSString *ext = (type==ASPrivateMediaTypePhoto)?@"jpg":@"mp4";
                uint64_t ms = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
                NSString *name = [NSString stringWithFormat:@"%llu_%@.%@", (unsigned long long)ms, NSUUID.UUID.UUIDString, ext];
                NSURL *dst = [destDir URLByAppendingPathComponent:name];

                NSError *werr = nil;
                BOOL ok = [data writeToURL:dst options:NSDataWritingAtomic error:&werr];
                fprintf(stderr, "💾 write ok=%d err=%s\n", ok, (werr.localizedDescription ?: @"").UTF8String);
                finish(dst, ok);
            }];
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        fprintf(stderr, "✅ import done allOK=%d\n", allOK);
        if (completion) completion(allOK);
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
