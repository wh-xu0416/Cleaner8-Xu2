import Foundation
import StoreKit
import Network
import UIKit
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(ThinkingSDK)
import ThinkingSDK
#endif
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif
import AdSupport
import AppTrackingTransparency

extension Notification.Name {
    static let storeSnapshotChanged = Notification.Name("storeSnapshotChanged")
    static let subscriptionStateChanged = Notification.Name("subscriptionStateChanged")
    static let purchaseStateChanged = Notification.Name("purchaseStateChanged")
}

final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

final class CompletionBox<T>: @unchecked Sendable {
    let block: (T) -> Void
    init(_ block: @escaping (T) -> Void) { self.block = block }
}

@objc enum SubscriptionState: Int {
    case unknown
    case inactive
    case active
}

@objc enum StoreAvailability: Int {
    case unknown
    case available
    case unavailable   // 例如无网络、或商店不可用（你可以先只用网络判断）
}

@objc enum ProductsLoadState: Int {
    case idle
    case loading
    case ready
    case failed
}

@objc enum PurchaseFlowState: Int {
    case idle
    case purchasing
    case pending
    case cancelled
    case succeeded
    case failed
    case restoring
    case restored
}
@objc public enum SK2PeriodUnit: Int { case day, week, month, year, unknown }

@objcMembers
public final class SK2ProductModel: NSObject {
    public let productID: String
    public let displayPrice: String
    public let displayName: String

    public let periodUnit: SK2PeriodUnit
    public let periodValue: Int

    public init(product: Product) {
        productID = product.id
        displayPrice = product.displayPrice
        displayName = product.displayName

        if let p = product.subscription?.subscriptionPeriod {
            periodValue = p.value
            switch p.unit {
            case .day:  periodUnit = .day
            case .week: periodUnit = .week
            case .month:periodUnit = .month
            case .year: periodUnit = .year
            @unknown default: periodUnit = .unknown
            }
        } else {
            periodValue = 0
            periodUnit = .unknown
        }
    }
}

@objcMembers
final class StoreSnapshot: NSObject {
    let networkAvailable: Bool
    let availability: StoreAvailability

    let productsState: ProductsLoadState
    let products: [SK2ProductModel]

    let subscriptionState: SubscriptionState

    let purchaseState: PurchaseFlowState
    let lastErrorMessage: String?

    init(networkAvailable: Bool,
         availability: StoreAvailability,
         productsState: ProductsLoadState,
         products: [SK2ProductModel],
         subscriptionState: SubscriptionState,
         purchaseState: PurchaseFlowState,
         lastErrorMessage: String?) {
        self.networkAvailable = networkAvailable
        self.availability = availability
        self.productsState = productsState
        self.products = products
        self.subscriptionState = subscriptionState
        self.purchaseState = purchaseState
        self.lastErrorMessage = lastErrorMessage
        super.init()
    }
}

@objcMembers
public final class ASProductIDs: NSObject {
    public static let subWeekly: String = "com.demo.pro.weekly"
    public static let subYearly: String = "com.demo.pro.yearly"
}

private enum ASAccountToken {
    static let tokenKey = "as_app_account_token"
    static let distinctKey = "as_app_account_token_distinctid"

    static func tokenUUID(distinctId: String?) -> UUID {
        let defaults = UserDefaults.standard

        // 1) 如果 distinctId 没变，并且之前存过 token，就直接复用
        if let d = distinctId, !d.isEmpty,
           defaults.string(forKey: distinctKey) == d,
           let saved = defaults.string(forKey: tokenKey),
           let uuid = UUID(uuidString: saved) {
            return uuid
        }

        // 2) 没有 distinctId：生成一个随机的并持久化（至少本机稳定）
        guard let d = distinctId, !d.isEmpty else {
            let uuid = UUID()
            defaults.set(uuid.uuidString, forKey: tokenKey)
            defaults.set("", forKey: distinctKey)
            return uuid
        }

        // 3) 用 distinctId 生成“稳定 UUID”
        let uuid = stableUUID(from: d)

        defaults.set(uuid.uuidString, forKey: tokenKey)
        defaults.set(d, forKey: distinctKey)
        return uuid
    }

    private static func stableUUID(from input: String) -> UUID {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest)

        // 取前 16 字节做 UUID，并设置 version/variant
        var b = Array(bytes[0..<16])
        b[6] = (b[6] & 0x0F) | 0x50  // version 5-ish
        b[8] = (b[8] & 0x3F) | 0x80  // RFC4122 variant

        return UUID(uuid: (
            b[0], b[1], b[2], b[3],
            b[4], b[5],
            b[6], b[7],
            b[8], b[9],
            b[10], b[11], b[12], b[13], b[14], b[15]
        ))
        #else
        // 没有 CryptoKit 就随机
        return UUID()
        #endif
    }
}

private enum ASIdentifiers {

