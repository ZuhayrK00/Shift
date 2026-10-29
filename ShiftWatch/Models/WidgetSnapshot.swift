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

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        defaults?.set(data, forKey: WidgetSnapshot.key)
        defaults?.set(ownerUserId, forKey: WidgetSnapshot.activeUserIdKey)
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
