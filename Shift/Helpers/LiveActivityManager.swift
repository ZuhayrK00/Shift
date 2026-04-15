import ActivityKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.shift.app", category: "LiveActivityManager")

/// Manages the rest timer Live Activity. Start when a rest timer begins,
/// end when it completes or the user skips.
enum LiveActivityManager {

    private static var currentActivityId: String?

    static func start(durationSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first (fire-and-forget but await internally)
        Task { await endCurrentActivity() }

        let endTime = Date.now.addingTimeInterval(Double(durationSeconds))
        let state = RestTimerAttributes.TimerState(
            endTime: endTime,
            totalSeconds: durationSeconds
        )
        let content = ActivityContent(
            state: state,
            staleDate: endTime
        )

        do {
            let activity = try Activity.request(
                attributes: RestTimerAttributes(),
                content: content,
                pushType: nil
            )
            currentActivityId = activity.id
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    static func stop() {
        Task { await endCurrentActivity() }
    }

    /// Ends all rest timer Live Activities — catches zombies left from background expiry.
    static func endAllActivities() {
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivityId = nil
        }
    }

    /// Ends the current Live Activity and waits for it to complete before clearing the ID.
    /// This prevents zombie activities from being left on the Dynamic Island.
    private static func endCurrentActivity() async {
        guard let id = currentActivityId else { return }
        currentActivityId = nil
        let match = Activity<RestTimerAttributes>.activities.first { $0.id == id }
        await match?.end(nil, dismissalPolicy: .immediate)
    }
}
