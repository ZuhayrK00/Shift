import Foundation
import StoreKit

// MARK: - Product identifiers

enum StoreProduct: String, CaseIterable {
    case monthlyPro = "com.zuhayrk.shift.pro.monthly"
    case yearlyPro = "com.zuhayrk.shift.pro.yearly"
}

// MARK: - StoreService

@Observable
final class StoreService {

    static let shared = StoreService()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false

    /// True when the user has an active Pro subscription (monthly or yearly).
    var isPro: Bool {
        purchasedProductIDs.contains(StoreProduct.monthlyPro.rawValue)
            || purchasedProductIDs.contains(StoreProduct.yearlyPro.rawValue)
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await updatePurchasedProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        do {
            let ids = StoreProduct.allCases.map(\.rawValue)
            print("[StoreService] Requesting products with IDs: \(ids)")
            let fetched = try await Product.products(for: ids)
            print("[StoreService] Fetched \(fetched.count) products: \(fetched.map(\.id))")
            await MainActor.run {
                // Sort so monthly comes first
                self.products = fetched.sorted { a, b in
                    a.price < b.price
                }
                self.isLoading = false
            }
        } catch {
            print("[StoreService] Failed to load products: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Entitlement check

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }

        await MainActor.run {
            self.purchasedProductIDs = purchased
        }

        // Sync Pro status to App Group so widgets/complications can check
        UserDefaults(suiteName: "group.com.zuhayrk.shift")?.set(isPro, forKey: "isPro")

        // Sync Pro status to watch
        PhoneSessionManager.shared.sendContextToWatch()
    }

    // MARK: - Transaction listener

    /// Listens for transactions that complete outside the app (e.g. Ask to Buy, renewals).
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.verificationFailed
        }
    }

    func monthlyProduct() -> Product? {
        products.first { $0.id == StoreProduct.monthlyPro.rawValue }
    }

    func yearlyProduct() -> Product? {
        products.first { $0.id == StoreProduct.yearlyPro.rawValue }
    }
}

// MARK: - StoreError

enum StoreError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed."
        }
    }
}
