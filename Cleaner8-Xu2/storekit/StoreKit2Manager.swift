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
    case unavailable
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

    public let currencyCode: String
    public let currencySymbol: String

    public let priceValue: NSDecimalNumber

    public init(product: Product) {
        productID = product.id
        displayPrice = product.displayPrice
        displayName = product.displayName

        currencyCode = product.priceFormatStyle.currencyCode
        currencySymbol = product.priceFormatStyle.locale.currencySymbol ?? ""
        priceValue = NSDecimalNumber(decimal: product.price)

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
            if product.id == AppConstants.productIDWeekly {
                periodValue = 1
                periodUnit = .week
            } else if product.id == AppConstants.productIDYearly {
                periodValue = 1
                periodUnit = .year
            } else {
                periodValue = 0
                periodUnit = .unknown
            }
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

    let lastOrderID: String?

    init(networkAvailable: Bool,
         availability: StoreAvailability,
         productsState: ProductsLoadState,
         products: [SK2ProductModel],
         subscriptionState: SubscriptionState,
         purchaseState: PurchaseFlowState,
         lastErrorMessage: String?,
         lastOrderID: String?) {

        self.networkAvailable = networkAvailable
        self.availability = availability
        self.productsState = productsState
        self.products = products
        self.subscriptionState = subscriptionState
        self.purchaseState = purchaseState
        self.lastErrorMessage = lastErrorMessage
        self.lastOrderID = lastOrderID
        super.init()
    }
}

private enum ASAccountToken {
    static let tokenKey = "as_app_account_token"
    static let distinctKey = "as_app_account_token_distinctid"

    static func tokenUUID(distinctId: String?) -> UUID {
        let defaults = UserDefaults.standard

        if let d = distinctId, !d.isEmpty,
           defaults.string(forKey: distinctKey) == d,
           let saved = defaults.string(forKey: tokenKey),
           let uuid = UUID(uuidString: saved) {
            return uuid
        }

        guard let d = distinctId, !d.isEmpty else {
            if defaults.string(forKey: distinctKey) == "",
               let saved = defaults.string(forKey: tokenKey),
               let uuid = UUID(uuidString: saved) {
                return uuid
            }
            let uuid = UUID()
            defaults.set(uuid.uuidString, forKey: tokenKey)
            defaults.set("", forKey: distinctKey)
            return uuid
        }

        let uuid = stableUUID(from: d)

        defaults.set(uuid.uuidString, forKey: tokenKey)
        defaults.set(d, forKey: distinctKey)
        return uuid
    }

    private static func stableUUID(from input: String) -> UUID {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest)

        var b = Array(bytes[0..<16])
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80

        return UUID(uuid: (
            b[0], b[1], b[2], b[3],
            b[4], b[5],
            b[6], b[7],
            b[8], b[9],
            b[10], b[11], b[12], b[13], b[14], b[15]
        ))
        #else
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
        return TDAnalytics.getDistinctId().uppercased()
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

@MainActor
final class StoreKit2Manager: NSObject {

    private var iapUploadURL: URL? {
        return URL(string: AppConstants.iapUploadURL + "/iap/upload")
    }
    
    @MainActor
    private var isRefreshingProducts = false

    private var lastNetworkAvailable: Bool? = nil

    private func logCN(_ msg: String) {
        #if DEBUG
        print("[内购标识上传] \(msg)")
        #endif
    }
    
    @MainActor
    private var productWaiters: [CheckedContinuation<Void, Never>] = []

    @objc func uploadIAPIdentifiersOnEnterPaywall() {
        Task { await self.uploadIAPIdentifiers(reason: "进入内购页") }
    }

    @objc func uploadIAPIdentifiersBeforePurchaseTap() {
        Task { await self.uploadIAPIdentifiers(reason: "点击购买前") }
    }

