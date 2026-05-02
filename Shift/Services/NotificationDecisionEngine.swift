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

    // MARK: - Step Progress Actions

    /// Determines what notifications to fire/cancel based on current step progress.
    /// Returns milestone celebrations and progressive cancellation of upcoming reminders.
    static func stepProgressActions(
        steps: Int,
        goal: Int,
        todayKey: String
    ) -> [Action] {
        guard goal > 0 else { return [] }
        var actions: [Action] = []
        let pct = Double(steps) / Double(goal) * 100
        let formatted = formatNumber(goal)

        if pct >= 100 {
            for tier in stepReminderTiers {
                actions.append(.cancel(prefix: "shift.steps-remind-\(tier)-0"))
            }
            actions.append(.fireImmediately(
                id: "shift.steps-completed-\(todayKey)",
                title: "Steps crushed!",
                body: "You hit your \(formatted)-step goal. Keep it up!"
            ))
        } else if pct >= 75 {
            actions.append(.cancel(prefix: "shift.steps-remind-evening-0"))
            actions.append(.fireImmediately(
                id: "shift.steps-milestone-75-\(todayKey)",
                title: "Almost there!",
                body: "75% of your \(formatted)-step goal is done. The finish line is close."
            ))
        } else if pct >= 50 {
            actions.append(.cancel(prefix: "shift.steps-remind-afternoon-0"))
            actions.append(.fireImmediately(
                id: "shift.steps-milestone-50-\(todayKey)",
                title: "Halfway there!",
                body: "You've hit 50% of your \(formatted)-step goal. Keep moving!"
            ))
        }

        return actions
    }

    /// Backward-compatible wrapper used by existing tests.
    static func goalCompletionActions(
        activity: ActivityData,
        stepGoal: Int?,
        todayKey: String
    ) -> [Action] {
        guard let goal = stepGoal else { return [] }
        return stepProgressActions(steps: activity.steps, goal: goal, todayKey: todayKey)
    }

    // MARK: - Step Reminder Tiers

    static let stepReminderTiers = ["morning", "afternoon", "evening"]

    /// Base hours for each step reminder tier. Actual fire time adds date-seeded jitter.
    static func stepTierBaseHour(_ tier: String) -> Int {
        switch tier {
        case "morning": return 10
        case "afternoon": return 14
        case "evening": return 20
        default: return 14
        }
    }

    /// Deterministic jitter (±20 min) so notifications don't fire at the exact same minute daily.
    /// Seeded by the day + tier so a reschedule on the same day produces the same time.
    static func stepTierMinuteJitter(tier: String, dayOffset: Int, baseDaySeed: Int) -> Int {
        var hash = baseDaySeed &+ dayOffset
        hash = hash &* 2654435761 // Knuth multiplicative hash
        hash ^= tier.hashValue
        return abs(hash) % 41 - 20 // -20 ... +20
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
