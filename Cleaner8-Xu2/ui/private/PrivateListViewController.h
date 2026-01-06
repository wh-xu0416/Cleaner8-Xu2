#import <UIKit/UIKit.h>
#import "ASPrivateMediaStore.h"

@interface PrivateListViewController : UIViewController
@property (nonatomic, assign) ASPrivateMediaType mediaType;
@property (nonatomic, copy) NSString *navTitleText; // "Secret Photos"/"Secret Videos"
@end
