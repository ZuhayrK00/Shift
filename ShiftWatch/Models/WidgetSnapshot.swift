import Foundation

/// Watch-side copy of WidgetSnapshot for complications.
/// Written by WatchSessionManager from iPhone context data.
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

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WidgetSnapshot.suiteName)?.set(data, forKey: WidgetSnapshot.key)
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
        latestWeight: nil,
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
