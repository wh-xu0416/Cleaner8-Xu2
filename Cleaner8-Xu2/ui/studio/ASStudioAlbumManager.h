#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@interface ASStudioAlbumManager : NSObject

+ (instancetype)shared;

// 默认专用相册名
@property (nonatomic, copy) NSString *albumTitle;

// 获取/创建相册（异步返回）
- (void)fetchOrCreateAlbum:(void(^)(PHAssetCollection * _Nullable album, NSError * _Nullable error))completion;

// 把“新创建的 asset placeholder”加入专用相册（在 performChanges 里调用）
+ (void)addPlaceholder:(PHObjectPlaceholder *)placeholder
               toAlbum:(PHAssetCollection *)album;

@end
