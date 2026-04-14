import Foundation

// MARK: - RestTimerSettings

struct RestTimerSettings: Codable, Hashable {
    var enabled: Bool = true
    var durationSeconds: Int = 90

    enum CodingKeys: String, CodingKey {
        case enabled
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - NotificationSettings

struct NotificationSettings: Codable, Hashable {
    var exerciseGoalReminders: Bool = true
    var frequencyReminders: Bool = true

    enum CodingKeys: String, CodingKey {
        case exerciseGoalReminders = "exercise_goal_reminders"
        case frequencyReminders = "frequency_reminders"
    }
}

// MARK: - UserSettings

struct UserSettings: Codable, Hashable {
    var weightUnit: String = "kg"
    var defaultWeightIncrement: Double = 2.5
    var distanceUnit: String = "km"
    var weekStartsOn: String = "monday"
    var theme: String = "dark"
    var restTimer: RestTimerSettings = .init()
    var weeklyFrequencyGoal: Int? = nil
    var notifications: NotificationSettings = .init()

    static let `default` = UserSettings()

    enum CodingKeys: String, CodingKey {
        case theme
        case weightUnit = "weight_unit"
        case defaultWeightIncrement = "default_weight_increment"
        case distanceUnit = "distance_unit"
        case weekStartsOn = "week_starts_on"
        case restTimer = "rest_timer"
        case weeklyFrequencyGoal = "weekly_frequency_goal"
        case notifications
    }
}
