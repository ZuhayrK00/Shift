import XCTest
@testable import Shift

final class WorkoutDurationEstimatorTests: XCTestCase {

    // MARK: - Empty input

    func testEmptyExercises_returnsZero() {
        let result = WorkoutDurationEstimator.estimate(exercises: [])
        XCTAssertEqual(result, 0)
    }

    func testZeroCounts_returnsZero() {
        let result = WorkoutDurationEstimator.estimate(exerciseCount: 0, totalSets: 0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Basic estimation

    func testSingleExercise_includesWarmup() {
        // 1 exercise, 3 sets, 10 reps, 90s rest
        // Warmup: 300s
        // Sets: 3 × (10×3 + 90) - 90 = 3×120 - 90 = 270s
        // Total: 570s = 9.5 → 10 min
        let exercise = makePlanExercise(sets: 3, repsMin: 10, repsMax: 10, rest: 90)
        let result = WorkoutDurationEstimator.estimate(exercises: [exercise])
        XCTAssertEqual(result, 10)
    }

    func testMultipleExercises_includesTransitionTime() {
        // 2 exercises, each 3 sets × 10 reps, 90s rest
        // Warmup: 300s
        // Each exercise: 3 × (30 + 90) - 90 = 270s
        // Transition: 60s (between the two)
        // Total: 300 + 270 + 60 + 270 = 900s = 15 min
        let exercises = [
            makePlanExercise(sets: 3, repsMin: 10, repsMax: 10, rest: 90),
            makePlanExercise(sets: 3, repsMin: 10, repsMax: 10, rest: 90)
        ]
        let result = WorkoutDurationEstimator.estimate(exercises: exercises)
        XCTAssertEqual(result, 15)
    }

    func testUsesMaxReps_whenBothProvided() {
        // Should use targetRepsMax (12) not targetRepsMin (8)
        let exercise = makePlanExercise(sets: 3, repsMin: 8, repsMax: 12, rest: 90)
        let result = WorkoutDurationEstimator.estimate(exercises: [exercise])

        // 300 + 3×(12×3 + 90) - 90 = 300 + 3×126 - 90 = 300 + 378 - 90 = 588 → 10 min
        XCTAssertEqual(result, 10)
    }

    func testDefaultsTo10Reps_whenNoRepsSpecified() {
        let exercise = makePlanExercise(sets: 3, repsMin: nil, repsMax: nil, rest: 90)
        let result = WorkoutDurationEstimator.estimate(exercises: [exercise])

        // Same as 10 reps: 300 + 3×(30+90) - 90 = 570 → 10 min
        XCTAssertEqual(result, 10)
    }

    func testUsesDefaultRest_whenNoRestSpecified() {
        let exercise = makePlanExercise(sets: 3, repsMin: 10, repsMax: 10, rest: nil)
        // defaultRestSeconds = 90, same as explicit 90
        let result = WorkoutDurationEstimator.estimate(exercises: [exercise], defaultRestSeconds: 90)
        XCTAssertEqual(result, 10)
    }

    func testCustomDefaultRest() {
        let exercise = makePlanExercise(sets: 3, repsMin: 10, repsMax: 10, rest: nil)
        // With 120s rest: 300 + 3×(30+120) - 120 = 300 + 450 - 120 = 630 → 11 min
        let result = WorkoutDurationEstimator.estimate(exercises: [exercise], defaultRestSeconds: 120)
        XCTAssertEqual(result, 11)
    }

    // MARK: - Raw counts estimation

    func testRawCountEstimation() {
        let result = WorkoutDurationEstimator.estimate(
            exerciseCount: 5, totalSets: 15, avgReps: 10, defaultRestSeconds: 90
        )
        // Should produce a reasonable estimate for a typical 5-exercise workout
        XCTAssertGreaterThan(result, 30)
        XCTAssertLessThan(result, 90)
    }

    // MARK: - Duration formatting

    func testFormatDuration_minutesOnly() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 45), "45 min")
    }

    func testFormatDuration_exactHour() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 60), "1 hr")
    }

    func testFormatDuration_hoursAndMinutes() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 75), "1 hr 15 min")
    }

    func testFormatDuration_multipleHours() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 120), "2 hrs")
    }

    func testFormatDuration_multipleHoursAndMinutes() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 150), "2 hrs 30 min")
    }

    func testFormatDuration_zero() {
        XCTAssertEqual(WorkoutDurationEstimator.formatDuration(minutes: 0), "—")
    }

    // MARK: - Helpers

    private func makePlanExercise(
        sets: Int,
        repsMin: Int?,
        repsMax: Int?,
        rest: Int?
    ) -> PlanExercise {
        PlanExercise(
            id: UUID().uuidString.lowercased(),
            planId: "plan-1",
            exerciseId: "ex-1",
            position: 0,
            targetSets: sets,
            targetRepsMin: repsMin,
            targetRepsMax: repsMax,
            targetWeight: nil,
            restSeconds: rest,
            groupId: nil
        )
    }
}
