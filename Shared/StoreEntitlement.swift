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
}

enum StoreEntitlementVerifier {
    static func currentSnapshot() async -> StoreEntitlementSnapshot {
        let proProductIDs = Set(StoreProduct.allCases.map(\.rawValue))
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if proProductIDs.contains(transaction.productID) {
                activeProductIDs.insert(transaction.productID)
            }
        }

        return StoreEntitlementSnapshot(
            isPro: !activeProductIDs.isEmpty,
            activeProductIDs: activeProductIDs,
            verifiedAt: Date()
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

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: snapshotKey)
    }
}
