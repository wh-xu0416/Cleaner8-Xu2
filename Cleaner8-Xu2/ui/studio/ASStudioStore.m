#import "ASStudioStore.h"

@interface ASStudioStore ()
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) NSMutableArray<ASStudioItem *> *items;
@end

@implementation ASStudioStore

+ (instancetype)shared {
    static ASStudioStore *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [ASStudioStore new];
    });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _q = dispatch_queue_create("studio.store.queue", DISPATCH_QUEUE_SERIAL);
        _items = [NSMutableArray array];
        [self load];
    }
    return self;
}

- (NSString *)filePath {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [dir stringByAppendingPathComponent:@"ASMyStudio"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [path stringByAppendingPathComponent:@"studio_index.json"];
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
    if (!data) return;

    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSArray class]]) return;

    NSArray *arr = (NSArray *)obj;
    NSMutableArray *tmp = [NSMutableArray array];
    for (id x in arr) {
        ASStudioItem *it = [ASStudioItem fromJSON:x];
        if (it.assetId.length > 0) [tmp addObject:it];
    }

    // sort desc
    [tmp sortUsingComparator:^NSComparisonResult(ASStudioItem *a, ASStudioItem *b) {
        return [b.compressedAt compare:a.compressedAt];
    }];

    self.items = tmp;
}

- (void)save {
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:self.items.count];
    for (ASStudioItem *it in self.items) {
        [arr addObject:[it toJSON]];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
    if (!data) return;
    [data writeToFile:[self filePath] atomically:YES];
}

- (NSArray<ASStudioItem *> *)allItems {
    __block NSArray *out = nil;
    dispatch_sync(self.q, ^{
        out = [self.items copy];
    });
    return out;
}

- (NSArray<ASStudioItem *> *)itemsForType:(ASStudioMediaType)type {
    __block NSArray *out = nil;
    dispatch_sync(self.q, ^{
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(ASStudioItem *it, NSDictionary *_) {
            return it.type == type;
        }];
        out = [self.items filteredArrayUsingPredicate:p];
    });
    return out;
}

- (void)upsertItem:(ASStudioItem *)item {
    if (item.assetId.length == 0) return;

    dispatch_async(self.q, ^{
        NSInteger idx = NSNotFound;
        for (NSInteger i = 0; i < self.items.count; i++) {
            if ([self.items[i].assetId isEqualToString:item.assetId]) { idx = i; break; }
        }
        if (idx != NSNotFound) {
            self.items[idx] = item;
        } else {
            [self.items insertObject:item atIndex:0];
        }

        [self.items sortUsingComparator:^NSComparisonResult(ASStudioItem *a, ASStudioItem *b) {
            return [b.compressedAt compare:a.compressedAt];
        }];

        [self save];
    });
}

- (void)removeByAssetId:(NSString *)assetId {
    if (assetId.length == 0) return;

    dispatch_async(self.q, ^{
        NSIndexSet *set = [self.items indexesOfObjectsPassingTest:^BOOL(ASStudioItem *obj, NSUInteger idx, BOOL *stop) {
            return [obj.assetId isEqualToString:assetId];
        }];
        if (set.count > 0) [self.items removeObjectsAtIndexes:set];
        [self save];
    });
}

- (void)removeItemsNotInAssetIdSet:(NSSet<NSString *> *)existingAssetIds {
    if (!existingAssetIds) return;

    dispatch_async(self.q, ^{
        NSIndexSet *set = [self.items indexesOfObjectsPassingTest:^BOOL(ASStudioItem *obj, NSUInteger idx, BOOL *stop) {
            return ![existingAssetIds containsObject:obj.assetId];
        }];
        if (set.count > 0) [self.items removeObjectsAtIndexes:set];
        [self save];
    });
}

@end
