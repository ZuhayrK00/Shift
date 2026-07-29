import Foundation
import StoreKit
import WidgetKit

// MARK: - StoreService

@Observable
final class StoreService {

    static let shared = StoreService()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var introOfferEligibleProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var isCheckingEntitlement = true
    private(set) var lastStoreError: String?

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
        await MainActor.run {
            isLoading = true
            lastStoreError = nil
        }
        do {
            let ids = StoreProduct.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            var eligibleProductIDs: Set<String> = []
            for product in fetched {
                guard let subscription = product.subscription,
                      subscription.introductoryOffer != nil,
                      await subscription.isEligibleForIntroOffer else { continue }
                eligibleProductIDs.insert(product.id)
            }
            let eligibleIDs = eligibleProductIDs
            await MainActor.run {
                self.products = fetched.sorted { a, b in
                    a.price < b.price
                }
                self.introOfferEligibleProductIDs = eligibleIDs
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.lastStoreError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        case pending
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return .purchased

        case .userCancelled:
            return .cancelled

        case .pending:
            return .pending

        @unknown default:
            return .cancelled
        }
    }

    // MARK: - Restore

    @discardableResult
    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        await updatePurchasedProducts()
        return isPro
    }

    // MARK: - Entitlement check

    func updatePurchasedProducts(syncWatch: Bool = true) async {
        let wasPro = isPro
        let snapshot = await StoreEntitlementVerifier.currentSnapshot()
        let purchased = snapshot.activeProductIDs

        let purchasedIDs = purchased
        await MainActor.run {
            self.purchasedProductIDs = purchasedIDs
            self.isCheckingEntitlement = false
            self.lastStoreError = nil
        }
        StoreEntitlementCache.write(snapshot)

        updateWidgetEntitlementCache()

        if wasPro != isPro {
            WidgetCenter.shared.reloadAllTimelines()
            if isPro, authManager.currentUserId != nil {
                Task { await WidgetDataService.updateSnapshot(knownProStatus: true) }
            }
        }

        if syncWatch {
            PhoneSessionManager.shared.sendContextToWatch()
        }
    }

    /// Resets cached state on sign out so another user doesn't inherit Pro status.
    func reset() async {
        await MainActor.run {
            self.purchasedProductIDs = []
            self.products = []
            self.introOfferEligibleProductIDs = []
            self.isCheckingEntitlement = false
        }
        WidgetSnapshot.clearSharedState()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneSessionManager.shared.sendSignedOutStateToWatch()
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

    // MARK: - Standalone entitlement check

    /// Verifies Pro entitlement directly from StoreKit without requiring the
    /// singleton to have been refreshed. Safe to call from background contexts
    /// (WidgetDataService, HealthKit wake, watch sync handler).
    /// Writes the result to the App Group so widgets/complications stay current.
    static func verifyProEntitlement() async -> Bool {
        await StoreEntitlementVerifier.currentSnapshot().isPro
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

    func isEligibleForIntroOffer(_ product: Product) -> Bool {
        introOfferEligibleProductIDs.contains(product.id)
    }

    private func updateWidgetEntitlementCache() {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        let hasSignedInUser = authManager.currentUserId != nil
        defaults?.set(isPro && hasSignedInUser, forKey: "isPro")
        if !hasSignedInUser {
            WidgetSnapshot.clearSharedState()
        }
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

enum ProFeaturePolicy {
    static let freePlanLimit = 3

    static func canCreatePlan(existingPlanCount: Int, isPro: Bool) -> Bool {
        isPro || existingPlanCount < freePlanLimit
    }
}
