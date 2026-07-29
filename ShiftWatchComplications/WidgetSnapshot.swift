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

    struct WeightPoint: Codable {
        var weight: Double
        var date: Date
    }

    static let suiteName = "group.com.zuhayrk.shift"
    static let key = "widgetSnapshot"

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data))?
            .normalized(for: Date())
    }

    static var isProUser: Bool {
        UserDefaults(suiteName: suiteName)?.bool(forKey: "isPro") ?? false
    }

    /// Verifies the subscription from StoreKit in the complication extension,
    /// rather than requiring a recent iPhone or Watch app launch.
    static func refreshProEntitlement() async -> Bool {
        guard read()?.ownerUserId != nil else { return false }
        let isPro = (await StoreEntitlementVerifier.currentSnapshot()).isPro
        UserDefaults(suiteName: suiteName)?.set(isPro, forKey: "isPro")
        return isPro
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
        return copy
    }
}
