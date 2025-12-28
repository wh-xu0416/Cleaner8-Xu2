#import "ASStudioAlbumManager.h"

static NSString * const kASStudioAlbumIdKey = @"ASStudioAlbumLocalId";

@implementation ASStudioAlbumManager

+ (instancetype)shared {
    static ASStudioAlbumManager *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [ASStudioAlbumManager new];
        s.albumTitle = @"My Studio";
    });
    return s;
}

- (NSString *)cachedAlbumId {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kASStudioAlbumIdKey];
}

- (void)setCachedAlbumId:(NSString *)lid {
    if (lid.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:lid forKey:kASStudioAlbumIdKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kASStudioAlbumIdKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (PHAssetCollection *)fetchAlbumById:(NSString *)localId {
    if (localId.length == 0) return nil;
    PHFetchResult<PHAssetCollection *> *r =
    [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[localId] options:nil];
    return r.firstObject;
}

- (PHAssetCollection *)fetchAlbumByTitle:(NSString *)title {
    if (title.length == 0) return nil;
    PHFetchResult<PHAssetCollection *> *r =
    [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                             subtype:PHAssetCollectionSubtypeAlbumRegular
                                             options:nil];
    __block PHAssetCollection *found = nil;
    [r enumerateObjectsUsingBlock:^(PHAssetCollection * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.localizedTitle isEqualToString:title]) {
            found = obj;
            *stop = YES;
        }
    }];
    return found;
}

- (void)fetchOrCreateAlbum:(void(^)(PHAssetCollection * _Nullable album, NSError * _Nullable error))completion {

    // 1) try cached id
    PHAssetCollection *cached = [self fetchAlbumById:[self cachedAlbumId]];
    if (cached) { if (completion) completion(cached, nil); return; }

    // 2) try title
    PHAssetCollection *byTitle = [self fetchAlbumByTitle:self.albumTitle];
    if (byTitle) {
        [self setCachedAlbumId:byTitle.localIdentifier];
        if (completion) completion(byTitle, nil);
        return;
    }

    // 3) create
    __block NSString *createdId = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCollectionChangeRequest *req =
        [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:self.albumTitle];
        createdId = req.placeholderForCreatedAssetCollection.localIdentifier;
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success || createdId.length == 0) {
            if (completion) completion(nil, error);
            return;
        }
        PHAssetCollection *album = [self fetchAlbumById:createdId];
        [self setCachedAlbumId:createdId];
        if (completion) completion(album, nil);
    }];
}

+ (void)addPlaceholder:(PHObjectPlaceholder *)placeholder toAlbum:(PHAssetCollection *)album {
    if (!placeholder || !album) return;
    PHAssetCollectionChangeRequest *albumReq = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
    [albumReq addAssets:@[placeholder]];
}

@end
