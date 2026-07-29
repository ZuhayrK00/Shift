import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.shift.app", category: "NotificationManager")

enum NotificationPermissionState: Equatable {
    case notDetermined
    case enabled
    case denied
}

private final class NotificationGenerationState: @unchecked Sendable {
    private let lock = NSLock()
    private var restGeneration = 0
    private var idleGenerations: [String: Int] = [:]

    func nextRestGeneration() -> Int {
        lock.withLock {
            restGeneration += 1
            return restGeneration
        }
    }

    func isCurrentRestGeneration(_ generation: Int) -> Bool {
        lock.withLock { generation == restGeneration }
    }

    func nextIdleGeneration(sessionId: String) -> Int {
        lock.withLock {
            let generation = (idleGenerations[sessionId] ?? 0) + 1
            idleGenerations[sessionId] = generation
            return generation
        }
    }

    func isCurrentIdleGeneration(_ generation: Int, sessionId: String) -> Bool {
        lock.withLock { idleGenerations[sessionId] == generation }
    }

    func invalidateAllIdleGenerations() {
        lock.withLock {
            for sessionId in Array(idleGenerations.keys) {
                idleGenerations[sessionId, default: 0] += 1
            }
        }
    }
}

/// Centralised wrapper around `UNUserNotificationCenter`.
///
/// Achievement notifications are delivered immediately from real app events.
/// Only rest timers and workout-idle timeouts use future triggers because iOS
/// suspends apps in the background and must own those countdowns.
enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let generations = NotificationGenerationState()

    static let workoutIdleCategory = "SHIFT_WORKOUT_IDLE"
    static let restTimerCategory = "SHIFT_REST_TIMER"
    static let openWorkoutAction = "OPEN_WORKOUT"

    private static let restTimerIdentifier = "shift.rest-timer-complete"
    private static let idlePrefix = "shift.workout-idle."

    // MARK: - Categories

    static func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: openWorkoutAction,
            title: "Open Workout",
            options: [.foreground]
        )

        let idleCategory = UNNotificationCategory(
            identifier: workoutIdleCategory,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        let restCategory = UNNotificationCategory(
            identifier: restTimerCategory,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([idleCategory, restCategory])
    }

    // MARK: - Permission

    static func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .enabled
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// Requests permission only when the user has not already made a choice.
    /// Call from onboarding or notification settings, where the request has context.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        switch await permissionState() {
        case .enabled:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    private static func isAuthorized() async -> Bool {
        await permissionState() == .enabled
    }

    // MARK: - Immediate event delivery

    /// Delivers an event notification now. A nil trigger is the system-supported
    /// immediate-delivery path and does not create a future scheduled reminder.
    @discardableResult
    static func deliverImmediately(
        identifier: String,
        title: String,
        body: String,
        kind: String,
        userInfo: [String: Any] = [:]
    ) async -> Bool {
        guard await isAuthorized() else {
            logger.info("Skipping \(identifier, privacy: .public) — notifications are not authorized")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        var payload = userInfo
        payload["shiftNotificationKind"] = kind
        content.userInfo = payload

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Failed to deliver \(identifier, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Rest timer

    static func scheduleRestTimerNotification(seconds: Int, sessionId: String?) {
        let generation = generations.nextRestGeneration()
        center.removePendingNotificationRequests(withIdentifiers: [restTimerIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [restTimerIdentifier])

        Task {
            guard await isAuthorized(),
                  generations.isCurrentRestGeneration(generation) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Ready for your next set?"
            content.sound = .default
            content.categoryIdentifier = restTimerCategory
            if let sessionId {
                content.userInfo = ["sessionId": sessionId]
            }

            let request = UNNotificationRequest(
                identifier: restTimerIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(max(seconds, 1)),
                    repeats: false
                )
            )

            do {
                try await center.add(request)
                // Cancellation may have happened while authorization or add was in flight.
                if !generations.isCurrentRestGeneration(generation) {
                    center.removePendingNotificationRequests(withIdentifiers: [restTimerIdentifier])
                    center.removeDeliveredNotifications(withIdentifiers: [restTimerIdentifier])
                }
            } catch {
                logger.error("Failed to schedule rest timer: \(error.localizedDescription)")
            }
        }
    }

    static func cancelRestTimerNotification() {
        _ = generations.nextRestGeneration()
        center.removePendingNotificationRequests(withIdentifiers: [restTimerIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [restTimerIdentifier])
    }

    // MARK: - Idle workout

    static func scheduleIdleWorkoutNotification(sessionId: String, seconds: Int = 1800) {
        let identifier = idleIdentifier(sessionId: sessionId)
        let generation = generations.nextIdleGeneration(sessionId: sessionId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        Task {
            guard await isAuthorized(),
                  generations.isCurrentIdleGeneration(generation, sessionId: sessionId) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Workout still in progress"
            content.body = "No sets have been logged for 30 minutes. Open the workout to continue or finish it."
            content.sound = .default
            content.categoryIdentifier = workoutIdleCategory
            content.userInfo = ["sessionId": sessionId]

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(max(seconds, 1)),
                    repeats: false
                )
            )

            do {
                try await center.add(request)
                if !generations.isCurrentIdleGeneration(generation, sessionId: sessionId) {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                }
            } catch {
                logger.error("Failed to schedule idle workout alert: \(error.localizedDescription)")
            }
        }
    }

    static func cancelIdleWorkoutNotification(sessionId: String) {
        _ = generations.nextIdleGeneration(sessionId: sessionId)
        let identifier = idleIdentifier(sessionId: sessionId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func cancelAllIdleWorkoutNotifications() async {
        generations.invalidateAllIdleGenerations()
        await removeNotifications(withPrefixes: [idlePrefix])
    }

    private static func idleIdentifier(sessionId: String) -> String {
        "\(idlePrefix)\(sessionId)"
    }

    // MARK: - Cleanup

    static func removeNotifications(withPrefixes prefixes: [String]) async {
        async let pending = pendingRequests()
        async let delivered = deliveredNotifications()

        let pendingIds = await pending
            .map(\.identifier)
            .filter { id in prefixes.contains { id.hasPrefix($0) } }
        let deliveredIds = await delivered
            .map(\.request.identifier)
            .filter { id in prefixes.contains { id.hasPrefix($0) } }

        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }
    }

    static func removeLegacyGoalNotifications() async {
        await removeNotifications(withPrefixes: [
            "shift.exercise-goal-",
            "shift.frequency-",
            "shift.steps-remind-",
            "shift.steps-kickoff",
            "shift.steps-milestone-",
            "shift.progress-"
        ])
    }

    static func removeAllShiftNotifications() async {
        _ = generations.nextRestGeneration()
        generations.invalidateAllIdleGenerations()
        await removeNotifications(withPrefixes: ["shift."])
    }

    private static func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications {
                continuation.resume(returning: $0)
            }
        }
    }
}
