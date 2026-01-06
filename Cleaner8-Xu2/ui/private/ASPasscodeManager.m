#import "ASPasscodeManager.h"
#import "ASKeychain.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const ASPasscodeChangedNotification = @"ASPasscodeChangedNotification";

static NSString * const kASPassEnabledKey = @"ASPrivatePassEnabled";
static NSString * const kASPassHashKey    = @"ASPrivatePassHash";

@implementation ASPasscodeManager

+ (NSString *)sha256:(NSString *)s {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

+ (BOOL)isEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kASPassEnabledKey];
}

+ (BOOL)verify:(NSString *)code {
    if (code.length != 4) return NO;
    NSString *saved = [ASKeychain stringForKey:kASPassHashKey];
    if (!saved.length) return NO;
    return [[self sha256:code] isEqualToString:saved];
}

+ (void)enableWithCode:(NSString *)code {
    if (code.length != 4) return;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kASPassEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [ASKeychain setString:[self sha256:code] forKey:kASPassHashKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:ASPasscodeChangedNotification object:nil];
}

+ (void)disable {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kASPassEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [ASKeychain deleteForKey:kASPassHashKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:ASPasscodeChangedNotification object:nil];
}

@end
