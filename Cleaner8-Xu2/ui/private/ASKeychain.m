#import "ASKeychain.h"
#import <Security/Security.h>

@implementation ASKeychain

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key {
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"ASPrivateAlbum",
        (__bridge id)kSecAttrAccount: keyData,
    } mutableCopy];
}

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key {
    NSMutableDictionary *q = [self baseQueryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)q);

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecValueData] = data;
    OSStatus s = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    return (s == errSecSuccess);
}

+ (NSString *)stringForKey:(NSString *)key {
    NSMutableDictionary *q = [self baseQueryForKey:key];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (s != errSecSuccess || !result) return nil;

    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)deleteForKey:(NSString *)key {
    NSMutableDictionary *q = [self baseQueryForKey:key];
    OSStatus s = SecItemDelete((__bridge CFDictionaryRef)q);
    return (s == errSecSuccess || s == errSecItemNotFound);
}

@end