    @MainActor private func fmt(_ date: Date?) -> String {
        guard let d = date else { return "nil" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
    }
    
    @MainActor
    private func paywallRank(for product: Product) -> Int {
        if product.id == AppConstants.productIDWeekly { return 0 }
        if product.id == AppConstants.productIDYearly { return 1 }
        
        guard let p = product.subscription?.subscriptionPeriod else { return 99 }
        switch p.unit {
        case .week: return 0
        case .year: return 1
        case .month: return 2
        case .day: return 3
        @unknown default: return 99
        }
    }

    @MainActor
    private func sortPaywallProducts(_ list: [Product]) -> [Product] {
        return list.sorted { a, b in
            let ra = paywallRank(for: a)
            let rb = paywallRank(for: b)
            if ra != rb { return ra < rb }
            // 同 rank 用 id 做稳定排序，避免顺序抖动
            return a.id < b.id
        }
    }

    private func uploadIAPIdentifiers(reason: String) async {
        guard let url = iapUploadURL else {
            logCN("失败：iapUploadURL 未配置")
            return
        }

        let idfv = ASIdentifiers.idfv()
        
        let body: [String: Any] = [
            "bundleid": ASIdentifiers.bundleId(),
            "distinctid": ASIdentifiers.distinctId(),
            "appsflyer_id": ASIdentifiers.appsFlyerId(),
            "idfa": ASIdentifiers.idfa(),
            "idfv": idfv
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

    let productIDs: [String] = [AppConstants.productIDYearly,AppConstants.productIDWeekly]

    @objc private(set) var snapshot: StoreSnapshot = StoreSnapshot(
        networkAvailable: true,
        availability: .unknown,
        productsState: .idle,
        products: [],
        subscriptionState: .unknown,
        purchaseState: .idle,
        lastErrorMessage: nil,
        lastOrderID: nil
    )
    
    @objc let canPay: Bool = {
        if #available(iOS 15.0, *) {
            return AppStore.canMakePayments
        } else {
            return SKPaymentQueue.canMakePayments()
        }
    }()
        
    @objc var state: SubscriptionState { snapshot.subscriptionState }

    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "xx.sk2.network.monitor")
    private var isStarted = false
    private var rawProducts: [Product] = []
    private var updatesTask: Task<Void, Never>?
    private var isRefreshingAfterNetwork = false

    @objc func start() {
        guard !isStarted else { return }
        isStarted = true

        startNetworkMonitor()
        observeAppForeground()

        listenForTransactionUpdates()
        listenForStorefrontUpdates()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshAll(reason: "start")
        }
    }

    @MainActor
    func refreshAll(reason: String) async {
        async let p: () = refreshProducts()
        async let s: () = refreshSubscriptionState()
        _ = await (p, s)
    }

    // MARK: - Products 刷新
    
    @MainActor
    func refreshProducts(force: Bool = false) async {
        if isRefreshingProducts {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                productWaiters.append(cont)
            }
            return
        }

        let now = Date()

        // 失败退避：避免连续失败疯狂刷
        if !force,
           snapshot.productsState == .failed,
           let lastTry = lastProductsAttemptAt,
           now.timeIntervalSince(lastTry) < minProductsRetryInterval {
           return
        }

        // TTL/状态判断
        if !shouldRefreshProducts(force: force, now: now) {
            return
        }

        lastProductsAttemptAt = now
        isRefreshingProducts = true
        defer {
            isRefreshingProducts = false

            let waiters = productWaiters
            productWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        print("开始获取商品")

        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.networkAvailable ? .available : .unavailable,
                productsState: .loading,
                products: old.products,
                subscriptionState: old.subscriptionState,
                purchaseState: old.purchaseState,
                lastErrorMessage: nil,
                lastOrderID: old.lastOrderID
            )
        }

