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
    var recoveryGuidance: Bool = false
    var showDailyActivity: Bool = false

    enum CodingKeys: String, CodingKey {
        case syncWorkouts = "sync_workouts"
        case syncBodyWeight = "sync_body_weight"
        case countExternalWorkouts = "count_external_workouts"
        case recoveryGuidance = "recovery_guidance"
        case showDailyActivity = "show_daily_activity"
    }

    init(
        syncWorkouts: Bool = false,
        syncBodyWeight: Bool = false,
        countExternalWorkouts: Bool = false,
        recoveryGuidance: Bool = false,
        showDailyActivity: Bool = false
    ) {
        self.syncWorkouts = syncWorkouts
        self.syncBodyWeight = syncBodyWeight
        self.countExternalWorkouts = countExternalWorkouts
        self.recoveryGuidance = recoveryGuidance
        self.showDailyActivity = showDailyActivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncWorkouts = (try? container.decode(Bool.self, forKey: .syncWorkouts)) ?? false
        syncBodyWeight = (try? container.decode(Bool.self, forKey: .syncBodyWeight)) ?? false
        countExternalWorkouts =
            (try? container.decode(Bool.self, forKey: .countExternalWorkouts)) ?? false
        recoveryGuidance =
            (try? container.decode(Bool.self, forKey: .recoveryGuidance)) ?? false
        showDailyActivity =
            (try? container.decode(Bool.self, forKey: .showDailyActivity)) ?? false
    }
}

// MARK: - TrainingScheduleSettings

struct TrainingScheduleSettings: Codable, Hashable {
    /// ISO weekday (1 = Monday, 7 = Sunday) to workout plan ID.
    var weeklyPlanIDs: [String: String] = [:]
    /// Local yyyy-MM-dd to a plan ID. An empty value represents a rest day.
    var dateOverrides: [String: String] = [:]

    var isEmpty: Bool { weeklyPlanIDs.isEmpty && dateOverrides.isEmpty }

    func planID(for date: Date, calendar: Calendar = .current) -> String? {
        let key = Self.dateKey(date, calendar: calendar)
        if let override = dateOverrides[key] {
            return override.isEmpty ? nil : override
        }
        let appleWeekday = calendar.component(.weekday, from: date)
        let isoWeekday = appleWeekday == 1 ? 7 : appleWeekday - 1
        guard let weekly = weeklyPlanIDs[String(isoWeekday)] else { return nil }
        return weekly.isEmpty ? nil : weekly
    }

    func hasExplicitRestDay(for date: Date, calendar: Calendar = .current) -> Bool {
        let dateKey = Self.dateKey(date, calendar: calendar)
        if let override = dateOverrides[dateKey] {
            return override.isEmpty
        }
        let appleWeekday = calendar.component(.weekday, from: date)
        let isoWeekday = appleWeekday == 1 ? 7 : appleWeekday - 1
        return weeklyPlanIDs[String(isoWeekday)] == ""
    }

    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
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
    /// ISO weekdays selected for the weekly goal (1 = Monday, 7 = Sunday).
    var weeklyTrainingDays: [Int] = []
    /// Local yyyy-MM-dd when the current day selection became active.
    /// This prevents a newly edited schedule from creating retroactive missed-day alerts.
    var weeklyTrainingDaysEffectiveDate: String? = nil
    var dailyStepGoal: Int? = nil
    var targetWeight: Double? = nil
    var targetWeightDeadline: String? = nil
    var notifications: NotificationSettings = .init()
    var healthKit: HealthKitSettings = .init()
    var trainingSchedule: TrainingScheduleSettings = .init()
    var lockPhotos: Bool = false
    var hasCompletedOnboarding: Bool = false

    static let `default` = UserSettings()

    var normalizedWeeklyTrainingDays: [Int] {
        Array(Set(weeklyTrainingDays.filter { (1...7).contains($0) })).sorted()
    }

    /// Explicit weekdays are the source of truth for new settings. The legacy
    /// integer remains as a fallback for users who have not edited their goal yet.
    var effectiveWeeklyFrequencyGoal: Int? {
        let days = normalizedWeeklyTrainingDays
        if !days.isEmpty { return days.count }
        guard let weeklyFrequencyGoal, weeklyFrequencyGoal > 0 else { return nil }
        return min(weeklyFrequencyGoal, 7)
    }

    func weeklyTrainingDaysWereEffective(
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let effectiveDate = weeklyTrainingDaysEffectiveDate,
              !effectiveDate.isEmpty else { return true }
        return TrainingScheduleSettings.dateKey(date, calendar: calendar) >= effectiveDate
    }

    enum CodingKeys: String, CodingKey {
        case theme
        case weightUnit = "weight_unit"
        case defaultWeightIncrement = "default_weight_increment"
        case distanceUnit = "distance_unit"
        case measurementUnit = "measurement_unit"
        case weekStartsOn = "week_starts_on"
        case restTimer = "rest_timer"
        case weeklyFrequencyGoal = "weekly_frequency_goal"
        case weeklyTrainingDays = "weekly_training_days"
        case weeklyTrainingDaysEffectiveDate = "weekly_training_days_effective_date"
        case dailyStepGoal = "daily_step_goal"
        case targetWeight = "target_weight"
        case targetWeightDeadline = "target_weight_deadline"
        case notifications
        case healthKit = "health_kit"
        case trainingSchedule = "training_schedule"
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
        weeklyTrainingDays =
            (try? container.decode([Int].self, forKey: .weeklyTrainingDays)) ?? []
        weeklyTrainingDays = Array(
            Set(weeklyTrainingDays.filter { (1...7).contains($0) })
        ).sorted()
        weeklyTrainingDaysEffectiveDate =
            try? container.decode(String.self, forKey: .weeklyTrainingDaysEffectiveDate)
        dailyStepGoal = try? container.decode(Int.self, forKey: .dailyStepGoal)
        targetWeight = try? container.decode(Double.self, forKey: .targetWeight)
        targetWeightDeadline = try? container.decode(String.self, forKey: .targetWeightDeadline)
        notifications = (try? container.decode(NotificationSettings.self, forKey: .notifications)) ?? .init()
        healthKit = (try? container.decode(HealthKitSettings.self, forKey: .healthKit)) ?? .init()
        trainingSchedule =
            (try? container.decode(TrainingScheduleSettings.self, forKey: .trainingSchedule))
            ?? .init()
        lockPhotos = (try? container.decode(Bool.self, forKey: .lockPhotos)) ?? false
        hasCompletedOnboarding = (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
    }

    init() {}
}

enum WeeklyTrainingScheduleDefaults {
    /// Balanced defaults for legacy numeric goals. They are shown for editing,
    /// but are not persisted until the user confirms the selected days.
    static func days(for target: Int?) -> [Int] {
        switch min(max(target ?? 3, 1), 7) {
        case 1: return [3]
        case 2: return [2, 5]
        case 3: return [1, 3, 5]
        case 4: return [1, 2, 4, 6]
        case 5: return [1, 2, 3, 5, 6]
        case 6: return [1, 2, 3, 4, 5, 6]
        default: return Array(1...7)
        }
    }
}
