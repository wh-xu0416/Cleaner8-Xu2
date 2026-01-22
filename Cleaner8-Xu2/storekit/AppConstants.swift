import Foundation

@objc(AppConstants)
@objcMembers
public class AppConstants: NSObject {

    private override init() {}

    // MARK: - IAP（订阅商品ID）
    public static let productIDWeekly = "com.demo.pro.weekly"
    public static let productIDYearly = "com.demo.pro.yearly"
    
    // MARK: - iapUploadURL 域名
    public static let iapUploadURL: String = "https://iapUploadURL.com"

    // MARK: - 协议链接
    public static let termsLink   = "https://www.baidu.com"
    public static let privacyLink = "https://www.baidu.com"

    // MARK: - Firebase
    
    // 是否启用 Firebase初始化
    public static let firebaseEnabled: Bool = false

    // MARK: - ThinkingData（数数）
    public static let thinkingDataAppId: String = "YOUR_THINKINGDATA_APP_ID"
    public static let thinkingDataServerUrl: String = "https://thinkingDataServerUrl.com"
    public static let thinkingDataEnableLog: Bool = true

    // MARK: - AppsFlyer
    public static let appsFlyerDevKey: String = "YOUR_APPSFLYER_DEV_KEY"
    public static let appsFlyerAppleAppId: String = "YOUR_APPLE_APP_ID"
    
    // AppsFlyer 内部等待 ATT 回来的最大时长（秒）
    public static let appsFlyerAttWaitTimeout: Double = 120
    
    
    // MARK: - ABTest相关
    public static let abKeyPaidRateRate: String = "paid_rate_rate"
    public static let abKeySetRateRate: String  = "set_rate_rate"

    // 默认值 Remote Config 默认 本地默认
    public static let abDefaultOpen: String = "open"
    public static let abDefaultClose: String = "close"
}
