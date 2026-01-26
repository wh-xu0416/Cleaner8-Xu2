#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "TDCalibratedTime.h"
#import "TDNTPServer.h"
#import "TDNTPTypes.h"
#import "NSData+TDGzip.h"
#import "NSDate+TDCore.h"
#import "NSDictionary+TDCore.h"
#import "NSNumber+TDCore.h"
#import "NSObject+TDCore.h"
#import "NSString+TDCore.h"
#import "NSURL+TDCore.h"
#import "TDCoreDatabase.h"
#import "TDCoreDeviceInfo.h"
#import "TDCoreFPSMonitor.h"
#import "TDCorePresetDisableConfig.h"
#import "TDCorePresetProperty.h"
#import "TDAESEncryptor.h"
#import "TDEncryptAlgorithm.h"
#import "TDEncryptProtocol.h"
#import "TDRSAEncryptor.h"
#import "TDRSAEncryptorPlugin.h"
#import "TDCoreKeychainHelper.h"
#import "TDKeychainManager.h"
#import "TDCoreLog.h"
#import "TDLogChannelConsole.h"
#import "TDLogChannelProtocol.h"
#import "TDLogConstant.h"
#import "TDLogMessage.h"
#import "TDOSLog.h"
#import "TDNetworkReachability.h"
#import "TDNotificationManager+Analytics.h"
#import "TDNotificationManager+Core.h"
#import "TDNotificationManager+Networking.h"
#import "TDNotificationManager+RemoteConfig.h"
#import "TDNotificationManager.h"
#import "TDMediator+Analytics.h"
#import "TDMediator+RemoteConfig.h"
#import "TDMediator+Sensitive.h"
#import "TDMediator+Strategy.h"
#import "TDMediator.h"
#import "TDStorageEncryptPlugin.h"
#import "TDUserDefaults.h"
#import "TDApp.h"
#import "TDCoreInfo.h"
#import "TDJSONUtil.h"
#import "NSObject+TDSwizzle.h"
#import "TDSwizzler.h"
#import "TDClassHelper.h"
#import "TDCoreWeakProxy.h"
#import "TDMethodHelper.h"
#import "TDNewSwizzle.h"
#import "TDSettings.h"
#import "TDSettingsPrivate.h"
#import "ThinkingDataCore.h"

FOUNDATION_EXPORT double ThinkingDataCoreVersionNumber;
FOUNDATION_EXPORT const unsigned char ThinkingDataCoreVersionString[];

