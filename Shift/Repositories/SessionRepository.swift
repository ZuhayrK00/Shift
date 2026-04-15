import Foundation
@preconcurrency import GRDB

// MARK: - Supporting types

struct SessionSummaryExercise: Identifiable {
    var id: String
    var name: String
    var setCount: Int
}

// MARK: - SessionRepository

struct SessionRepository {

    // MARK: - Reads

    static func findById(_ id: String) async throws -> WorkoutSession? {
        try await AppDatabase.shared.dbPool.read { db in
            try WorkoutSession.fetchOne(db, key: id)
        }
    }

    static func findLatestInProgress(userId: String) async throws -> WorkoutSession? {
        try await AppDatabase.shared.dbPool.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId)
                .filter(Column("ended_at") == nil)
                .order(Column("started_at").desc)
                .fetchOne(db)
        }
    }

    static func findCompleted(userId: String) async throws -> [WorkoutSession] {
        try await AppDatabase.shared.dbPool.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId)
                .filter(Column("ended_at") != nil)
                .order(Column("started_at").asc)
                .fetchAll(db)
        }
    }

    static func findInProgress(userId: String) async throws -> [WorkoutSession] {
        try await AppDatabase.shared.dbPool.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId)
                .filter(Column("ended_at") == nil)
                .order(Column("started_at").asc)
                .fetchAll(db)
        }
    }

    /// Returns one row per unique exercise in the session, ordered by first appearance.
    static func findExerciseSummaries(sessionId: String) async throws -> [SessionSummaryExercise] {
        try await AppDatabase.shared.dbPool.read { db in
            let sql = """
                SELECT e.id, e.name, COUNT(s.id) as set_count
                FROM session_sets s
                JOIN exercises e ON e.id = s.exercise_id
                WHERE s.session_id = ?
                GROUP BY e.id, e.name
                ORDER BY MIN(s.rowid) ASC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [sessionId])
            return rows.map { row in
                SessionSummaryExercise(
                    id: row["id"],
                    name: row["name"],
                    setCount: row["set_count"]
                )
            }
        }
    }

    /// Returns completed sessions since a given date for a user.
    static func findCompletedSince(_ date: Date, userId: String) async throws -> [WorkoutSession] {
        let dateString = ISO8601DateFormatter.shared.string(from: date)
        return try await AppDatabase.shared.dbPool.read { db in
            try WorkoutSession
                .filter(Column("ended_at") != nil
                        && Column("user_id") == userId
                        && Column("started_at") >= dateString)
                .order(Column("started_at").asc)
                .fetchAll(db)
        }
    }

    /// Returns the average hour (0-23) at which the user starts their workouts,
    /// based on completed sessions. Returns nil if no history exists.
    static func findAverageWorkoutHour(userId: String) async throws -> Int? {
        try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT AVG(CAST(strftime('%H', started_at) AS INTEGER)) as avg_hour
                    FROM workout_sessions
                    WHERE ended_at IS NOT NULL AND user_id = ?
                    """,
                arguments: [userId]
            )
            return row?["avg_hour"] as Int?
        }
    }

    // MARK: - Writes

    static func insert(_ session: WorkoutSession) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try session.insert(db)
        }
    }

    static func setEndedAt(_ sessionId: String, _ endedAt: Date?) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            let endedAtString = endedAt.map { ISO8601DateFormatter.shared.string(from: $0) }
            try db.execute(
                sql: "UPDATE workout_sessions SET ended_at = ? WHERE id = ?",
                arguments: [endedAtString, sessionId]
            )
        }
    }

    static func setOriginalEndedAt(_ sessionId: String, _ originalEndedAt: Date?) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            let str = originalEndedAt.map { ISO8601DateFormatter.shared.string(from: $0) }
            try db.execute(
                sql: "UPDATE workout_sessions SET original_ended_at = ? WHERE id = ?",
                arguments: [str, sessionId]
            )
        }
    }

    static func delete(_ sessionId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            // Delete child session_sets first to avoid orphans
            try db.execute(
                sql: "DELETE FROM session_sets WHERE session_id = ?",
                arguments: [sessionId]
            )
            try db.execute(
                sql: "DELETE FROM workout_sessions WHERE id = ?",
                arguments: [sessionId]
            )
        }
    }
}
