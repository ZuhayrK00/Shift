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
        updatedAt: Date()
    )
}
