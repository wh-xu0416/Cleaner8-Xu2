import Foundation
import StoreKit
import Network
import UIKit

@objc enum SubscriptionState: Int {
    case unknown
    case inactive
    case active
}

extension Notification.Name {
    static let subscriptionStateChanged = Notification.Name("subscriptionStateChanged")
    static let storeProductsUpdated = Notification.Name("storeProductsUpdated")
    static let storeNetworkChanged = Notification.Name("storeNetworkChanged")
}

final class CompletionBox: @unchecked Sendable {
    let block: (Bool) -> Void
    init(_ block: @escaping (Bool) -> Void) { self.block = block }
}

final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// OC 可见的产品模型（不暴露 StoreKit.Product struct）
@objcMembers
final class SK2ProductModel: NSObject {
    let productID: String
    let displayName: String
    let displayPrice: String

    /// ✅ 你说“价格和符号都要”：这里把符号也拆出来给你
    let currencySymbol: String

    /// 如果你还想要 code（比如 USD/CNY），这里也给一个（来自 priceFormatStyle）
    let currencyCode: String

    fileprivate let raw: Product

    init(raw: Product) {
        self.raw = raw
        self.productID = raw.id
        self.displayName = raw.displayName
        self.displayPrice = raw.displayPrice

        // ✅ currencyCode 通常是 ISO 4217 (如 USD/JPY)，符号用 displayPrice 里提取更贴近商店展示
        self.currencyCode = raw.priceFormatStyle.currencyCode
        self.currencySymbol = SK2ProductModel.extractCurrencySymbol(from: raw.displayPrice)

        super.init()
    }

    /// 从 "¥300" / "$9.99" / "9,99 €" / "PLN 9,99" 等字符串里提取“符号部分”
    private static func extractCurrencySymbol(from displayPrice: String) -> String {
        let s = displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = CharacterSet.decimalDigits

        // 1) 前缀符号（$ / ¥ / PLN 这类）
        if let firstDigit = s.rangeOfCharacter(from: digits) {
            let prefix = String(s[..<firstDigit.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { return prefix }
        }

        // 2) 后缀符号（€ 这类）
        if let lastDigit = s.rangeOfCharacter(from: digits, options: .backwards) {
            let suffix = String(s[lastDigit.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty { return suffix }
        }

        // 3) 兜底：剔除数字/空格后剩余
        let fallback = s.filter { !$0.isNumber && !$0.isWhitespace }
        return fallback
    }
}

@objcMembers
final class StoreKit2Manager: NSObject {
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "xx.sk2.network.monitor")
    private var isRefreshingAfterNetwork = false

    static let shared = StoreKit2Manager()

    let productIDs: [String] = [
        "com.demo.pro.weekly",
        "com.demo.pro.yearly"
    ]

    /// ✅ 网络是否可用（OC 可读）
    @objc private(set) var networkAvailable: Bool = true {
           didSet {
               if oldValue != networkAvailable {
                   postOnMain(.storeNetworkChanged)
               }
           }
       }


    /// OC 用的产品数组
    private(set) var products: [SK2ProductModel] = [] {
        didSet { postOnMain(.storeProductsUpdated) }
    }

    private(set) var state: SubscriptionState = .unknown {
        didSet {
            if oldValue != state { postOnMain(.subscriptionStateChanged) }
        }
    }

    private var isStarted = false
    private var rawProducts: [Product] = []
    private var updatesTask: Task<Void, Never>?

    // MARK: - 启动入口

    func start() {
        guard !isStarted else { return }
        isStarted = true

        startNetworkMonitor()
        observeAppForeground()

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self.refreshProducts()
            await self.refreshSubscriptionState()
            self.listenForTransactionUpdates()
        }
    }

    // MARK: - Products

    @MainActor
    func refreshProducts() async {
        do {
            let list = try await Product.products(for: productIDs)
            self.rawProducts = list
            self.products = list.map { SK2ProductModel(raw: $0) }
        } catch {
            // ✅ 网络波动时不强制清空（避免 UI 抖动）；只有当本来就空才保持空
            if self.products.isEmpty {
                self.rawProducts = []
                self.products = []
            }
        }
    }

    // MARK: - Subscription State

    @MainActor
    func refreshSubscriptionState() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                state = .active
                return
            }
        }
        state = .inactive
    }

    // MARK: - OC 友好的购买/恢复接口（completion）

    @preconcurrency
    func purchase(productID: String, completion: @escaping (Bool) -> Void) {
        let box = CompletionBox(completion)

        Task { @MainActor [weak self] in
            guard let self else { box.block(false); return }
            let ok = await self.purchaseAsync(productID: productID)
            box.block(ok)
        }
    }

    @MainActor
    private func purchaseAsync(productID: String) async -> Bool {
        guard let product = rawProducts.first(where: { $0.id == productID }) else { return false }

        do {
            let result = try await product.purchase()
            if case .success(let verification) = result {
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshSubscriptionState()
                return true
            }
        } catch { }
        return false
    }

    @preconcurrency
    func restore(completion: @escaping (Bool) -> Void) {
        let box = CompletionBox(completion)

        Task { @MainActor [weak self] in
            guard let self else { box.block(false); return }
            let ok = await self.restoreAsync()
            box.block(ok)
        }
    }

    @MainActor
    private func restoreAsync() async -> Bool {
        do { try await AppStore.sync() } catch { }
        await refreshSubscriptionState()
        return state == .active
    }

    // MARK: - Transaction Updates

    private func listenForTransactionUpdates() {
        updatesTask?.cancel()

        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if Task.isCancelled { return }
                if case .verified(_) = update {
                    await self.refreshSubscriptionState()
                }
            }
        }
    }

    // MARK: - Verify

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified:
            throw NSError(domain: "StoreKit2", code: -1)
        }
    }

    // MARK: - Network

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
                self.networkAvailable = available
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

        // ✅ 商品为空才重拉
        if products.isEmpty {
            await refreshProducts()
        }

        // ✅ 状态 unknown/inactive 时顺带刷新
        if state == .unknown || state == .inactive {
            await refreshSubscriptionState()
        }
    }

    // MARK: - Notify on main

    private func postOnMain(_ name: Notification.Name) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: name, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: name, object: nil)
            }
        }
    }
}

extension StoreKit2Manager: @unchecked Sendable {}
