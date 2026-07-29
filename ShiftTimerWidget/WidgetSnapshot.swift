import Foundation

/// Mirror of the main app's WidgetSnapshot — kept in sync manually.
/// Reads the shared snapshot from the App Group UserDefaults.
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
    static let activeUserIdKey = "widgetActiveUserId.v2"

    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let activeUserId = defaults.string(forKey: activeUserIdKey),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.ownerUserId == activeUserId else { return nil }
        return snapshot.normalized(for: Date())
    }

    static var isProUser: Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: activeUserIdKey) != nil else { return false }
        return defaults.bool(forKey: "isPro")
    }

    /// Refreshes StoreKit directly inside the widget extension. This prevents
    /// widget access from depending on the iPhone app having launched recently.
    static func refreshProEntitlement() async -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: activeUserIdKey) != nil else { return false }
        let isPro = (await StoreEntitlementVerifier.currentSnapshot()).isPro
        defaults.set(isPro, forKey: "isPro")
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

    static let placeholder = WidgetSnapshot(
        workoutsThisWeek: 3,
        weeklyGoal: 5,
        stepsToday: 6420,
        stepGoal: 10000,
        workedOutToday: true,
        latestWeight: 75.0,
        latestWeightUnit: "kg",
        weightTrend: [],
        currentStreak: 4,
        streakUnit: "days",
        updatedAt: Date(),
        ownerUserId: "preview",
        weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start,
        schemaVersion: 2
    )
}
