import XCTest
@testable import Shift

final class ModelTests: XCTestCase {

    // MARK: - Exercise.displayName

    func testDisplayName_withEquipment() {
        let exercise = Exercise(
            id: "1", name: "Bench Press", slug: "bench-press",
            primaryMuscleId: "chest", secondaryMuscleIds: [],
            equipment: "Barbell", isBuiltIn: true
        )
        XCTAssertEqual(exercise.displayName, "Bench Press: Barbell")
    }

    func testDisplayName_noEquipment() {
        let exercise = Exercise(
            id: "1", name: "Push Up", slug: "push-up",
            primaryMuscleId: "chest", secondaryMuscleIds: [],
            equipment: nil, isBuiltIn: true
        )
        XCTAssertEqual(exercise.displayName, "Push Up")
    }

    // MARK: - WorkoutSession.isInProgress

    func testIsInProgress_noEndedAt() {
        let session = WorkoutSession(
            id: "s1", userId: "u1", name: "Leg Day",
            startedAt: Date(), endedAt: nil
        )
        XCTAssertTrue(session.isInProgress)
    }

    func testIsInProgress_withEndedAt() {
        let session = WorkoutSession(
            id: "s1", userId: "u1", name: "Leg Day",
            startedAt: Date(), endedAt: Date()
        )
        XCTAssertFalse(session.isInProgress)
    }

    // MARK: - SessionSet.badgeLabel

    func testBadgeLabel_normalSet() {
        let set = SessionSet(
            id: "set1", sessionId: "s1", exerciseId: "e1",
            setNumber: 3, setType: .normal
        )
        XCTAssertEqual(set.badgeLabel, "3")
    }

    func testBadgeLabel_warmupSet() {
        let set = SessionSet(
            id: "set1", sessionId: "s1", exerciseId: "e1",
            setNumber: 1, setType: .warmup
        )
        XCTAssertEqual(set.badgeLabel, "W")
    }

    func testBadgeLabel_dropSet() {
        let set = SessionSet(
            id: "set1", sessionId: "s1", exerciseId: "e1",
            setNumber: 2, setType: .drop
        )
        XCTAssertEqual(set.badgeLabel, "D")
    }

    func testBadgeLabel_failureSet() {
        let set = SessionSet(
            id: "set1", sessionId: "s1", exerciseId: "e1",
            setNumber: 2, setType: .failure
        )
        XCTAssertEqual(set.badgeLabel, "F")
    }

    // MARK: - SetType raw values

    func testSetType_rawValues() {
        XCTAssertEqual(SetType.normal.rawValue, "normal")
        XCTAssertEqual(SetType.warmup.rawValue, "warmup")
        XCTAssertEqual(SetType.drop.rawValue, "drop")
        XCTAssertEqual(SetType.failure.rawValue, "failure")
    }

    func testSetType_allCases() {
        XCTAssertEqual(SetType.allCases.count, 4)
    }

    // MARK: - PlanExercise.repRangeText

    func testRepRangeText_minAndMaxDiffer() {
        let pe = makePlanExercise(repsMin: 8, repsMax: 12)
        XCTAssertEqual(pe.repRangeText(), "8-12")
    }

    func testRepRangeText_minAndMaxEqual() {
        let pe = makePlanExercise(repsMin: 10, repsMax: 10)
        XCTAssertEqual(pe.repRangeText(), "10")
    }

    func testRepRangeText_onlyMin() {
        let pe = makePlanExercise(repsMin: 8, repsMax: nil)
        XCTAssertEqual(pe.repRangeText(), "8")
    }

    func testRepRangeText_onlyMax() {
        let pe = makePlanExercise(repsMin: nil, repsMax: 12)
        XCTAssertEqual(pe.repRangeText(), "12")
    }

    func testRepRangeText_neither() {
        let pe = makePlanExercise(repsMin: nil, repsMax: nil)
        XCTAssertNil(pe.repRangeText())
    }

    // MARK: - PlanExercise.subtitle

    func testSubtitle_withRepRange() {
        let pe = makePlanExercise(sets: 3, repsMin: 8, repsMax: 12)
        XCTAssertEqual(pe.subtitle(), "3 sets × 8-12 reps")
    }

    func testSubtitle_singleSet() {
        let pe = makePlanExercise(sets: 1, repsMin: 10, repsMax: 10)
        XCTAssertEqual(pe.subtitle(), "1 set × 10 reps")
    }

    func testSubtitle_noReps() {
        let pe = makePlanExercise(sets: 4, repsMin: nil, repsMax: nil)
        XCTAssertEqual(pe.subtitle(), "4 sets")
    }

    // MARK: - PlanExercise.defaultReps

    func testDefaultReps_prefersMax() {
        let pe = makePlanExercise(repsMin: 8, repsMax: 12)
        XCTAssertEqual(pe.defaultReps, 12)
    }

