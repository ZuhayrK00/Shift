import XCTest
@testable import Shift

final class NotificationDecisionEngineTests: XCTestCase {

    // MARK: - Goal Completion Actions

    func testStepGoalMet_cancelReminderAndFireCongrats() {
        let activity = ActivityData(steps: 10000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps-completed") }
            return false
        }))
    }

    func testStepGoalExceeded_cancelReminderAndFireCongrats() {
        let activity = ActivityData(steps: 12000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps-completed") }
            return false
        }))
    }

    func testStepGoalNotMet_noActions() {
        let activity = ActivityData(steps: 5000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .cancel(let prefix) = $0 { return prefix.contains("steps") }
            return false
        }))
        XCTAssertFalse(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps") }
            return false
        }))
    }

    func testNoStepGoal_noStepActions() {
        let activity = ActivityData(steps: 10000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.filter {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps") }
            if case .cancel(let prefix) = $0 { return prefix.contains("steps") }
            return false
        }.isEmpty)
    }

    func testZeroStepGoal_noStepActions() {
        let activity = ActivityData(steps: 500)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 0, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.filter {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps") }
            if case .cancel(let prefix) = $0 { return prefix.contains("steps") }
            return false
        }.isEmpty)
    }

    // MARK: - Move Ring

    func testMoveRingClosed_cancelReminderAndFireCongrats() {
        let activity = ActivityData(moveCalories: 500, moveGoal: 400)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.rings-move-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("rings-move-completed") }
            return false
        }))
    }

    func testMoveRingOpen_noMoveActions() {
        let activity = ActivityData(moveCalories: 200, moveGoal: 400)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .cancel(let prefix) = $0 { return prefix.contains("move") }
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("move") }
            return false
        }))
    }

    func testMoveRingNoGoal_noMoveActions() {
        let activity = ActivityData(moveCalories: 500, moveGoal: 0)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("move") }
            return false
        }))
    }

    // MARK: - Exercise Ring

    func testExerciseRingClosed_cancelReminderAndFireCongrats() {
        let activity = ActivityData(exerciseMinutes: 35, exerciseGoal: 30)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.rings-exercise-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("rings-exercise-completed") }
            return false
        }))
    }

    func testExerciseRingOpen_noExerciseActions() {
        let activity = ActivityData(exerciseMinutes: 10, exerciseGoal: 30)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .cancel(let prefix) = $0 { return prefix.contains("exercise") }
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("exercise") }
            return false
        }))
    }

    // MARK: - Stand Ring

    func testStandRingClosed_cancelReminderAndFireCongrats() {
        let activity = ActivityData(standHours: 12, standGoal: 12)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.rings-stand-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("rings-stand-completed") }
            return false
        }))
    }

    func testStandRingOpen_noStandActions() {
        let activity = ActivityData(standHours: 8, standGoal: 12)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .cancel(let prefix) = $0 { return prefix.contains("stand") }
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("stand") }
            return false
        }))
    }

    // MARK: - All Goals Met

    func testAllGoalsMet_allActionsPresent() {
        let activity = ActivityData(
            moveCalories: 500, moveGoal: 400,
            exerciseMinutes: 45, exerciseGoal: 30,
            standHours: 14, standGoal: 12,
            steps: 12000
        )
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        // Should have 4 cancels + 4 congrats = 8 actions
        let cancels = actions.filter { if case .cancel = $0 { return true }; return false }
        let fires = actions.filter { if case .fireImmediately = $0 { return true }; return false }
        XCTAssertEqual(cancels.count, 4)
        XCTAssertEqual(fires.count, 4)
    }

    func testNoGoalsMet_noActions() {
        let activity = ActivityData(
            moveCalories: 100, moveGoal: 400,
            exerciseMinutes: 5, exerciseGoal: 30,
            standHours: 3, standGoal: 12,
            steps: 2000
        )
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Congrats ID includes date (once per day)

    func testCongratsIdContainsTodayKey() {
        let activity = ActivityData(moveCalories: 500, moveGoal: 400)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        let fireAction = actions.first(where: { if case .fireImmediately = $0 { return true }; return false })
        if case .fireImmediately(let id, _, _) = fireAction {
            XCTAssertTrue(id.contains("2026-04-14"), "Congrats ID should contain today's date key")
        } else {
            XCTFail("Expected a fireImmediately action")
        }
    }

    func testDifferentDays_differentCongratsIds() {
        let activity = ActivityData(steps: 10000)

        let actions1 = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 7000, todayKey: "2026-04-14"
        )
        let actions2 = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 7000, todayKey: "2026-04-15"
        )

        let id1 = actions1.compactMap { if case .fireImmediately(let id, _, _) = $0, id.contains("steps") { return id }; return nil }.first
        let id2 = actions2.compactMap { if case .fireImmediately(let id, _, _) = $0, id.contains("steps") { return id }; return nil }.first

        XCTAssertNotNil(id1)
        XCTAssertNotNil(id2)
        XCTAssertNotEqual(id1, id2)
    }

    // MARK: - Frequency Stage

    func testFrequencyStage_behindPace() {
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 1, target: 4, dayOfWeek: 2, dayOffset: 0
        )
        XCTAssertEqual(stage, .behindPace)
    }

    func testFrequencyStage_runningOutOfTime() {
        // 3 remaining, only 2 days left
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 1, target: 4, dayOfWeek: 5, dayOffset: 0
        )
        XCTAssertEqual(stage, .runningOutOfTime)
    }

    func testFrequencyStage_hitGoal() {
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 4, target: 4, dayOfWeek: 3, dayOffset: 0
        )
        XCTAssertEqual(stage, .hitGoal)
    }

    func testFrequencyStage_exceededGoal() {
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 6, target: 4, dayOfWeek: 5, dayOffset: 0
        )
        XCTAssertEqual(stage, .exceededGoal)
    }

    func testFrequencyStage_missedGoal_lastDay() {
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 2, target: 4, dayOfWeek: 7, dayOffset: 0
        )
        XCTAssertEqual(stage, .missedGoal)
    }

    func testFrequencyStage_dayOffsetAdvancesDay() {
        // Day 3, offset 3 = effective day 6, 1 day left, 2 remaining = running out
        let stage = NotificationDecisionEngine.computeFrequencyStage(
            completed: 2, target: 4, dayOfWeek: 3, dayOffset: 3
        )
        XCTAssertEqual(stage, .runningOutOfTime)
    }

    // MARK: - Exercise Goal Schedule Days

    func testScheduleDays_lastDay() {
        let days = NotificationDecisionEngine.exerciseGoalScheduleDays(daysRemaining: 0)
        XCTAssertEqual(days, [0])
    }

    func testScheduleDays_threeDaysLeft_daily() {
        let days = NotificationDecisionEngine.exerciseGoalScheduleDays(daysRemaining: 3)
        XCTAssertEqual(days, [0, 1, 2, 3])
    }

    func testScheduleDays_sevenDaysLeft_everyOther() {
        let days = NotificationDecisionEngine.exerciseGoalScheduleDays(daysRemaining: 7)
        XCTAssertEqual(days, [0, 2, 4, 6])
    }

    func testScheduleDays_fourteenDaysLeft_weekly() {
        let days = NotificationDecisionEngine.exerciseGoalScheduleDays(daysRemaining: 14)
        XCTAssertEqual(days, [0, 7, 14])
    }

    func testScheduleDays_overdue_empty() {
        let days = NotificationDecisionEngine.exerciseGoalScheduleDays(daysRemaining: -1)
        XCTAssertTrue(days.isEmpty)
    }

    // MARK: - Notification Hour

    func testNotificationHour_defaultsTo17() {
        let hour = NotificationDecisionEngine.computeNotificationHour(averageWorkoutHour: nil)
        XCTAssertEqual(hour, 17) // (18 - 1)
    }

    func testNotificationHour_oneHourBeforeAverage() {
        let hour = NotificationDecisionEngine.computeNotificationHour(averageWorkoutHour: 19)
        XCTAssertEqual(hour, 18)
    }

    func testNotificationHour_clampedToMin7() {
        let hour = NotificationDecisionEngine.computeNotificationHour(averageWorkoutHour: 6)
        XCTAssertEqual(hour, 7) // (6 - 1 = 5) clamped to 7
    }

    func testNotificationHour_clampedToMax21() {
        let hour = NotificationDecisionEngine.computeNotificationHour(averageWorkoutHour: 23)
        XCTAssertEqual(hour, 21) // (23 - 1 = 22) clamped to 21
    }

    // MARK: - Rings Needing Reminders

    func testRingsNeedingReminders_allGoalsSet() {
        let activity = ActivityData(moveGoal: 400, exerciseGoal: 30, standGoal: 12)
        let rings = NotificationDecisionEngine.ringsNeedingReminders(activity: activity)
        XCTAssertEqual(rings, ["Move", "Exercise", "Stand"])
    }

    func testRingsNeedingReminders_noGoals() {
        let activity = ActivityData(moveGoal: 0, exerciseGoal: 0, standGoal: 0)
        let rings = NotificationDecisionEngine.ringsNeedingReminders(activity: activity)
        XCTAssertTrue(rings.isEmpty)
    }

    func testRingsNeedingReminders_partialGoals() {
        let activity = ActivityData(moveGoal: 400, exerciseGoal: 0, standGoal: 12)
        let rings = NotificationDecisionEngine.ringsNeedingReminders(activity: activity)
        XCTAssertEqual(rings, ["Move", "Stand"])
    }

    // MARK: - Edge Cases

    func testExactlyAtGoal_countsAsCompleted() {
        let activity = ActivityData(
            moveCalories: 400, moveGoal: 400,
            exerciseMinutes: 30, exerciseGoal: 30,
            standHours: 12, standGoal: 12,
            steps: 10000
        )
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        let fires = actions.filter { if case .fireImmediately = $0 { return true }; return false }
        XCTAssertEqual(fires.count, 4, "Exactly meeting a goal should trigger congrats")
    }

    func testOneStepShort_noStepCongrats() {
        let activity = ActivityData(steps: 9999)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertFalse(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps") }
            return false
        }))
    }

    func testZeroActivity_noActions() {
        let activity = ActivityData()
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )
        XCTAssertTrue(actions.isEmpty)
    }
}
