import Foundation
import StoreKit
import Network
import UIKit

@objcMembers
public final class ASProductIDs: NSObject {
    public static let subWeekly: String = "com.demo.pro.weekly"
    public static let subYearly: String = "com.demo.pro.yearly"
}

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

@objcMembers
final class SK2ProductModel: NSObject {
    let productID: String
    let displayName: String
    let displayPrice: String

    @nonobjc private let raw: Product

    init(raw: Product) {
        self.raw = raw
        self.productID = raw.id
        self.displayName = raw.displayName
        self.displayPrice = raw.displayPrice
        super.init()
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

final class StoreKit2Manager: NSObject {

    @objc static let shared = StoreKit2Manager()

    let productIDs: [String] = [subWeekly,subYearly]

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
            let models = list.map { SK2ProductModel(raw: $0) }

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
        if rawProducts.first(where: { $0.id == productID }) == nil, snapshot.networkAvailable {
            await refreshProducts()
        }
        guard let product = rawProducts.first(where: { $0.id == productID }) else {
            setPurchaseState(.failed, err: "Product not loaded")
            return .failed
        }

        setPurchaseState(.purchasing, err: nil)

        do {
            let result = try await product.purchase()
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
