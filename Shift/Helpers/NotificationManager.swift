import UserNotifications

/// Lightweight wrapper around UNUserNotificationCenter for local notifications.
enum NotificationManager {

    private static let center = UNUserNotificationCenter.current()

    // MARK: - Categories

    static let workoutIdleCategory = "SHIFT_WORKOUT_IDLE"
    static let finishWorkoutAction = "FINISH_WORKOUT"

    /// Registers notification categories with actions. Call once at app launch.
    static func registerCategories() {
        let finishAction = UNNotificationAction(
            identifier: finishWorkoutAction,
            title: "Finish Workout",
            options: [.foreground]
        )

        let idleCategory = UNNotificationCategory(
            identifier: workoutIdleCategory,
            actions: [finishAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([idleCategory])
    }

    // MARK: - Permission

    /// Request notification permission. Safe to call multiple times — the system
    /// only shows the prompt once.
    static func requestPermissionIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Rest Timer

    private static let restTimerIdentifier = "shift.rest-timer-complete"

    /// Schedule a notification to fire when the rest timer finishes.
    static func scheduleRestTimerNotification(seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Time to get back to work 💪"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(max(seconds, 1)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: restTimerIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Cancel any pending rest timer notification (e.g. user skipped the timer).
    static func cancelRestTimerNotification() {
        center.removePendingNotificationRequests(
            withIdentifiers: [restTimerIdentifier]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [restTimerIdentifier]
        )
    }

    // MARK: - Goal Notifications

    /// Schedule a notification at a specific date/time using calendar trigger.
    static func scheduleGoalNotification(
        identifier: String,
        title: String,
        body: String,
        at dateComponents: DateComponents
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    // MARK: - Idle Workout

    private static let idleWorkoutIdentifier = "shift.workout-idle"

    /// Schedules a notification to fire after `seconds` of inactivity during a workout.
    /// Each call cancels the previous one (resets the timer).
    static func scheduleIdleWorkoutNotification(sessionId: String, seconds: Int = 1800) {
        cancelIdleWorkoutNotification()

        let content = UNMutableNotificationContent()
        content.title = "Still working out?"
        content.body = "You haven't logged a set in a while. Finish up or keep going?"
        content.sound = .default
        content.categoryIdentifier = workoutIdleCategory
        content.userInfo = ["sessionId": sessionId]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(max(seconds, 1)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: idleWorkoutIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Cancel the idle workout notification (e.g. when a new set is logged or workout finishes).
    static func cancelIdleWorkoutNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [idleWorkoutIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [idleWorkoutIdentifier])
    }

    /// Cancel all pending notifications whose identifiers start with the given prefix.
    static func cancelNotifications(withPrefix prefix: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
