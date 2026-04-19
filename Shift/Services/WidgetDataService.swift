import Foundation
import WidgetKit

/// Builds a WidgetSnapshot from the current app state and writes it to the
/// shared App Group so widgets can display fresh data.
struct WidgetDataService {

    static func updateSnapshot() async {
        guard StoreService.shared.isPro else {
            // Clear snapshot so widgets show placeholder
            UserDefaults(suiteName: WidgetSnapshot.suiteName)?.removeObject(forKey: WidgetSnapshot.key)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        guard let userId = authManager.currentUserId else { return }

        // Fall back to local profile cache when woken in the background by HealthKit
        // (authManager.user may not be fully loaded yet)
        let settings: UserSettings
        if let userSettings = authManager.user?.settings {
            settings = userSettings
        } else if let profile = try? await ProfileRepository.findById(userId) {
            settings = profile.settings
        } else {
            settings = .default
        }

        // Weekly progress
        let weekStart = GoalService.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let sessionsThisWeek = (try? await SessionRepository.findCompletedSince(weekStart, userId: userId)) ?? []

        var workoutsThisWeek = sessionsThisWeek.count
        if settings.healthKit.countExternalWorkouts {
            workoutsThisWeek += await HealthKitService.countExternalWorkouts(since: weekStart)
        }

        // Worked out today
        let todayStart = Calendar.current.startOfDay(for: Date())
        let workedOutToday = sessionsThisWeek.contains(where: { $0.startedAt >= todayStart })

        // Steps
        let stepsToday = await HealthKitService.fetchStepsForWidget()

        // Weight trend (last 7 entries)
        let allWeights = (try? await WeightEntryRepository.findAll(userId: userId)) ?? []
        let latestWeight = allWeights.first
        let trendPoints: [WidgetSnapshot.WeightPoint] = allWeights.prefix(7).reversed().map { entry in
            WidgetSnapshot.WeightPoint(weight: entry.weight, date: entry.recordedAt)
        }

        // Streak calculation
        let allCompleted = (try? await SessionRepository.findCompleted(userId: userId)) ?? []
        let streak = calculateStreak(sessions: allCompleted, weekStartsOn: settings.weekStartsOn, weeklyGoal: settings.weeklyFrequencyGoal)

        let snapshot = WidgetSnapshot(
            workoutsThisWeek: workoutsThisWeek,
            weeklyGoal: settings.weeklyFrequencyGoal,
            stepsToday: stepsToday,
            stepGoal: settings.dailyStepGoal,
            workedOutToday: workedOutToday,
            latestWeight: latestWeight?.weight,
            latestWeightUnit: settings.weightUnit,
            weightTrend: trendPoints,
            currentStreak: streak.count,
            streakUnit: streak.unit,
            updatedAt: Date()
        )

        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Streak

    static func calculateStreak(
        sessions: [WorkoutSession],
        weekStartsOn: String = "monday",
        weeklyGoal: Int? = nil
    ) -> (count: Int, unit: String) {
        let cal = Calendar.current

        // Get unique workout dates
        let workoutDates: Set<Date> = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })

        guard !workoutDates.isEmpty else { return (0, "days") }

        // Day streak: consecutive calendar days with a workout, counting back from today
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())

        // Allow today to not have a workout yet — start checking from yesterday
        // if today doesn't have one
        if !workoutDates.contains(checkDate) {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while workoutDates.contains(checkDate) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return (streak, "days")
    }
}
