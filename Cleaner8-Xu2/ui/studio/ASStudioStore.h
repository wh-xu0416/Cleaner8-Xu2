#import <Foundation/Foundation.h>
#import "ASStudioItem.h"

@interface ASStudioStore : NSObject

+ (instancetype)shared;

// 全量（已按 compressedAt desc 排好）
- (NSArray<ASStudioItem *> *)allItems;

// 按类型筛选
- (NSArray<ASStudioItem *> *)itemsForType:(ASStudioMediaType)type;

// upsert（assetId 相同则更新）
- (void)upsertItem:(ASStudioItem *)item;

// 删除
- (void)removeByAssetId:(NSString *)assetId;

// 清理：移除不在现存 assetId 集合里的记录
- (void)removeItemsNotInAssetIdSet:(NSSet<NSString *> *)existingAssetIds;

@end
