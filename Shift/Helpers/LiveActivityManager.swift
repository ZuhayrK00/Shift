import ActivityKit
import Foundation

/// Manages the rest timer Live Activity. Start when a rest timer begins,
/// end when it completes or the user skips.
enum LiveActivityManager {

    private static var currentActivityId: String?

    static func start(durationSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first
        stopCurrent()

        let endTime = Date.now.addingTimeInterval(Double(durationSeconds))
        let state = RestTimerAttributes.TimerState(
            endTime: endTime,
            totalSeconds: durationSeconds
        )
        let content = ActivityContent(
            state: state,
            staleDate: endTime.addingTimeInterval(10)
        )

        do {
            let activity = try Activity.request(
                attributes: RestTimerAttributes(),
                content: content,
                pushType: nil
            )
            currentActivityId = activity.id
        } catch {
            // Live Activity failed — the in-app timer still works fine.
        }
    }

    static func stop() {
        stopCurrent()
    }

    private static func stopCurrent() {
        guard let id = currentActivityId else { return }
        let match = Activity<RestTimerAttributes>.activities.first { $0.id == id }
        Task {
            await match?.end(nil, dismissalPolicy: .immediate)
        }
        currentActivityId = nil
    }
}
