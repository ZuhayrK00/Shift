import Foundation

/// Widget extension copy of WidgetSnapshot for complications.
/// Reads from App Group UserDefaults written by WatchSessionManager.
struct WidgetSnapshot: Codable {
    var workoutsThisWeek: Int
    var weeklyGoal: Int?
    var stepsToday: Int
    var stepGoal: Int?
    var workedOutToday: Bool
    var latestWeight: Double?
    var latestWeightUnit: String
    var weightTrend: [WeightPoint]
    var currentStreak: Int
    var streakUnit: String
    var updatedAt: Date
    var ownerUserId: String?
    var weekStart: Date?
    var schemaVersion: Int?
    var endurance: EnduranceWidgetData?

    struct WeightPoint: Codable {
        var weight: Double
        var date: Date
    }

    static let suiteName = "group.com.zuhayrk.shift"
    static let key = "widgetSnapshot"
    static let activeUserIdKey = "widgetActiveUserId.v2"

    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName), let owner = defaults.string(forKey: activeUserIdKey),
              let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              value.ownerUserId == owner else { return nil }
        return value.normalized(for: Date())
    }

    static var isProUser: Bool {
        guard read()?.ownerUserId != nil else { return false }
        if let cached = StoreEntitlementCache.read() {
            return cached.hasUnexpiredPro() || (cached.isPro && cached.verifiedAt > Date().addingTimeInterval(-60 * 60))
        }
        return UserDefaults(suiteName: suiteName)?.bool(forKey: "isPro") ?? false
    }

    /// Verifies the subscription from StoreKit in the complication extension,
    /// rather than requiring a recent iPhone or Watch app launch.
    static func refreshProEntitlement() async -> Bool {
        guard read()?.ownerUserId != nil else { return false }
        let fresh = await StoreEntitlementVerifier.currentSnapshot()
        let resolved = StoreEntitlementCache.resolveForExtension(
            fresh,
            cached: StoreEntitlementCache.read()
        )
        StoreEntitlementCache.write(resolved)
        UserDefaults(suiteName: suiteName)?.set(resolved.isPro, forKey: "isPro")
        return resolved.isPro
    }

    func normalized(for date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = self
        if !calendar.isDate(updatedAt, inSameDayAs: date) {
            copy.stepsToday = 0
            copy.workedOutToday = false
        }
        if let weekStart,
           let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart),
           date >= nextWeek {
            copy.workoutsThisWeek = 0
        }
        copy.endurance = endurance?.normalized(at: date, calendar: calendar)
        return copy
    }
}
