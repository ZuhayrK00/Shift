import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    typealias ContentState = TimerState

    struct TimerState: Codable, Hashable {
        /// When the rest period expires.
        var endTime: Date
        /// Original duration — used to draw the progress arc.
        var totalSeconds: Int
    }
}
