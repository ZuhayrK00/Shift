import XCTest
@preconcurrency import GRDB
@testable import Shift

final class PersistenceRegressionTests: XCTestCase {

    func testSetWeightCanBeCleared() async throws {
        let setId = "test-weight-\(UUID().uuidString)"
        let set = SessionSet(
            id: setId,
            sessionId: "test-session",
            exerciseId: "test-exercise",
            setNumber: 1,
            reps: 8,
            weight: 42.5,
            isCompleted: true
        )
        try await SessionSetRepository.insert(set)
        defer { Task { try? await SessionSetRepository.delete(setId) } }

        try await SessionSetRepository.update(
            setId,
            patch: SetPatch(weight: .some(nil))
        )

        let storedWeight: Double? = try await AppDatabase.shared.dbPool.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT weight FROM session_sets WHERE id = ?",
                arguments: [setId]
            )
        }
        XCTAssertNil(storedWeight)
    }

    func testClearingExerciseNoteReturnsSyncTargetAndClearsValue() async throws {
        let setId = "test-note-\(UUID().uuidString)"
        let sessionId = "test-session-\(UUID().uuidString)"
        let exerciseId = "test-exercise-\(UUID().uuidString)"
        let set = SessionSet(
            id: setId,
            sessionId: sessionId,
            exerciseId: exerciseId,
            setNumber: 1,
            notes: "old note"
        )
        try await SessionSetRepository.insert(set)
        defer { Task { try? await SessionSetRepository.delete(setId) } }

        let targetId = try await SessionSetRepository.setExerciseNote(
            sessionId: sessionId,
            exerciseId: exerciseId,
            note: nil
        )
        let storedNote = try await SessionSetRepository.findExerciseNote(
            sessionId: sessionId,
            exerciseId: exerciseId
        )

        XCTAssertEqual(targetId, setId)
        XCTAssertNil(storedNote)
    }

    func testAtomicMutationRollsBackLocalWriteOnFailure() async throws {
        enum ExpectedFailure: Error { case stopTransaction }

        let setId = "test-rollback-\(UUID().uuidString)"
        let set = SessionSet(
            id: setId,
            sessionId: "test-session",
            exerciseId: "test-exercise",
            setNumber: 1
        )
        let mutation = LocalMutation(
            table: "session_sets",
            op: "insert",
            payload: ["id": setId]
        )

        do {
            try await MutationQueueRepository.performAtomically(
                mutations: [mutation]
            ) { db in
                try set.insert(db)
                throw ExpectedFailure.stopTransaction
            }
            XCTFail("Expected the transaction to fail")
        } catch {
            // Expected: GRDB must roll the inserted set back with the transaction.
        }

        let rowExists = try await AppDatabase.shared.dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM session_sets WHERE id = ?)",
                arguments: [setId]
            ) ?? false
        }
        XCTAssertFalse(rowExists)
    }

    func testMutationQueueHasRetryAndUserScopingColumns() async throws {
        let columns = try await AppDatabase.shared.dbPool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(mutation_queue)")
                .compactMap { $0["name"] as String? }
        }

        XCTAssertTrue(columns.contains("user_id"))
        XCTAssertTrue(columns.contains("attempt_count"))
        XCTAssertTrue(columns.contains("last_error"))
        XCTAssertTrue(columns.contains("next_attempt_at"))
    }

    func testExerciseGoalCanBeDeletedFromLocalStorage() async throws {
        let goal = ExerciseGoal(
            id: "test-goal-\(UUID().uuidString)",
            userId: "test-user-\(UUID().uuidString)",
            exerciseId: "test-exercise-\(UUID().uuidString)",
            targetWeightIncrease: 5,
            baselineWeight: 80,
            deadline: Date().addingTimeInterval(86_400)
        )
        try await ExerciseGoalRepository.insert(goal)
        defer { Task { try? await ExerciseGoalRepository.delete(goal.id) } }

        try await ExerciseGoalRepository.delete(goal.id)

        let stored = try await ExerciseGoalRepository.findById(goal.id)
        XCTAssertNil(stored)
    }

    func testWarmupTapLogsImmediatelyWithoutConsumingWorkingSets() async throws {
        let sessionId = "test-warmup-session-\(UUID().uuidString)"
        let exerciseId = "test-warmup-exercise-\(UUID().uuidString)"
        let oldPendingWarmup = SessionSet(
            id: "test-pending-warmup-\(UUID().uuidString)",
            sessionId: sessionId,
            exerciseId: exerciseId,
            setNumber: 1,
            reps: 8,
            weight: 30,
            setType: .warmup
        )
        let workingSet = SessionSet(
            id: "test-working-set-\(UUID().uuidString)",
            sessionId: sessionId,
            exerciseId: exerciseId,
            setNumber: 2,
            reps: 10,
            weight: 80
        )
        try await SessionSetRepository.insert(oldPendingWarmup)
        try await SessionSetRepository.insert(workingSet)
        defer {
            Task {
                try? await AppDatabase.shared.dbPool.write { db in
                    try db.execute(
                        sql: """
                            DELETE FROM session_sets
                            WHERE session_id = ? AND exercise_id = ?
                            """,
                        arguments: [sessionId, exerciseId]
                    )
                }
            }
        }

        let first = try await WorkoutService.logWarmupSet(
            sessionId: sessionId,
            exerciseId: exerciseId,
            reps: 6,
            weight: 45
        )
        XCTAssertTrue(first.isCompleted)
        XCTAssertEqual(first.setType, .warmup)
        XCTAssertEqual(first.reps, 6)
        XCTAssertEqual(first.weight, 45)

        _ = try await WorkoutService.logWarmupSet(
            sessionId: sessionId,
            exerciseId: exerciseId,
            reps: 3,
            weight: 65
        )

        let stored = try await SessionSetRepository.findForExercise(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
        XCTAssertEqual(stored.map(\.setNumber), [1, 2, 3])
        XCTAssertEqual(stored.filter { $0.setType == .warmup }.count, 2)
        XCTAssertTrue(stored.filter { $0.setType == .warmup }.allSatisfy(\.isCompleted))
        XCTAssertEqual(stored.last?.id, workingSet.id)
        XCTAssertFalse(stored.last?.isCompleted ?? true)
        XCTAssertFalse(stored.contains(where: { $0.id == oldPendingWarmup.id }))
    }

    func testFreshDatabaseRunsEveryMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shift-db-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try AppDatabase(
            databaseURL: directory.appendingPathComponent("shift.db")
        )
        let columns = try database.dbPool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(mutation_queue)")
                .compactMap { $0["name"] as String? }
        }

        XCTAssertTrue(columns.contains("user_id"))
        XCTAssertTrue(columns.contains("attempt_count"))
        XCTAssertTrue(columns.contains("next_attempt_at"))
    }
}
