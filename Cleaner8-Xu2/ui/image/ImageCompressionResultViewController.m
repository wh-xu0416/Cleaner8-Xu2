#import "ImageCompressionResultViewController.h"
#import "ImageCompressionManager.h"
#import "Common.h"

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat ASScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }

@interface ASImageCompressionSummary (ASResult) <ASCompressionResultSummary>
@end
@implementation ASImageCompressionSummary (ASResult)
@end

@implementation ImageCompressionResultViewController

- (BOOL)useStaticPreviewIcon { return YES; }
- (NSString *)staticPreviewIconName { return @"ic_img_great"; }
- (CGSize)staticPreviewSize { return CGSizeMake(AS(180), AS(170)); }

- (NSString *)deleteSheetTitle { return NSLocalizedString(@"Delete original Image ?", nil); }
- (NSString *)itemSingular { return NSLocalizedString(@"image", nil); }
- (NSString *)itemPlural   { return NSLocalizedString(@"images", nil); }

- (NSString *)homeIconName { return @"ic_back_home"; }

@end
