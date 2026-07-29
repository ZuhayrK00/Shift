import Foundation

private struct CachedStepNotificationConfiguration: Codable {
    let userId: String
    let goal: Int
    let enabled: Bool
}

private actor NotificationEventLedger {
    static let shared = NotificationEventLedger()

    private let defaults = UserDefaults.standard
    private let prefix = "shift.notification.event."

    @discardableResult
    func deliverOnce(
        eventKey: String,
        identifier: String,
        title: String,
        body: String,
        kind: String,
        userInfo: [String: Any] = [:]
    ) async -> Bool {
        let key = prefix + eventKey
        let now = Date().timeIntervalSince1970
        if let stored = defaults.object(forKey: key) as? Double {
            // Negative timestamps are in-flight reservations. Recover one if
            // the process was terminated during delivery.
            if stored >= 0 || -stored > now - 30 {
                return false
            }
            defaults.removeObject(forKey: key)
        } else if defaults.object(forKey: key) != nil {
            return false
        }

        // Reserve before awaiting the notification center. Actors are
        // re-entrant at suspension points, so this prevents duplicate delivery.
        defaults.set(-now, forKey: key)
        let delivered = await NotificationManager.deliverImmediately(
            identifier: identifier,
            title: title,
            body: body,
            kind: kind,
            userInfo: userInfo
        )
        guard delivered else {
            defaults.removeObject(forKey: key)
            return false
        }

        defaults.set(Date().timeIntervalSince1970, forKey: key)
        removeExpiredEntries()
        return true
    }

    func clear(userId: String) {
        let userPrefix = prefix + userId + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(userPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func removeExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-120 * 24 * 60 * 60).timeIntervalSince1970
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            if let timestamp = value as? Double, timestamp < cutoff {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// Event-driven achievement notifications.
///
/// No calendar or future goal reminders are created here. Step notifications
/// run from HealthKit observer callbacks (best effort in the background), while
/// exercise and weekly achievements run from completed workout events.
enum GoalNotificationService {
    private static let stepCacheKey = "shift.notification.stepConfiguration"

    // MARK: - Configuration lifecycle

    static func prepareForCurrentUser() async {
        await NotificationManager.removeLegacyGoalNotifications()
        await refreshConfiguration()
    }

    static func refreshConfiguration() async {
        guard let userId = authManager.currentUserId else {
            clearStepConfiguration()
            return
        }

        let settings: UserSettings?
        if let user = authManager.user, user.id == userId {
            settings = user.settings
        } else {
            settings = try? await ProfileRepository.findById(userId)?.settings
        }

        guard let settings,
              let goal = settings.dailyStepGoal,
              goal > 0 else {
            clearStepConfiguration()
            return
        }

        cacheStepConfiguration(
            CachedStepNotificationConfiguration(
                userId: userId,
                goal: goal,
                enabled: settings.notifications.stepGoalAchievements
            )
        )
    }

    static func clearUserState(userId: String?) async {
        if let userId {
            await NotificationEventLedger.shared.clear(userId: userId)
        }
        clearStepConfiguration()
        clearLegacyStepState()
        await NotificationManager.removeAllShiftNotifications()
    }

    // MARK: - Step achievement

    static func handleStepCountChange() async {
        guard HealthKitService.isAvailable,
              let userId = authManager.currentUserId,
              let configuration = await resolveStepConfiguration(userId: userId),
              configuration.enabled else { return }

        let now = Date()
        await notifyStepGoalIfReached(
            for: now,
            day: .today,
            userId: userId,
            configuration: configuration
        )

        // HealthKit may deliver a late-evening step change after midnight.
        // Reconcile yesterday briefly after day rollover so a 23:xx goal
        // completion is not silently lost, while avoiding stale daytime alerts.
        if Calendar.current.component(.hour, from: now) < 2,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) {
            await notifyStepGoalIfReached(
                for: yesterday,
                day: .yesterday,
                userId: userId,
                configuration: configuration
            )
        }
    }

    /// Compatibility entry point retained for existing foreground hooks.
    static func checkAndNotifyGoalCompletion() async {
        await handleStepCountChange()
    }

    private static func notifyStepGoalIfReached(
        for date: Date,
        day: NotificationDecisionEngine.StepDay,
        userId: String,
        configuration: CachedStepNotificationConfiguration
    ) async {
        let steps = await HealthKitService.fetchSteps(for: date)
        guard NotificationDecisionEngine.shouldNotifyStepGoal(
            steps: steps,
            goal: configuration.goal
        ) else { return }

        let dayKey = toLocalDateKey(date)
        let message = NotificationDecisionEngine.stepGoalMessage(
            goal: configuration.goal,
            day: day
        )
        await NotificationEventLedger.shared.deliverOnce(
            eventKey: "\(userId).steps.\(dayKey)",
            identifier: "shift.achievement.steps.\(userId).\(dayKey)",
            title: message.title,
            body: message.body,
            kind: "achievement",
            userInfo: ["achievement": "steps"]
        )
    }

    // MARK: - Exercise achievement

    static func notifyExerciseGoalCompleted(_ goal: ExerciseGoal) async {
        guard let userId = authManager.currentUserId,
              goal.userId == userId,
              let settings = await currentSettings(userId: userId),
              settings.notifications.exerciseGoalAchievements else { return }

        let exerciseName = (try? await ExerciseRepository.findById(goal.exerciseId))?.name ?? "Exercise"
        let message = NotificationDecisionEngine.exerciseGoalMessage(
            exerciseName: exerciseName,
            targetWeight: goal.targetWeight,
            unit: settings.weightUnit
        )

        await NotificationEventLedger.shared.deliverOnce(
            eventKey: "\(userId).exercise.\(goal.id)",
            identifier: "shift.achievement.exercise.\(goal.id)",
            title: message.title,
            body: message.body,
            kind: "achievement",
            userInfo: [
                "achievement": "exercise",
                "exerciseId": goal.exerciseId
            ]
        )
    }

    // MARK: - Weekly frequency achievement

    static func notifyFrequencyGoalIfReached() async {
        guard let userId = authManager.currentUserId,
              let settings = await currentSettings(userId: userId),
              settings.notifications.frequencyGoalAchievements,
              let target = settings.weeklyFrequencyGoal,
              let progress = try? await GoalService.getFrequencyProgress(),
              NotificationDecisionEngine.shouldNotifyFrequencyGoal(
                completed: progress.completed,
                target: target
              ) else { return }

        let weekStart = GoalService.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let weekKey = toLocalDateKey(weekStart)
        let message = NotificationDecisionEngine.frequencyGoalMessage(target: target)

        await NotificationEventLedger.shared.deliverOnce(
            eventKey: "\(userId).frequency.\(weekKey).\(target)",
            identifier: "shift.achievement.frequency.\(userId).\(weekKey).\(target)",
            title: message.title,
            body: message.body,
            kind: "achievement",
            userInfo: ["achievement": "frequency"]
        )
    }

    // MARK: - Settings and cache

    private static func currentSettings(userId: String) async -> UserSettings? {
        if let user = authManager.user, user.id == userId {
            return user.settings
        }
        return try? await ProfileRepository.findById(userId)?.settings
    }

    private static func resolveStepConfiguration(
        userId: String
    ) async -> CachedStepNotificationConfiguration? {
        if let settings = await currentSettings(userId: userId),
           let goal = settings.dailyStepGoal,
           goal > 0 {
            let configuration = CachedStepNotificationConfiguration(
                userId: userId,
                goal: goal,
                enabled: settings.notifications.stepGoalAchievements
            )
            cacheStepConfiguration(configuration)
            return configuration
        }

        guard let cached = cachedStepConfiguration(),
              cached.userId == userId else { return nil }
        return cached
    }

    private static func cacheStepConfiguration(
        _ configuration: CachedStepNotificationConfiguration
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: stepCacheKey)
    }

    private static func cachedStepConfiguration() -> CachedStepNotificationConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: stepCacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedStepNotificationConfiguration.self, from: data)
    }

    private static func clearStepConfiguration() {
        UserDefaults.standard.removeObject(forKey: stepCacheKey)
    }

    private static func clearLegacyStepState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "shift.cached.dailyStepGoal")
        defaults.removeObject(forKey: "shift.cached.stepGoalReminders")
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("shift.notification.sent.") {
            defaults.removeObject(forKey: key)
        }
    }
}
