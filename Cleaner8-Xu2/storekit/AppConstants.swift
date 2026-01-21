import Foundation

@objc(AppConstants)
@objcMembers public class AppConstants: NSObject {
    
    private override init() {}
    
    // 订阅商品ID
    public static let productIDWeekly = "com.demo.pro.weekly"
    public static let productIDYearly  = "com.demo.pro.yearly"
    
    // 用户协议
    public static let termsLink  = "https://www.baidu.com"
    // 隐私协议
    public static let privacyLink  = "https://www.baidu.com"
}
