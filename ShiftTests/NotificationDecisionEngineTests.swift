import XCTest
@testable import Shift

final class NotificationDecisionEngineTests: XCTestCase {

    // MARK: - Goal Completion Actions

    func testStepGoalMet_cancelsAllTiersAndFiresCongrats() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 10000, goal: 10000, todayKey: "2026-04-14"
        )

        for tier in ["morning", "afternoon", "evening"] {
            XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-\(tier)-0")),
                          "Should cancel \(tier) reminder")
        }
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps-completed") }
            return false
        }))
    }

    func testStepGoalExceeded_cancelsAllTiersAndFiresCongrats() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 12000, goal: 10000, todayKey: "2026-04-14"
        )

        for tier in ["morning", "afternoon", "evening"] {
            XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-\(tier)-0")))
        }
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("steps-completed") }
            return false
        }))
    }

    func testStepGoalNotMet_below50pct_noActions() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 4999, goal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.isEmpty)
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

    // MARK: - No Ring Notifications

    func testNoRingNotifications_evenWithClosedRings() {
        let activity = ActivityData(
            moveCalories: 500, moveGoal: 400,
            exerciseMinutes: 45, exerciseGoal: 30,
            standHours: 14, standGoal: 12
        )
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: nil, todayKey: "2026-04-14"
        )

        // No ring notifications — only step goal notifications are supported
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Step Goal Only

    func testStepGoalComplete_threeCancels_oneCongrats() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 12000, goal: 10000, todayKey: "2026-04-14"
        )

        let cancels = actions.filter { if case .cancel = $0 { return true }; return false }
        let fires = actions.filter { if case .fireImmediately = $0 { return true }; return false }
        XCTAssertEqual(cancels.count, 3, "Should cancel morning, afternoon, and evening")
        XCTAssertEqual(fires.count, 1)
    }

    func testNoGoalsMet_noActions() {
        let activity = ActivityData(steps: 2000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Congrats ID includes date (once per day)

    func testCongratsIdContainsTodayKey() {
        let activity = ActivityData(steps: 10000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 8000, todayKey: "2026-04-14"
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

    // MARK: - Edge Cases

    func testExactlyAtStepGoal_countsAsCompleted() {
        let activity = ActivityData(steps: 10000)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        let fires = actions.filter { if case .fireImmediately = $0 { return true }; return false }
        XCTAssertEqual(fires.count, 1, "Exactly meeting step goal should trigger congrats")
    }

    func testOneStepShort_fires75MilestoneNotCompletion() {
        let activity = ActivityData(steps: 9999)
        let actions = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )

        // 99.99% → should fire 75% milestone, not completion
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("milestone-75") }
            return false
        }))
        XCTAssertFalse(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("completed") }
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

    // MARK: - Step Milestones

    func testHalfwayMilestone_firesAndCancelsAfternoon() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 5000, goal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-afternoon-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("milestone-50") }
            return false
        }))
        // Should NOT cancel morning or evening
        XCTAssertFalse(actions.contains(.cancel(prefix: "shift.steps-remind-morning-0")))
        XCTAssertFalse(actions.contains(.cancel(prefix: "shift.steps-remind-evening-0")))
    }

    func testThreeQuarterMilestone_firesAndCancelsEvening() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 7500, goal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(.cancel(prefix: "shift.steps-remind-evening-0")))
        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("milestone-75") }
            return false
        }))
        // Should NOT cancel morning or afternoon
        XCTAssertFalse(actions.contains(.cancel(prefix: "shift.steps-remind-morning-0")))
        XCTAssertFalse(actions.contains(.cancel(prefix: "shift.steps-remind-afternoon-0")))
    }

    func testAt49Percent_noMilestoneActions() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 4999, goal: 10000, todayKey: "2026-04-14"
        )
        XCTAssertTrue(actions.isEmpty)
    }

    func testAt74Percent_fires50MilestoneOnly() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 7499, goal: 10000, todayKey: "2026-04-14"
        )

        XCTAssertTrue(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("milestone-50") }
            return false
        }))
        XCTAssertFalse(actions.contains(where: {
            if case .fireImmediately(let id, _, _) = $0 { return id.contains("milestone-75") }
            return false
        }))
    }

    func testMilestoneIdsContainDate() {
        let actions = NotificationDecisionEngine.stepProgressActions(
            steps: 5000, goal: 10000, todayKey: "2026-04-14"
        )

        let fireId = actions.compactMap {
            if case .fireImmediately(let id, _, _) = $0 { return id }; return nil
        }.first
        XCTAssertTrue(fireId?.contains("2026-04-14") ?? false)
    }

    // MARK: - Step Tier Configuration

    func testStepReminderTiers_hasThreeTiers() {
        XCTAssertEqual(NotificationDecisionEngine.stepReminderTiers.count, 3)
        XCTAssertEqual(NotificationDecisionEngine.stepReminderTiers, ["morning", "afternoon", "evening"])
    }

    func testStepTierBaseHours() {
        XCTAssertEqual(NotificationDecisionEngine.stepTierBaseHour("morning"), 10)
        XCTAssertEqual(NotificationDecisionEngine.stepTierBaseHour("afternoon"), 14)
        XCTAssertEqual(NotificationDecisionEngine.stepTierBaseHour("evening"), 20)
    }

    func testStepTierJitter_withinBounds() {
        for dayOffset in 0..<14 {
            for tier in ["morning", "afternoon", "evening"] {
                let jitter = NotificationDecisionEngine.stepTierMinuteJitter(
                    tier: tier, dayOffset: dayOffset, baseDaySeed: 20000
                )
                XCTAssertGreaterThanOrEqual(jitter, -20)
                XCTAssertLessThanOrEqual(jitter, 20)
            }
        }
    }

    func testStepTierJitter_deterministicForSameInputs() {
        let j1 = NotificationDecisionEngine.stepTierMinuteJitter(
            tier: "morning", dayOffset: 0, baseDaySeed: 20000
        )
        let j2 = NotificationDecisionEngine.stepTierMinuteJitter(
            tier: "morning", dayOffset: 0, baseDaySeed: 20000
        )
        XCTAssertEqual(j1, j2)
    }

    func testStepTierJitter_variesAcrossDays() {
        let j1 = NotificationDecisionEngine.stepTierMinuteJitter(
            tier: "morning", dayOffset: 0, baseDaySeed: 20000
        )
        let j2 = NotificationDecisionEngine.stepTierMinuteJitter(
            tier: "morning", dayOffset: 1, baseDaySeed: 20000
        )
        // Technically could collide, but with the hash it's extremely unlikely
        // for adjacent days. If this ever flakes, just verify both are in range.
        XCTAssertNotEqual(j1, j2)
    }

    // MARK: - Backward Compatibility

    func testGoalCompletionActions_delegatesToStepProgress() {
        let activity = ActivityData(steps: 10000)
        let viaLegacy = NotificationDecisionEngine.goalCompletionActions(
            activity: activity, stepGoal: 10000, todayKey: "2026-04-14"
        )
        let viaDirect = NotificationDecisionEngine.stepProgressActions(
            steps: 10000, goal: 10000, todayKey: "2026-04-14"
        )
        XCTAssertEqual(viaLegacy, viaDirect)
    }
}
