#import "ImageCompressionResultViewController.h"
#import "ImageCompressionManager.h"

@interface ASImageCompressionSummary (ASResult) <ASCompressionResultSummary>
@end
@implementation ASImageCompressionSummary (ASResult)
@end

@implementation ImageCompressionResultViewController

- (BOOL)useStaticPreviewIcon { return YES; }
- (NSString *)staticPreviewIconName { return @"ic_img_great"; }
- (CGSize)staticPreviewSize { return CGSizeMake(180, 170); }

- (NSString *)deleteSheetTitle { return @"Delete original Image ?"; }
- (NSString *)itemSingular { return @"image"; }
- (NSString *)itemPlural   { return @"images"; }

- (NSString *)homeIconName { return @"ic_back_home"; }

@end
