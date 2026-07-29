import Foundation

/// Lightweight data snapshot shared between the main app and widget extension
/// via UserDefaults(suiteName:). The main app writes it; widgets read it.
struct WidgetSnapshot: Codable {
    // Weekly Progress
    var workoutsThisWeek: Int
    var weeklyGoal: Int?

    // Today's Activity
    var stepsToday: Int
    var stepGoal: Int?
    var workedOutToday: Bool

    // Weight Trend
    var latestWeight: Double?
    var latestWeightUnit: String
    var weightTrend: [WeightPoint]

    // Streak
    var currentStreak: Int
    var streakUnit: String // "days" or "weeks"

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

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        defaults?.set(data, forKey: WidgetSnapshot.key)
        if let ownerUserId {
            defaults?.set(ownerUserId, forKey: WidgetSnapshot.activeUserIdKey)
        }
    }

    static func setActiveUserId(_ userId: String) {
        UserDefaults(suiteName: suiteName)?.set(userId, forKey: activeUserIdKey)
    }

    static func clearSnapshot() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }

    static func clearSharedState() {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removeObject(forKey: key)
        defaults?.removeObject(forKey: activeUserIdKey)
        defaults?.set(false, forKey: "isPro")
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