    func testDefaultReps_fallsBackToMin() {
        let pe = makePlanExercise(repsMin: 8, repsMax: nil)
        XCTAssertEqual(pe.defaultReps, 8)
    }

    func testDefaultReps_neitherSet_returnsZero() {
        let pe = makePlanExercise(repsMin: nil, repsMax: nil)
        XCTAssertEqual(pe.defaultReps, 0)
    }

    // MARK: - ExerciseGoal.targetWeight

    func testTargetWeight_computedCorrectly() {
        let goal = ExerciseGoal(
            id: "g1", userId: "u1", exerciseId: "e1",
            targetWeightIncrease: 10, baselineWeight: 80,
            deadline: Date()
        )
        XCTAssertEqual(goal.targetWeight, 90)
    }

    func testTargetWeight_zeroIncrease() {
        let goal = ExerciseGoal(
            id: "g1", userId: "u1", exerciseId: "e1",
            targetWeightIncrease: 0, baselineWeight: 60,
            deadline: Date()
        )
        XCTAssertEqual(goal.targetWeight, 60)
    }

    // MARK: - WorkoutSession JSON round-trip

    func testWorkoutSession_jsonRoundTrip() throws {
        let session = WorkoutSession(
            id: "s1", userId: "u1", planId: "p1", name: "Push Day",
            startedAt: Date(timeIntervalSince1970: 1713200000),
            endedAt: Date(timeIntervalSince1970: 1713203600),
            notes: "Great session"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkoutSession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.userId, session.userId)
        XCTAssertEqual(decoded.planId, session.planId)
        XCTAssertEqual(decoded.name, session.name)
        XCTAssertEqual(decoded.notes, session.notes)
        // ISO 8601 round-trip loses sub-second precision; compare within 1s
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, session.startedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.endedAt!.timeIntervalSince1970, session.endedAt!.timeIntervalSince1970, accuracy: 1)
    }

    func testWorkoutSession_jsonRoundTrip_nilOptionals() throws {
        let session = WorkoutSession(
            id: "s1", userId: "u1", name: "Quick Session",
            startedAt: Date(timeIntervalSince1970: 1713200000)
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: data)

        XCTAssertNil(decoded.planId)
        XCTAssertNil(decoded.endedAt)
        XCTAssertNil(decoded.notes)
    }

    // MARK: - SessionSet JSON round-trip

    func testSessionSet_jsonRoundTrip() throws {
        let set = SessionSet(
            id: "set1", sessionId: "s1", exerciseId: "e1",
            setNumber: 2, reps: 10, weight: 80.0, rpe: 8.5,
            isCompleted: true, completedAt: Date(timeIntervalSince1970: 1713200000),
            setType: .drop, notes: "Felt heavy"
        )

        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(SessionSet.self, from: data)

        XCTAssertEqual(decoded.id, set.id)
        XCTAssertEqual(decoded.reps, 10)
        XCTAssertEqual(decoded.weight, 80.0)
        XCTAssertEqual(decoded.rpe, 8.5)
        XCTAssertTrue(decoded.isCompleted)
        XCTAssertEqual(decoded.setType, .drop)
        XCTAssertEqual(decoded.notes, "Felt heavy")
    }

    func testSessionSet_jsonDecode_defaultsSetTypeToNormal() throws {
        // JSON without set_type should default to .normal
        let json = """
        {
            "id": "set1",
            "session_id": "s1",
            "exercise_id": "e1",
            "set_number": 1,
            "reps": 8,
            "is_completed": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SessionSet.self, from: json)
        XCTAssertEqual(decoded.setType, .normal)
    }

    // MARK: - ExerciseGoal JSON round-trip

    func testExerciseGoal_jsonRoundTrip() throws {
        let goal = ExerciseGoal(
            id: "g1", userId: "u1", exerciseId: "e1",
            targetWeightIncrease: 15.0, baselineWeight: 100.0,
            deadline: Date(timeIntervalSince1970: 1713200000),
            isCompleted: false
        )

        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(ExerciseGoal.self, from: data)

        XCTAssertEqual(decoded.id, goal.id)
        XCTAssertEqual(decoded.targetWeightIncrease, 15.0)
        XCTAssertEqual(decoded.baselineWeight, 100.0)
        XCTAssertFalse(decoded.isCompleted)
        XCTAssertNil(decoded.completedAt)
    }

    // MARK: - Helpers

    private func makePlanExercise(
        sets: Int = 3,
        repsMin: Int?,
        repsMax: Int?
    ) -> PlanExercise {
        PlanExercise(
            id: "pe1", planId: "p1", exerciseId: "e1",
            position: 0, targetSets: sets,
            targetRepsMin: repsMin, targetRepsMax: repsMax,
            targetWeight: nil, restSeconds: nil, groupId: nil
        )
    }
}
