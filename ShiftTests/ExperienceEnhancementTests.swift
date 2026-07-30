import XCTest
@testable import Shift

final class ExperienceEnhancementTests: XCTestCase {
    func testLegacyThreeDayGoalDefaultsToMondayWednesdayFriday() {
        XCTAssertEqual(
            WeeklyTrainingScheduleDefaults.days(for: 3),
            [1, 3, 5]
        )
    }

    func testExplicitTrainingDaysAreSanitizedAndDriveWeeklyTarget() throws {
        let data = Data(
            """
            {
              "weekly_frequency_goal": 5,
              "weekly_training_days": [5, 1, 3, 3, 8, 0],
              "weekly_training_days_effective_date": "2026-07-30"
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(settings.normalizedWeeklyTrainingDays, [1, 3, 5])
        XCTAssertEqual(settings.effectiveWeeklyFrequencyGoal, 3)
    }

    func testNewScheduleDoesNotCreateRetroactiveMissedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var settings = UserSettings()
        settings.weeklyTrainingDays = [1, 3, 5]
        settings.weeklyTrainingDaysEffectiveDate = "2026-07-30"

        let before = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 29)
        )!
        let effective = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 30)
        )!

        XCTAssertFalse(
            settings.weeklyTrainingDaysWereEffective(
                on: before,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            settings.weeklyTrainingDaysWereEffective(
                on: effective,
                calendar: calendar
            )
        )
    }

    func testPlateCalculatorPresentationSnapshotsCurrentInput() {
        let request = PlateCalculatorRequest(targetWeight: 102.5, unit: "kg")
        XCTAssertEqual(request.targetWeight, 102.5)
        XCTAssertEqual(request.unit, "kg")
    }

    func testTrainingScheduleUsesDateOverrideBeforeWeeklyPlan() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        var schedule = TrainingScheduleSettings(
            weeklyPlanIDs: ["1": "weekly"],
            dateOverrides: [:]
        )

        XCTAssertEqual(schedule.planID(for: monday, calendar: calendar), "weekly")

        schedule.dateOverrides["2026-07-27"] = "special"
        XCTAssertEqual(schedule.planID(for: monday, calendar: calendar), "special")

        schedule.dateOverrides["2026-07-27"] = ""
        XCTAssertNil(schedule.planID(for: monday, calendar: calendar))
        XCTAssertTrue(schedule.hasExplicitRestDay(for: monday, calendar: calendar))

        schedule.dateOverrides.removeAll()
        schedule.weeklyPlanIDs["1"] = ""
        XCTAssertNil(schedule.planID(for: monday, calendar: calendar))
        XCTAssertTrue(schedule.hasExplicitRestDay(for: monday, calendar: calendar))
    }

    func testRecoveryGuidanceRespondsToCombinedSignals() {
        let healthy = RecoveryGuidanceService.makeSnapshot(
            metrics: RecoveryHealthMetrics(
                sleepHours: 8,
                hrvMilliseconds: 60,
                hrvBaselineMilliseconds: 55,
                restingHeartRate: 55,
                restingHeartRateBaseline: 56
            ),
            checkIn: 5
        )
        XCTAssertEqual(healthy.recommendation, .train)

        let depleted = RecoveryGuidanceService.makeSnapshot(
            metrics: RecoveryHealthMetrics(
                sleepHours: 5,
                hrvMilliseconds: 35,
                hrvBaselineMilliseconds: 55,
                restingHeartRate: 70,
                restingHeartRateBaseline: 56
            ),
            checkIn: 2
        )
        XCTAssertEqual(depleted.recommendation, .recover)
    }

    func testRecoveryGuidanceNeverOverstatesMissingData() {
        let snapshot = RecoveryGuidanceService.makeSnapshot(
            metrics: .init(),
            checkIn: nil
        )
        XCTAssertEqual(snapshot.recommendation, .checkIn)
        XCTAssertTrue(snapshot.reasons.first?.contains("No recovery signals") == true)
    }
}