    static func bundleId() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }

    static func distinctId() -> String {
        #if canImport(ThinkingSDK)
        return TDAnalytics.getDistinctId()
        #else
        return ""
        #endif
    }

    static func appsFlyerId() -> String {
        #if canImport(AppsFlyerLib)
        return AppsFlyerLib.shared().getAppsFlyerUID()
        #else
        return ""
        #endif
    }

    @MainActor static func idfv() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? ""
    }

    static func idfa() -> String {
        if #available(iOS 14, *) {
            guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return "" }
        }
        #if canImport(AdSupport)
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        if idfa == "00000000-0000-0000-0000-000000000000" { return "" }
        return idfa
        #else
        return ""
        #endif
    }
}

private struct ASUploadResp: Decodable {
    let result: Int
}

final class StoreKit2Manager: NSObject {

    // TODO: 换成你们自己的域名
    private var iapUploadURL: URL? {
        let baseURL = "https://YOUR_DOMAIN.com"
        return URL(string: baseURL + "/iap/upload")
    }

    @objc func uploadIAPIdentifiersOnEnterPaywall() {
        Task { await self.uploadIAPIdentifiers(reason: "进入内购页") }
    }

    @objc func uploadIAPIdentifiersBeforePurchaseTap() {
        Task { await self.uploadIAPIdentifiers(reason: "点击购买前") }
    }

    private func logCN(_ msg: String) {
        print("[内购标识上传] \(msg)")
    }

    private func uploadIAPIdentifiers(reason: String) async {
        guard let url = iapUploadURL else {
            logCN("失败：iapUploadURL 未配置")
            return
        }

        let body: [String: Any] = await [
            "bundleid": ASIdentifiers.bundleId(),
            "distinctid": ASIdentifiers.distinctId(),
            "appsflyer_id": ASIdentifiers.appsFlyerId(),
            "idfa": ASIdentifiers.idfa(),
            "idfv": ASIdentifiers.idfv()
        ]

        logCN("开始（\(reason)）：\(body)")

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, resp) = try await URLSession.shared.data(for: req)

            if let http = resp as? HTTPURLResponse {
                logCN("HTTP 状态码：\(http.statusCode)")
            }

