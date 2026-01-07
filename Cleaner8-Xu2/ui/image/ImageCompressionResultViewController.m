#import "ImageCompressionResultViewController.h"
#import "ImageCompressionManager.h"
#import "Common.h"

@interface ASImageCompressionSummary (ASResult) <ASCompressionResultSummary>
@end
@implementation ASImageCompressionSummary (ASResult)
@end

@implementation ImageCompressionResultViewController

- (BOOL)useStaticPreviewIcon { return YES; }
- (NSString *)staticPreviewIconName { return @"ic_img_great"; }
- (CGSize)staticPreviewSize { return CGSizeMake(180, 170); }

- (NSString *)deleteSheetTitle { return NSLocalizedString(@"Delete original Image ?", nil); }
- (NSString *)itemSingular { return NSLocalizedString(@"image", nil); }
- (NSString *)itemPlural   { return NSLocalizedString(@"images", nil); }

- (NSString *)homeIconName { return @"ic_back_home"; }

@end
