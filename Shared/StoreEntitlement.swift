import Foundation
import StoreKit

enum StoreProduct: String, CaseIterable, Sendable {
    case monthlyPro = "com.zuhayrk.shift.pro.monthly"
    case yearlyPro = "com.zuhayrk.shift.pro.yearly"
}

struct StoreEntitlementSnapshot: Codable, Equatable, Sendable {
    var isPro: Bool
    var activeProductIDs: Set<String>
    var verifiedAt: Date
    /// The end of the verified paid period. A widget or Watch extension can
    /// retain access through this date if its own StoreKit refresh is empty.
    var expiresAt: Date? = nil

    func hasUnexpiredPro(at date: Date = Date()) -> Bool {
        isPro && (expiresAt.map { $0 > date } ?? false)
    }
}

enum StoreEntitlementVerifier {
    static func currentSnapshot() async -> StoreEntitlementSnapshot {
        let proProductIDs = Set(StoreProduct.allCases.map(\.rawValue))
        var activeProductIDs: Set<String> = []
        var expiresAt: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if proProductIDs.contains(transaction.productID) {
                activeProductIDs.insert(transaction.productID)
                if let expirationDate = transaction.expirationDate {
                    expiresAt = max(expiresAt ?? expirationDate, expirationDate)
                }
            }
        }

        return StoreEntitlementSnapshot(
            isPro: !activeProductIDs.isEmpty,
            activeProductIDs: activeProductIDs,
            verifiedAt: Date(),
            expiresAt: expiresAt
        )
    }
}

enum StoreEntitlementCache {
    static let suiteName = "group.com.zuhayrk.shift"
    private static let snapshotKey = "storeEntitlementSnapshot.v2"

    static func read() -> StoreEntitlementSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoreEntitlementSnapshot.self, from: data)
    }

    static func write(_ snapshot: StoreEntitlementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: snapshotKey)
    }

    /// An extension can temporarily see no StoreKit entitlements even while
    /// the containing app has a verified subscription. Preserve that verified
    /// grant only until its known expiry; a positive extension result always
    /// refreshes the grant, and an expired grant is never kept alive by cache.
    static func resolveForExtension(
        _ fresh: StoreEntitlementSnapshot,
        cached: StoreEntitlementSnapshot?,
        at date: Date = Date()
    ) -> StoreEntitlementSnapshot {
        if fresh.isPro { return fresh }
        if let cached, cached.hasUnexpiredPro(at: date) { return cached }
        return fresh
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: snapshotKey)
    }
}