            let decoded = try JSONDecoder().decode(ASUploadResp.self, from: data)
            if decoded.result == 0 {
                logCN("成功（\(reason)），result=0")
            } else {
                logCN("失败（\(reason)），result=\(decoded.result)")
            }
        } catch {
            logCN("失败（\(reason)）：\(error.localizedDescription)")
        }
    }
    
    @objc static let shared = StoreKit2Manager()

    let productIDs: [String] = [ASProductIDs.subYearly,ASProductIDs.subWeekly]

    @objc private(set) var snapshot: StoreSnapshot = StoreSnapshot(
        networkAvailable: true,
        availability: .unknown,
        productsState: .idle,
        products: [],
        subscriptionState: .unknown,
        purchaseState: .idle,
        lastErrorMessage: nil
    )

    @objc var state: SubscriptionState { snapshot.subscriptionState }

    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "xx.sk2.network.monitor")
    private var isStarted = false
    private var rawProducts: [Product] = []
    private var updatesTask: Task<Void, Never>?
    private var isRefreshingAfterNetwork = false

    // MARK: - Start
    @objc func start() {
        guard !isStarted else { return }
        isStarted = true
        
        startNetworkMonitor()
        observeAppForeground()
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshAll(reason: "start")
            self.listenForTransactionUpdates()
        }
    }

    // MARK: - Refresh
    @MainActor
    func refreshAll(reason: String) async {
        await refreshProducts()
        await refreshSubscriptionState()
    }

    @MainActor
    func refreshProducts() async {
        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.networkAvailable ? .available : .unavailable,
                productsState: .loading,
                products: old.products,
                subscriptionState: old.subscriptionState,
                purchaseState: old.purchaseState,
                lastErrorMessage: nil
            )
        }

        do {
            let list = try await Product.products(for: productIDs)
            self.rawProducts = list
            let models = list.map { SK2ProductModel(product: $0) }

            updateSnapshot { old in
                StoreSnapshot(
                    networkAvailable: old.networkAvailable,
                    availability: old.networkAvailable ? .available : .unavailable,
                    productsState: .ready,
                    products: models,
                    subscriptionState: old.subscriptionState,
                    purchaseState: old.purchaseState,
                    lastErrorMessage: nil
                )
            }
        } catch {
            let msg = error.localizedDescription
            updateSnapshot { old in
                StoreSnapshot(
                    networkAvailable: old.networkAvailable,
                    availability: old.networkAvailable ? .available : .unavailable,
                    productsState: .failed,
                    products: old.products,
                    subscriptionState: old.subscriptionState,
                    purchaseState: old.purchaseState,
                    lastErrorMessage: msg
                )
            }
        }
    }

    @MainActor
    func refreshSubscriptionState() async {
        var newState: SubscriptionState = .inactive

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                newState = .active
                break
            }
        }

        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.availability,
                productsState: old.productsState,
                products: old.products,
                subscriptionState: newState,
                purchaseState: old.purchaseState,
                lastErrorMessage: old.lastErrorMessage
            )
        }
    }

    @objc(purchaseWithProductID:completion:)
    func purchaseWithProductID(_ productID: String,
                               completion: @escaping (PurchaseFlowState) -> Void) {
        let box = CompletionBox<PurchaseFlowState>(completion)

        Task { @MainActor [weak self] in
            guard let self else { box.block(.failed); return }
            let st = await self.purchaseAsync(productID: productID)
            box.block(st)
        }
    }

    @objc(restoreWithCompletion:)
    func restoreWithCompletion(_ completion: @escaping (PurchaseFlowState) -> Void) {
        let box = CompletionBox<PurchaseFlowState>(completion)

        Task { @MainActor [weak self] in
            guard let self else { box.block(.failed); return }
            let st = await self.restoreAsync()
            box.block(st)
        }
    }

    @MainActor
    private func purchaseAsync(productID: String) async -> PurchaseFlowState {
        await uploadIAPIdentifiers(reason: "点击购买前")

        if rawProducts.first(where: { $0.id == productID }) == nil, snapshot.networkAvailable {
            await refreshProducts()
        }
        guard let product = rawProducts.first(where: { $0.id == productID }) else {
            setPurchaseState(.failed, err: "Product not loaded")
            return .failed
        }

        setPurchaseState(.purchasing, err: nil)

        do {
            let distinctId = ASIdentifiers.distinctId()
            let token = ASAccountToken.tokenUUID(distinctId: distinctId)
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshSubscriptionState()
                await transaction.finish()
                setPurchaseState(.succeeded, err: nil)
                return .succeeded

            case .pending:
                setPurchaseState(.pending, err: nil)
                return .pending

            case .userCancelled:
                setPurchaseState(.cancelled, err: nil)
                return .cancelled

            @unknown default:
                setPurchaseState(.failed, err: "Unknown purchase result")
                return .failed
            }
        } catch {
            setPurchaseState(.failed, err: error.localizedDescription)
            return .failed
        }
    }

    @MainActor
    private func restoreAsync() async -> PurchaseFlowState {
        setPurchaseState(.restoring, err: nil)
        do { try await AppStore.sync() } catch { }
        await refreshSubscriptionState()

        let ok = (snapshot.subscriptionState == .active)
        setPurchaseState(ok ? .restored : .failed, err: ok ? nil : "No active subscription found")
        return ok ? .restored : .failed
    }

    // MARK: - Transaction updates
    private func listenForTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if Task.isCancelled { return }
                if case .verified(let transaction) = update {
                    await self.refreshSubscriptionState()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Network / Foreground
    private func startNetworkMonitor() {
        if pathMonitor != nil { return }

        let monitor = NWPathMonitor()
        self.pathMonitor = monitor

        let box = WeakBox(self)
        monitor.pathUpdateHandler = { path in
            guard let self = box.value else { return }
            let available = (path.status == .satisfied)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateNetwork(available: available)
                if available {
                    await self.refreshIfNeededAfterNetworkBack()
                }
            }
        }

        monitor.start(queue: pathQueue)
    }

    private func observeAppForeground() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func onAppWillEnterForeground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshIfNeededAfterNetworkBack()
        }
    }

    @MainActor
    private func refreshIfNeededAfterNetworkBack() async {
        if isRefreshingAfterNetwork { return }
        isRefreshingAfterNetwork = true
        defer { isRefreshingAfterNetwork = false }

        await refreshProducts()
        if snapshot.subscriptionState == .unknown {
            await refreshSubscriptionState()
        }
    }

    // MARK: - Snapshot updates
    @MainActor
    private func updateNetwork(available: Bool) {
        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: available,
                availability: available ? .available : .unavailable,
                productsState: old.productsState,
                products: old.products,
                subscriptionState: old.subscriptionState,
                purchaseState: old.purchaseState,
                lastErrorMessage: old.lastErrorMessage
            )
        }
    }

    @MainActor
    private func setPurchaseState(_ st: PurchaseFlowState, err: String?) {
        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.availability,
                productsState: old.productsState,
                products: old.products,
                subscriptionState: old.subscriptionState,
                purchaseState: st,
                lastErrorMessage: err
            )
        }
    }

    @MainActor
    private func updateSnapshot(_ transform: (StoreSnapshot) -> StoreSnapshot) {
        let old = snapshot
        let new = transform(old)
        snapshot = new

        NotificationCenter.default.post(name: .storeSnapshotChanged, object: new)

        if old.subscriptionState != new.subscriptionState {
            NotificationCenter.default.post(name: .subscriptionStateChanged, object: new.subscriptionState)
        }

        if old.purchaseState != new.purchaseState || old.lastErrorMessage != new.lastErrorMessage {
            NotificationCenter.default.post(
                name: .purchaseStateChanged,
                object: new.purchaseState,
                userInfo: ["error": new.lastErrorMessage as Any]
            )
        }
    }

    // MARK: - Verify
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}

extension StoreKit2Manager: @unchecked Sendable {}
