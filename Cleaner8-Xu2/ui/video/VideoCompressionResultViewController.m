#import "VideoCompressionResultViewController.h"
#import "VideoCompressionManager.h"

@interface ASCompressionSummary (ASResult) <ASCompressionResultSummary>
@end

@implementation ASCompressionSummary (ASResult)

- (NSInteger)inputCount {
    return (NSInteger)self.items.count;
}

- (uint64_t)beforeBytes { return self.totalBeforeBytes; }
- (uint64_t)afterBytes  { return self.totalAfterBytes; }
- (uint64_t)savedBytes  { return self.totalSavedBytes; }

- (NSArray<PHAsset *> *)originalAssets {
    NSMutableArray *arr = [NSMutableArray array];
    for (ASCompressionItemResult *it in self.items) {
        if (it.originalAsset) [arr addObject:it.originalAsset];
    }
    return arr;
}

@end

@implementation VideoCompressionResultViewController
- (NSString *)deleteSheetTitle { return @"Delete original Video ?"; }
- (NSString *)itemSingular { return @"video"; }
- (NSString *)itemPlural   { return @"videos"; }
- (NSString *)homeIconName { return @"ic_back_home"; }
@end
