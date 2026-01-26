#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ASStudioMediaType) {
    ASStudioMediaTypePhoto = 0,
    ASStudioMediaTypeVideo = 1
};

@interface ASStudioItem : NSObject

@property (nonatomic, copy) NSString *assetId;          // PHAsset.localIdentifier
@property (nonatomic, assign) ASStudioMediaType type;   // photo / video

@property (nonatomic, copy) NSString *displayName;      // 你希望展示的文件名（自生成，避免同名）
@property (nonatomic, strong) NSDate *compressedAt;     // 你自己记录的压缩时间（最可靠）

@property (nonatomic, assign) int64_t afterBytes;       // 压缩后大小（存你编码得到的长度最稳）
@property (nonatomic, assign) int64_t beforeBytes;      // 压缩前大小（可选，但建议存）

@property (nonatomic, assign) double duration;          // video 秒数；photo=0

// JSON
- (NSDictionary *)toJSON;
+ (instancetype)fromJSON:(NSDictionary *)json;

@end
