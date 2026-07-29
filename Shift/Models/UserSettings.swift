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
    var exerciseGoalAchievements: Bool = true
    var frequencyGoalAchievements: Bool = true
    var stepGoalAchievements: Bool = true
    var workoutIdleAlerts: Bool = true

    enum CodingKeys: String, CodingKey {
        case exerciseGoalAchievements = "exercise_goal_achievements"
        case frequencyGoalAchievements = "frequency_goal_achievements"
        case stepGoalAchievements = "step_goal_achievements"
        case workoutIdleAlerts = "workout_idle_alerts"

        // Legacy keys retained for a one-way migration from the old scheduled
        // reminder system.
        case legacyExerciseGoalReminders = "exercise_goal_reminders"
        case legacyFrequencyReminders = "frequency_reminders"
        case legacyStepGoalReminders = "step_goal_reminders"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseGoalAchievements =
            (try? container.decode(Bool.self, forKey: .exerciseGoalAchievements))
            ?? (try? container.decode(Bool.self, forKey: .legacyExerciseGoalReminders))
            ?? true
        frequencyGoalAchievements =
            (try? container.decode(Bool.self, forKey: .frequencyGoalAchievements))
            ?? (try? container.decode(Bool.self, forKey: .legacyFrequencyReminders))
            ?? true
        stepGoalAchievements =
            (try? container.decode(Bool.self, forKey: .stepGoalAchievements))
            ?? (try? container.decode(Bool.self, forKey: .legacyStepGoalReminders))
            ?? true
        workoutIdleAlerts =
            (try? container.decode(Bool.self, forKey: .workoutIdleAlerts))
            ?? true
    }

    init() {}

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseGoalAchievements, forKey: .exerciseGoalAchievements)
        try container.encode(frequencyGoalAchievements, forKey: .frequencyGoalAchievements)
        try container.encode(stepGoalAchievements, forKey: .stepGoalAchievements)
        try container.encode(workoutIdleAlerts, forKey: .workoutIdleAlerts)
    }
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
    var targetWeight: Double? = nil
    var targetWeightDeadline: String? = nil
    var notifications: NotificationSettings = .init()
    var healthKit: HealthKitSettings = .init()
    var lockPhotos: Bool = false
    var hasCompletedOnboarding: Bool = false

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
        case targetWeight = "target_weight"
        case targetWeightDeadline = "target_weight_deadline"
        case notifications
        case healthKit = "health_kit"
        case lockPhotos = "lock_photos"
        case hasCompletedOnboarding = "has_completed_onboarding"
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
        targetWeight = try? container.decode(Double.self, forKey: .targetWeight)
        targetWeightDeadline = try? container.decode(String.self, forKey: .targetWeightDeadline)
        notifications = (try? container.decode(NotificationSettings.self, forKey: .notifications)) ?? .init()
        healthKit = (try? container.decode(HealthKitSettings.self, forKey: .healthKit)) ?? .init()
        lockPhotos = (try? container.decode(Bool.self, forKey: .lockPhotos)) ?? false
        hasCompletedOnboarding = (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
    }

    init() {}
}
