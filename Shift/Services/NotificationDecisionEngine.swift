import Foundation

/// Pure notification policy. This layer deliberately contains no timer or
/// calendar scheduling: it only describes alerts caused by completed events.
enum NotificationDecisionEngine {
    enum StepDay {
        case today
        case yesterday
    }

    struct Message: Equatable {
        let title: String
        let body: String
    }

    enum FrequencyProgressEvent: Equatable {
        case oneRemaining(completed: Int, target: Int)
        case completed(target: Int)
    }

    static func shouldNotifyStepGoal(steps: Int, goal: Int?) -> Bool {
        guard let goal, goal > 0 else { return false }
        return steps >= goal
    }

    static func shouldNotifyFrequencyGoal(completed: Int, target: Int?) -> Bool {
        guard let target, target > 0 else { return false }
        return completed >= target
    }

    static func frequencyProgressEvent(
        completed: Int,
        target: Int?
    ) -> FrequencyProgressEvent? {
        guard let target, target > 0, completed >= 0 else { return nil }
        if completed >= target {
            return .completed(target: target)
        }
        if target > 1, completed == target - 1 {
            return .oneRemaining(completed: completed, target: target)
        }
        return nil
    }

    static func stepGoalMessage(goal: Int, day: StepDay = .today) -> Message {
        Message(
            title: "Daily step goal complete",
            body: "You reached \(formatNumber(goal)) steps \(day == .today ? "today" : "yesterday")."
        )
    }

    static func frequencyGoalMessage(target: Int) -> Message {
        let workout = target == 1 ? "workout" : "workouts"
        return Message(
            title: "Weekly workout goal complete",
            body: "You completed \(target) \(workout) this week."
        )
    }

    static func frequencyProgressMessage(
        for event: FrequencyProgressEvent
    ) -> Message {
        switch event {
        case let .oneRemaining(completed, target):
            return Message(
                title: "One workout to go",
                body: "You’ve completed \(completed) of \(target) workouts this week."
            )
        case let .completed(target):
            return frequencyGoalMessage(target: target)
        }
    }

    static func missedTrainingDayMessage(dayName: String) -> Message {
        Message(
            title: "Planned workout missed",
            body: "\(dayName) was one of your training days, but no workout was logged. You can still adjust this week or update your schedule."
        )
    }

    static func exerciseGoalMessage(
        exerciseName: String,
        targetWeight: Double,
        unit: String
    ) -> Message {
        Message(
            title: "Exercise goal achieved",
            body: "\(exerciseName): you reached \(formatWeight(targetWeight)) \(unit)."
        )
    }

    private static func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private static func formatWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}
