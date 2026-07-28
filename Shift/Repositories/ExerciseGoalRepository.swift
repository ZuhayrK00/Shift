import Foundation
@preconcurrency import GRDB

// MARK: - ExerciseGoalRepository

struct ExerciseGoalRepository {

    // MARK: - Reads

    static func findByExercise(_ exerciseId: String) async throws -> [ExerciseGoal] {
        guard let userId = authManager.currentUserId else { return [] }
        return try await AppDatabase.shared.dbPool.read { db in
            try ExerciseGoal
                .filter(Column("exercise_id") == exerciseId && Column("user_id") == userId)
                .order(Column("deadline").asc)
                .fetchAll(db)
        }
    }

    static func findActiveForUser(_ userId: String) async throws -> [ExerciseGoal] {
        return try await AppDatabase.shared.dbPool.read { db in
            try ExerciseGoal
                .filter(Column("user_id") == userId && Column("is_completed") == 0)
                .order(Column("deadline").asc)
                .fetchAll(db)
        }
    }

    static func findById(_ id: String) async throws -> ExerciseGoal? {
        try await AppDatabase.shared.dbPool.read { db in
            try ExerciseGoal.fetchOne(db, key: id)
        }
    }

    /// Returns the current max weight ever lifted for an exercise.
    static func findCurrentMaxWeight(exerciseId: String) async throws -> Double? {
        guard let userId = authManager.currentUserId else { return nil }
        return try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT MAX(weight) as max_weight
                    FROM session_sets ss
                    JOIN workout_sessions ws ON ws.id = ss.session_id
                    WHERE ss.exercise_id = ?
                      AND ss.is_completed = 1
                      AND ss.weight IS NOT NULL
                      AND ws.user_id = ?
                    """,
                arguments: [exerciseId, userId]
            )
            return row?["max_weight"] as Double?
        }
    }

    // MARK: - Writes

    static func insert(_ goal: ExerciseGoal) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try goal.insert(db)
        }
    }

    static func update(_ goal: ExerciseGoal) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try goal.update(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM exercise_goals WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
