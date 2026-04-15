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

// MARK: - HealthKitSettings

struct HealthKitSettings: Codable, Hashable {
    var syncWorkouts: Bool = false
    var syncBodyWeight: Bool = false
    var countExternalWorkouts: Bool = false

    enum CodingKeys: String, CodingKey {
        case syncWorkouts = "sync_workouts"
        case syncBodyWeight = "sync_body_weight"
        case countExternalWorkouts = "count_external_workouts"
    }
}

// MARK: - NotificationSettings

struct NotificationSettings: Codable, Hashable {
    var exerciseGoalReminders: Bool = true
    var frequencyReminders: Bool = true
    var stepGoalReminders: Bool = true
    var progressReminders: Bool = true

    enum CodingKeys: String, CodingKey {
        case exerciseGoalReminders = "exercise_goal_reminders"
        case frequencyReminders = "frequency_reminders"
        case stepGoalReminders = "step_goal_reminders"
        case progressReminders = "progress_reminders"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseGoalReminders = (try? container.decode(Bool.self, forKey: .exerciseGoalReminders)) ?? true
        frequencyReminders = (try? container.decode(Bool.self, forKey: .frequencyReminders)) ?? true
        stepGoalReminders = (try? container.decode(Bool.self, forKey: .stepGoalReminders)) ?? true
        progressReminders = (try? container.decode(Bool.self, forKey: .progressReminders)) ?? true
    }

    init() {}
}

// MARK: - UserSettings

struct UserSettings: Codable, Hashable {
    var weightUnit: String = "kg"
    var defaultWeightIncrement: Double = 2.5
    var distanceUnit: String = "km"
    var measurementUnit: String = "cm"
    var weekStartsOn: String = "monday"
    var theme: String = "dark"
    var restTimer: RestTimerSettings = .init()
    var weeklyFrequencyGoal: Int? = nil
    var dailyStepGoal: Int? = nil
    var notifications: NotificationSettings = .init()
    var healthKit: HealthKitSettings = .init()
    var lockPhotos: Bool = false

    static let `default` = UserSettings()

    enum CodingKeys: String, CodingKey {
        case theme
        case weightUnit = "weight_unit"
        case defaultWeightIncrement = "default_weight_increment"
        case distanceUnit = "distance_unit"
        case measurementUnit = "measurement_unit"
        case weekStartsOn = "week_starts_on"
        case restTimer = "rest_timer"
        case weeklyFrequencyGoal = "weekly_frequency_goal"
        case dailyStepGoal = "daily_step_goal"
        case notifications
        case healthKit = "health_kit"
        case lockPhotos = "lock_photos"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weightUnit = (try? container.decode(String.self, forKey: .weightUnit)) ?? "kg"
        defaultWeightIncrement = (try? container.decode(Double.self, forKey: .defaultWeightIncrement)) ?? 2.5
        distanceUnit = (try? container.decode(String.self, forKey: .distanceUnit)) ?? "km"
        measurementUnit = (try? container.decode(String.self, forKey: .measurementUnit)) ?? "cm"
        weekStartsOn = (try? container.decode(String.self, forKey: .weekStartsOn)) ?? "monday"
        theme = (try? container.decode(String.self, forKey: .theme)) ?? "dark"
        restTimer = (try? container.decode(RestTimerSettings.self, forKey: .restTimer)) ?? .init()
        weeklyFrequencyGoal = try? container.decode(Int.self, forKey: .weeklyFrequencyGoal)
        dailyStepGoal = try? container.decode(Int.self, forKey: .dailyStepGoal)
        notifications = (try? container.decode(NotificationSettings.self, forKey: .notifications)) ?? .init()
        healthKit = (try? container.decode(HealthKitSettings.self, forKey: .healthKit)) ?? .init()
        lockPhotos = (try? container.decode(Bool.self, forKey: .lockPhotos)) ?? false
    }

    init() {}
}
