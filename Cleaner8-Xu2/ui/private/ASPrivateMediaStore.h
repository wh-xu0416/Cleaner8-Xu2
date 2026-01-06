#import <Foundation/Foundation.h>
#import <PhotosUI/PhotosUI.h>

typedef NS_ENUM(NSInteger, ASPrivateMediaType) {
    ASPrivateMediaTypePhoto = 0,
    ASPrivateMediaTypeVideo = 1,
};

@interface ASPrivateMediaStore : NSObject
+ (instancetype)shared;

- (NSArray<NSURL *> *)allItems:(ASPrivateMediaType)type;
- (void)deleteItems:(NSArray<NSURL *> *)urls;

- (void)importFromPickerResults:(NSArray<PHPickerResult *> *)results
                           type:(ASPrivateMediaType)type
                     completion:(void(^)(BOOL ok))completion;

- (NSArray<PHAsset *> *)allAssets:(ASPrivateMediaType)type;
- (void)appendAssetIdentifiers:(NSArray<NSString *> *)ids type:(ASPrivateMediaType)type;
- (void)deleteAssetIdentifiers:(NSArray<NSString *> *)ids type:(ASPrivateMediaType)type;

- (void)importFromPickerResults:(NSArray<PHPickerResult *> *)results
                           type:(ASPrivateMediaType)type
                      onOneDone:(void(^)(NSURL * _Nullable dstURL, BOOL ok))onOneDone
                     completion:(void(^)(BOOL ok))completion;

@end
