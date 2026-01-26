#import "VideoCompressionResultViewController.h"
#import "VideoCompressionManager.h"
#import "Common.h"

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
- (NSString *)deleteSheetTitle { return NSLocalizedString(@"Delete original Video ?", nil); }
- (NSString *)itemSingular { return NSLocalizedString(@"video", nil); }
- (NSString *)itemPlural   { return NSLocalizedString(@"videos", nil); }
- (NSString *)homeIconName { return @"ic_back_home"; }
@end
