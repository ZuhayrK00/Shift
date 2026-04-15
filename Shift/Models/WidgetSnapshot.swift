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

    struct WeightPoint: Codable {
        var weight: Double
        var date: Date
    }

    static let suiteName = "group.com.zuhayrk.shift"
    static let key = "widgetSnapshot"

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WidgetSnapshot.suiteName)?.set(data, forKey: WidgetSnapshot.key)
    }
}
