import Foundation

@objc(AppConstants)
@objcMembers
public class AppConstants: NSObject {

    private override init() {}

    // MARK: - IAP（订阅商品ID）
    public static let productIDWeekly = "com.demo.pro.weekly"                    // 周 $7.99
    public static let productIDWeeklyTrial899 = "com.demo.pro.weekly.trial899"   // 周 3天免费试用 $8.99
    public static let productIDWeeklyTrial999 = "com.demo.pro.weekly.trial999"   // 周 3天免费试用 $9.99
    public static let productIDYearly = "com.demo.pro.yearly"
    
    // MARK: - iapUploadURL 域名
    public static let iapUploadURL: String = "https://iapUploadURL.com"

    // MARK: - 协议链接
    public static let termsLink   = "https://www.baidu.com"
    public static let privacyLink = "https://www.baidu.com"

    // MARK: - Firebase
    public static let firebaseEnabled: Bool = false

    // MARK: - ThinkingData（数数）
    public static let thinkingDataAppId: String = "YOUR_THINKINGDATA_APP_ID"
    public static let thinkingDataServerUrl: String = "https://thinkingDataServerUrl.com"
    public static let thinkingDataEnableLog: Bool = true

    // MARK: - AppsFlyer
    public static let appsFlyerDevKey: String = "YOUR_APPSFLYER_DEV_KEY"
    public static let appsFlyerAppleAppId: String = "YOUR_APPLE_APP_ID"
    public static let appsFlyerAttWaitTimeout: Double = 120
    
    // MARK: - Paywall / Subscription 配置
    // 栏门页 2: 周费商品, 3: 年费商品
    public static let paywallGateModeRaw: Int = 2

    // 订阅列表页 0: 默认选中周费, 1: 默认选中年费
    public static let subscriptionPageModeRaw: Int = 0
    
    // MARK: - ABTest Key
    public static let abKeyPaidRateRate: String = "paid_rate_rate"
    public static let abKeySetRateRate: String  = "set_rate_rate"
    public static let abKeyWeeklySku: String    = "ab_purchase_0203"      // 周SKU AB测试 key

    public static let abDefaultOpen: String = "open"
    public static let abDefaultClose: String = "close"

    // MARK: - Weekly SKU AB Test Values
    public static let abWeeklySkuDefault: String = "799"        // 默认 $7.99
    public static let abWeeklySkuTrial899: String = "899"      // 3天免费试用 $8.99
    public static let abWeeklySkuTrial999: String = "999"      // 3天免费试用 $9.99

    // MARK: - 所有周SKU产品ID列表
    public static let allWeeklyProductIDs: [String] = [
        productIDWeekly,
        productIDWeeklyTrial899,
        productIDWeeklyTrial999
    ]
}
