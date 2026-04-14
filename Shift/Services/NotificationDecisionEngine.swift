import Foundation

// MARK: - NotificationDecisionEngine
//
// Pure logic layer for notification decisions. No side effects — returns
// actions that the caller (GoalNotificationService) executes.
// This separation makes the logic unit-testable without mocking UNUserNotificationCenter.

enum NotificationDecisionEngine {

    // MARK: - Actions

    enum Action: Equatable {
        case schedule(id: String, title: String, body: String, hour: Int, minute: Int, dayOffset: Int)
        case cancel(prefix: String)
        case fireImmediately(id: String, title: String, body: String)
    }

    // MARK: - Goal Completion Check

    /// Determines what notifications to fire/cancel based on current activity vs goals.
    static func goalCompletionActions(
        activity: ActivityData,
        stepGoal: Int?,
        todayKey: String
    ) -> [Action] {
        var actions: [Action] = []

        // Step goal
        if let goal = stepGoal, goal > 0, activity.steps >= goal {
            actions.append(.cancel(prefix: "shift.steps-remind-0"))
            actions.append(.fireImmediately(
                id: "shift.steps-completed-\(todayKey)",
                title: "Steps crushed!",
                body: "You hit your \(formatNumber(goal))-step goal. Keep it up!"
            ))
        }

        // Move ring
        if activity.moveGoal > 0, activity.moveCalories >= activity.moveGoal {
            actions.append(.cancel(prefix: "shift.rings-move-0"))
            actions.append(.fireImmediately(
                id: "shift.rings-move-completed-\(todayKey)",
                title: "Move ring closed!",
                body: "You've hit your calorie goal for today. Nice work!"
            ))
        }

        // Exercise ring
        if activity.exerciseGoal > 0, activity.exerciseMinutes >= activity.exerciseGoal {
            actions.append(.cancel(prefix: "shift.rings-exercise-0"))
            actions.append(.fireImmediately(
                id: "shift.rings-exercise-completed-\(todayKey)",
                title: "Exercise ring closed!",
                body: "You've hit your exercise minutes. Strong effort!"
            ))
        }

        // Stand ring
        if activity.standGoal > 0, activity.standHours >= activity.standGoal {
            actions.append(.cancel(prefix: "shift.rings-stand-0"))
            actions.append(.fireImmediately(
                id: "shift.rings-stand-completed-\(todayKey)",
                title: "Stand ring closed!",
                body: "You've stayed active throughout the day. Well done!"
            ))
        }

        return actions
    }

    // MARK: - Step Goal Reminder Decisions

    /// Determines whether a step reminder or congrats should be scheduled for a given day.
    enum StepNotificationType: Equatable {
        case eveningReminder
        case morningCongrats
    }

    static func stepNotificationTypes(
        stepGoal: Int,
        notificationsEnabled: Bool
    ) -> [StepNotificationType] {
        guard notificationsEnabled, stepGoal > 0 else { return [] }
        return [.eveningReminder, .morningCongrats]
    }

    // MARK: - Ring Reminder Decisions

    /// Returns which rings should get reminders (all that have goals > 0).
    static func ringsNeedingReminders(activity: ActivityData) -> [String] {
        var rings: [String] = []
        if activity.moveGoal > 0 { rings.append("Move") }
        if activity.exerciseGoal > 0 { rings.append("Exercise") }
        if activity.standGoal > 0 { rings.append("Stand") }
        return rings
    }

    // MARK: - Frequency Stage

    /// Pure computation of frequency notification stage.
    static func computeFrequencyStage(
        completed: Int,
        target: Int,
        dayOfWeek: Int,
        dayOffset: Int
    ) -> FrequencyStage {
        if completed >= target {
            return completed > target ? .exceededGoal : .hitGoal
        }

        let effectiveDay = dayOfWeek + dayOffset
        let daysLeft = max(0, 7 - effectiveDay)
        let remaining = target - completed

        if daysLeft == 0 {
            return completed >= target ? .hitGoal : .missedGoal
        }

        if remaining >= daysLeft {
            return .runningOutOfTime
        }

        return .behindPace
    }

    enum FrequencyStage: Equatable {
        case behindPace
        case runningOutOfTime
        case missedGoal
        case hitGoal
        case exceededGoal
    }

    // MARK: - Exercise Goal Schedule Days

    /// Determines which days to schedule exercise goal reminders based on days remaining.
    static func exerciseGoalScheduleDays(daysRemaining: Int) -> [Int] {
        guard daysRemaining >= 0 else { return [] }

        if daysRemaining <= 3 {
            return Array(0...daysRemaining)
        } else if daysRemaining <= 7 {
            return stride(from: 0, through: daysRemaining, by: 2).map { $0 }
        } else {
            return stride(from: 0, through: daysRemaining, by: 7).map { $0 }
        }
    }

    // MARK: - Notification Hour

    /// Computes notification hour from average workout hour.
    static func computeNotificationHour(averageWorkoutHour: Int?) -> Int {
        let hour = (averageWorkoutHour ?? 18) - 1
        return min(max(hour, 7), 21)
    }

    // MARK: - Helpers

    private static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