        do {
//            try? await Task.sleep(nanoseconds: UInt64(10 * 1_000_000_000))
            let list = try await Product.products(for: productIDs)
            guard !list.isEmpty else {
                updateSnapshot { old in
                    StoreSnapshot(
                        networkAvailable: old.networkAvailable,
                        availability: old.networkAvailable ? .available : .unavailable,
                        productsState: .failed,
                        products: old.products,
                        subscriptionState: old.subscriptionState,
                        purchaseState: old.purchaseState,
                        lastErrorMessage: "No products returned",
                        lastOrderID: old.lastOrderID
                    )
                }
                return
            }
            let sortedList = sortPaywallProducts(list)

            self.rawProducts = sortedList
            let models = sortedList.map { SK2ProductModel(product: $0) }

            lastProductsSuccessAt = Date()

            for product in list {
                print("获取商品成功 \(product.displayName): \(product.displayPrice) \(product.priceFormatStyle.currencyCode)")
            }
            updateSnapshot { old in
                StoreSnapshot(
                    networkAvailable: old.networkAvailable,
                    availability: old.networkAvailable ? .available : .unavailable,
                    productsState: .ready,
                    products: models,
                    subscriptionState: old.subscriptionState,
                    purchaseState: old.purchaseState,
                    lastErrorMessage: nil,
                    lastOrderID: old.lastOrderID
                )
            }
        } catch {
            print("获取商品失败 \(error)")
            let msg = error.localizedDescription
            updateSnapshot { old in
                StoreSnapshot(
                    networkAvailable: old.networkAvailable,
                    availability: old.networkAvailable ? .available : .unavailable,
                    productsState: .failed,
                    products: old.products,
                    subscriptionState: old.subscriptionState,
                    purchaseState: old.purchaseState,
                    lastErrorMessage: msg,
                    lastOrderID: old.lastOrderID
                )
            }
        }
    }

    @objc func forceRefreshProducts() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshProducts(force: true)
        }
    }
    
    @objc func forceRefreshSubscriptionState() {
        Task { @MainActor [weak self] in
            await self?.refreshSubscriptionState(force: true)
        }
    }

    @MainActor
    func refreshSubscriptionState(force: Bool = false) async {
        let now = Date()

        // 防抖：避免瞬间重复调用
        if !force,
           let lastTry = lastEntitlementsAttemptAt,
           now.timeIntervalSince(lastTry) < minEntitlementsRetryInterval {
           return
        }

        if !shouldRefreshEntitlements(force: force, now: now) {
            return
        }

        lastEntitlementsAttemptAt = now
        let oldState = snapshot.subscriptionState

        var isActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                isActive = true
                break
            }
        }

        // 离线且 unknown：也不急着定性
        if !isActive,
           !snapshot.networkAvailable,
           oldState == .unknown,
           !force {
           lastEntitlementsRefreshAt = now
           return
        }

        let newState: SubscriptionState = isActive ? .active : .inactive
        lastEntitlementsRefreshAt = now

        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.availability,
                productsState: old.productsState,
                products: old.products,
                subscriptionState: newState,
                purchaseState: old.purchaseState,
                lastErrorMessage: old.lastErrorMessage,
                lastOrderID: old.lastOrderID
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
        Task { [weak self] in
            await self?.uploadIAPIdentifiers(reason: "点击购买前")
        }
        
        setPurchaseState(.purchasing, err: nil)

        if rawProducts.first(where: { $0.id == productID }) == nil,
           snapshot.networkAvailable {
            await refreshProducts(force: true)
        }

        guard let product = rawProducts.first(where: { $0.id == productID }) else {
            setPurchaseState(.failed, err: "Product not loaded")
            return .failed
        }

        do {
            let distinctId = ASIdentifiers.distinctId()
            let uuid = UUID(uuidString: distinctId) ?? UUID()
            let result = try await product.purchase(options: [.appAccountToken(uuid)])
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)

                let oid: String
                if transaction.originalID != 0 {
                    oid = String(transaction.originalID)       // 订阅链路唯一（续费同一个）
                } else if transaction.id != 0 {
                    oid = String(transaction.id)               // 每笔交易唯一
                } else {
                    oid = String(transaction.id)
                }

                await transaction.finish()
                await refreshSubscriptionState(force: true)

                setPurchaseState(.succeeded, err: nil, orderID: oid)
                return .succeeded

            case .pending:
                setPurchaseState(.pending, err: nil, orderID: nil)
                return .pending

            case .userCancelled:
                setPurchaseState(.cancelled, err: nil, orderID: nil)
                return .cancelled

            @unknown default:
                setPurchaseState(.failed, err: "Unknown purchase result")
                return .failed
            }
        } catch {
            setPurchaseState(.failed, err: error.localizedDescription, orderID: nil)
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
                    await self.refreshSubscriptionState(force: true)
                    await transaction.finish()
                }
            }
        }
    }
    
    private var storefrontTask: Task<Void, Never>?

    private func listenForStorefrontUpdates() {
        storefrontTask?.cancel()
        storefrontTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            if #available(iOS 15.0, *) {
                for await _ in Storefront.updates {
                    if Task.isCancelled { return }
                    await self.refreshProducts(force: true) // 换区/换账号，强制刷新价格
                }
            }
        }
    }

    // MARK: - Refresh Policy

    @MainActor private var lastProductsSuccessAt: Date? = nil
    @MainActor private var lastProductsAttemptAt: Date? = nil
    @MainActor private var lastEntitlementsRefreshAt: Date? = nil
    @MainActor private var lastEntitlementsAttemptAt: Date? = nil

    private let productsTTL: TimeInterval = 1 * 60        // 商品信息 1 分钟内不刷新
    private let entitlementsTTL: TimeInterval = 30             // 订阅状态 30 秒防抖

    private let minProductsRetryInterval: TimeInterval = 10    // 商品失败后最短 10 秒再试
    private let minEntitlementsRetryInterval: TimeInterval = 2 // 订阅刷新最短 2 秒再刷一次（防抖）

    @MainActor
    private func shouldRefreshProducts(force: Bool, now: Date = Date()) -> Bool {
        if force { return true }
        // 没拉过/失败过/本地为空 -> 需要刷新
        if snapshot.productsState == .idle || snapshot.productsState == .failed || rawProducts.isEmpty {
            return true
        }
        // TTL 过期 -> 需要刷新
        if let last = lastProductsSuccessAt, now.timeIntervalSince(last) < productsTTL {
            return false
        }
        return true
    }

    @MainActor
    private func shouldRefreshEntitlements(force: Bool, now: Date = Date()) -> Bool {
        if force { return true }
        if snapshot.subscriptionState == .unknown { return true }
        if let last = lastEntitlementsRefreshAt, now.timeIntervalSince(last) < entitlementsTTL {
            return false
        }
        return true
    }

    @MainActor
    func refreshAllIfStale(reason: String, force: Bool = false) async {
        let now = Date()
        let needProducts = shouldRefreshProducts(force: force, now: now)
        let needEnt = shouldRefreshEntitlements(force: force, now: now)

        if needProducts && needEnt {
            async let p: () = refreshProducts(force: force)
            async let s: () = refreshSubscriptionState(force: force)
            _ = await (p, s)
        } else if needProducts {
            await refreshProducts(force: force)
        } else if needEnt {
            await refreshSubscriptionState(force: force)
        } else {
            
        }
    }

    // MARK: - Network
    private func startNetworkMonitor() {
        if pathMonitor != nil { return }

        let monitor = NWPathMonitor()
        self.pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let available = (path.status == .satisfied)

            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.lastNetworkAvailable == nil {
                    self.lastNetworkAvailable = available
                    self.updateNetwork(available: available)
                    return
                }

                if self.lastNetworkAvailable == available {
                    return
                }

                self.lastNetworkAvailable = available
                self.updateNetwork(available: available)

                // 只有从 “不可用 → 可用” 时才当成网络恢复，触发刷新逻辑
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
            await self.refreshAllIfStale(reason: "foreground")
        }
    }

    @MainActor
    private func refreshIfNeededAfterNetworkBack() async {
        if isRefreshingAfterNetwork { return }
        isRefreshingAfterNetwork = true
        defer { isRefreshingAfterNetwork = false }

        await refreshAllIfStale(reason: "network_back")
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
                lastErrorMessage: old.lastErrorMessage,
                lastOrderID: old.lastOrderID
            )
        }
    }

    @MainActor
    private func setPurchaseState(_ st: PurchaseFlowState, err: String?, orderID: String? = nil) {
        updateSnapshot { old in
            StoreSnapshot(
                networkAvailable: old.networkAvailable,
                availability: old.availability,
                productsState: old.productsState,
                products: old.products,
                subscriptionState: old.subscriptionState,
                purchaseState: st,
                lastErrorMessage: err,
                lastOrderID: orderID
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
            print("[StoreKit2Manager] subscriptionState \(old.subscriptionState) -> \(new.subscriptionState)")

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
