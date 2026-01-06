#import <Foundation/Foundation.h>

@interface ASKeychain : NSObject
+ (BOOL)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (BOOL)deleteForKey:(NSString *)key;
@end
