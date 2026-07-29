import XCTest
@testable import Shift

final class NotificationDecisionEngineTests: XCTestCase {
    // MARK: - Step completion policy

    func testStepGoalRequiresPositiveGoal() {
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 10_000, goal: nil))
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 10_000, goal: 0))
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 10_000, goal: -1))
    }

    func testStepGoalDoesNotNotifyBeforeCompletion() {
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 9_999, goal: 10_000))
    }

    func testStepGoalNotifiesAtExactCompletion() {
        XCTAssertTrue(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 10_000, goal: 10_000))
    }

    func testStepGoalNotifiesWhenExceeded() {
        XCTAssertTrue(NotificationDecisionEngine.shouldNotifyStepGoal(steps: 12_000, goal: 10_000))
    }

    func testStepMessageIsSpecificAndNeutral() {
        let message = NotificationDecisionEngine.stepGoalMessage(goal: 10_000)
        XCTAssertEqual(message.title, "Daily step goal complete")
        XCTAssertEqual(message.body, "You reached 10,000 steps today.")
        XCTAssertFalse(message.body.localizedCaseInsensitiveContains("crush"))
    }

    func testLateStepMessageClearlyRefersToYesterday() {
        let message = NotificationDecisionEngine.stepGoalMessage(
            goal: 8_000,
            day: .yesterday
        )
        XCTAssertEqual(message.body, "You reached 8,000 steps yesterday.")
    }

    // MARK: - Weekly frequency policy

    func testFrequencyGoalRequiresPositiveTarget() {
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyFrequencyGoal(completed: 4, target: nil))
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyFrequencyGoal(completed: 4, target: 0))
    }

    func testFrequencyGoalDoesNotNotifyBeforeCompletion() {
        XCTAssertFalse(NotificationDecisionEngine.shouldNotifyFrequencyGoal(completed: 3, target: 4))
    }

    func testFrequencyGoalNotifiesAtOrAboveTarget() {
        XCTAssertTrue(NotificationDecisionEngine.shouldNotifyFrequencyGoal(completed: 4, target: 4))
        XCTAssertTrue(NotificationDecisionEngine.shouldNotifyFrequencyGoal(completed: 5, target: 4))
    }

    func testFrequencyMessageHandlesSingularWorkout() {
        let message = NotificationDecisionEngine.frequencyGoalMessage(target: 1)
        XCTAssertEqual(message.body, "You completed 1 workout this week.")
    }

    func testFrequencyMessageHandlesPluralWorkouts() {
        let message = NotificationDecisionEngine.frequencyGoalMessage(target: 3)
        XCTAssertEqual(message.body, "You completed 3 workouts this week.")
    }

    // MARK: - Exercise achievement wording

    func testExerciseMessageIncludesExerciseTargetAndUnit() {
        let message = NotificationDecisionEngine.exerciseGoalMessage(
            exerciseName: "Bench Press",
            targetWeight: 102.5,
            unit: "kg"
        )
        XCTAssertEqual(message.title, "Exercise goal achieved")
        XCTAssertEqual(message.body, "Bench Press: you reached 102.5 kg.")
    }

    func testExerciseMessageOmitsUnnecessaryDecimal() {
        let message = NotificationDecisionEngine.exerciseGoalMessage(
            exerciseName: "Deadlift",
            targetWeight: 180,
            unit: "kg"
        )
        XCTAssertEqual(message.body, "Deadlift: you reached 180 kg.")
    }

    // MARK: - Settings migration

    func testLegacyReminderSettingsMigrateToAchievementSettings() throws {
        let data = Data(
            """
            {
              "exercise_goal_reminders": false,
              "frequency_reminders": true,
              "step_goal_reminders": false,
              "progress_reminders": true
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(NotificationSettings.self, from: data)
        XCTAssertFalse(settings.exerciseGoalAchievements)
        XCTAssertTrue(settings.frequencyGoalAchievements)
        XCTAssertFalse(settings.stepGoalAchievements)
        XCTAssertTrue(settings.workoutIdleAlerts)
    }

    func testNewAchievementSettingsTakePrecedenceOverLegacyValues() throws {
        let data = Data(
            """
            {
              "exercise_goal_achievements": true,
              "exercise_goal_reminders": false,
              "frequency_goal_achievements": false,
              "frequency_reminders": true,
              "step_goal_achievements": true,
              "step_goal_reminders": false,
              "workout_idle_alerts": false
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(NotificationSettings.self, from: data)
        XCTAssertTrue(settings.exerciseGoalAchievements)
        XCTAssertFalse(settings.frequencyGoalAchievements)
        XCTAssertTrue(settings.stepGoalAchievements)
        XCTAssertFalse(settings.workoutIdleAlerts)
    }

    func testEncodedSettingsContainOnlyCurrentNotificationKeys() throws {
        var settings = NotificationSettings()
        settings.exerciseGoalAchievements = false
        settings.frequencyGoalAchievements = true
        settings.stepGoalAchievements = false
        settings.workoutIdleAlerts = true

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["exercise_goal_achievements"] as? Bool, false)
        XCTAssertEqual(object["frequency_goal_achievements"] as? Bool, true)
        XCTAssertEqual(object["step_goal_achievements"] as? Bool, false)
        XCTAssertEqual(object["workout_idle_alerts"] as? Bool, true)
        XCTAssertNil(object["exercise_goal_reminders"])
        XCTAssertNil(object["progress_reminders"])
    }
}
