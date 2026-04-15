import Foundation
@preconcurrency import GRDB

// MARK: - Supporting types

struct SetPatch: Sendable {
    var reps: Int?
    var weight: Double?
    var isCompleted: Bool?
    var setNumber: Int?
    var setType: SetType?
}

struct PersonalBest: Identifiable {
    var exerciseId: String
    var exerciseName: String
    var equipment: String?
    var maxWeight: Double
    var achievedAt: Date

    var id: String { exerciseId }

    /// "exercise: equipment" or just "exercise" when equipment is nil.
    var displayName: String { equipment.map { "\(exerciseName): \($0)" } ?? exerciseName }
}

// MARK: - SessionSetRepository

struct SessionSetRepository {

    // MARK: - Reads

    static func findForSession(_ sessionId: String) async throws -> [SessionSet] {
        try await AppDatabase.shared.dbPool.read { db in
            try SessionSet
                .filter(Column("session_id") == sessionId && Column("is_completed") == 1)
                .order(Column("exercise_id"), Column("set_number"))
                .fetchAll(db)
        }
    }

    static func findForExercise(sessionId: String, exerciseId: String) async throws -> [SessionSet] {
        try await AppDatabase.shared.dbPool.read { db in
            try SessionSet
                .filter(Column("session_id") == sessionId && Column("exercise_id") == exerciseId)
                .order(Column("set_number").asc)
                .fetchAll(db)
        }
    }

    static func findSetIds(sessionId: String) async throws -> [String] {
        try await AppDatabase.shared.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM session_sets WHERE session_id = ?",
                arguments: [sessionId]
            )
            return rows.map { $0["id"] }
        }
    }

    /// Returns exercise ids in the order they were first added to the session.
    /// Uses MIN(set_number) so the order is stable even when placeholder rows
    /// are replaced by completed rows (which have different rowids).
    static func findExerciseIds(sessionId: String) async throws -> [String] {
        try await AppDatabase.shared.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT exercise_id
                    FROM session_sets
                    WHERE session_id = ?
                    GROUP BY exercise_id
                    ORDER BY MIN(set_number) ASC, MIN(rowid) ASC
                    """,
                arguments: [sessionId]
            )
            return rows.map { $0["exercise_id"] }
        }
    }

    /// Returns the completed_at date when isCompleted is being set to true, nil otherwise.
    static func findOwnership(_ setId: String) async throws -> (sessionId: String, exerciseId: String)? {
        try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT session_id, exercise_id FROM session_sets WHERE id = ?",
                arguments: [setId]
            )
            guard let row else { return nil }
            return (sessionId: row["session_id"], exerciseId: row["exercise_id"])
        }
    }

    /// Returns the minimum completed-set count across exercises in a superset group.
    /// Used to decide when all exercises have been hit equally.
    static func findMinCompletedInGroup(sessionId: String, groupId: String) async throws -> Int {
        try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT MIN(cnt) as min_count
                    FROM (
                        SELECT COUNT(*) as cnt
                        FROM session_sets
                        WHERE session_id = ? AND group_id = ? AND is_completed = 1
                        GROUP BY exercise_id
                    )
                    """,
                arguments: [sessionId, groupId]
            )
            return (row?["min_count"] as Int?) ?? 0
        }
    }

    /// Top-N personal bests: heaviest weight ever lifted per exercise,
    /// plus the date of the session in which that weight was first achieved.
    static func findPersonalBests(userId: String, limit: Int = 10) async throws -> [PersonalBest] {
        try await AppDatabase.shared.dbPool.read { db in
            let sql = """
                SELECT
                    e.id        AS exercise_id,
                    e.name      AS exercise_name,
                    e.equipment AS equipment,
                    pb.max_weight,
                    MAX(ws.started_at) AS started_at
                FROM (
                    SELECT ss.exercise_id, MAX(ss.weight) AS max_weight
                    FROM session_sets ss
                    JOIN workout_sessions w ON w.id = ss.session_id
                    WHERE ss.is_completed = 1 AND ss.weight IS NOT NULL AND w.user_id = ?
                    GROUP BY ss.exercise_id
                ) pb
                JOIN session_sets s
                    ON s.exercise_id = pb.exercise_id
                    AND s.weight = pb.max_weight
                    AND s.is_completed = 1
                JOIN workout_sessions ws
                    ON ws.id = s.session_id
                    AND ws.ended_at IS NOT NULL
                    AND ws.user_id = ?
                JOIN exercises e ON e.id = pb.exercise_id
                GROUP BY pb.exercise_id
                ORDER BY pb.max_weight DESC
                LIMIT ?
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [userId, userId, limit])
            return rows.compactMap { row -> PersonalBest? in
                guard let maxWeight: Double = row["max_weight"] else { return nil }
                let startedAtString: String = row["started_at"] ?? ""
                let achievedAt = ISO8601DateFormatter.shared.date(from: startedAtString)
                    ?? ISO8601DateFormatter.sharedWithFractional.date(from: startedAtString)
                    ?? Date()
                return PersonalBest(
                    exerciseId: row["exercise_id"],
                    exerciseName: row["exercise_name"],
                    equipment: row["equipment"],
                    maxWeight: maxWeight,
                    achievedAt: achievedAt
                )
            }
        }
    }

    /// Exercise ids ordered by how recently they were used in a completed session.
    static func findRecentlyUsedExerciseIds(userId: String) async throws -> [String] {
        try await AppDatabase.shared.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT s.exercise_id
                    FROM session_sets s
                    JOIN workout_sessions ws ON ws.id = s.session_id
                    WHERE s.is_completed = 1 AND ws.ended_at IS NOT NULL AND ws.user_id = ?
                    GROUP BY s.exercise_id
                    ORDER BY MAX(ws.started_at) DESC
                    """,
                arguments: [userId]
            )
            return rows.map { $0["exercise_id"] }
        }
    }

    /// Full set history for an exercise, newest sessions first.
    static func findHistory(
        exerciseId: String
    ) async throws -> [(set: SessionSet, sessionStartedAt: Date)] {
        try await AppDatabase.shared.dbPool.read { db in
            let sql = """
                SELECT s.*, ws.started_at AS session_started_at
                FROM session_sets s
                JOIN workout_sessions ws ON ws.id = s.session_id
                WHERE s.exercise_id = ?
                  AND s.is_completed = 1
                  AND ws.ended_at IS NOT NULL
                ORDER BY ws.started_at DESC, s.set_number ASC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [exerciseId])
            return try rows.map { row in
                let set = try SessionSet(row: row)
                let startedAtString: String = row["session_started_at"] ?? ""
                let sessionStartedAt = ISO8601DateFormatter.shared.date(from: startedAtString)
                    ?? ISO8601DateFormatter.sharedWithFractional.date(from: startedAtString)
                    ?? Date()
                return (set: set, sessionStartedAt: sessionStartedAt)
            }
        }
    }

    /// Returns the latest completed_at timestamp across all sets in a session.
    static func findLatestCompletedAt(sessionId: String) async throws -> Date? {
        try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT MAX(completed_at) AS latest
                    FROM session_sets
                    WHERE session_id = ? AND is_completed = 1 AND completed_at IS NOT NULL
                    """,
                arguments: [sessionId]
            )
            guard let dateStr: String = row?["latest"] else { return nil }
            return ISO8601DateFormatter.shared.date(from: dateStr)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: dateStr)
        }
    }

    /// Returns the number of completed sets in a session.
    static func countCompleted(sessionId: String) async throws -> Int {
        try await AppDatabase.shared.dbPool.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session_sets WHERE session_id = ? AND is_completed = 1",
                arguments: [sessionId]
            )
            return count ?? 0
        }
    }

    // MARK: - Writes

    static func insert(_ set: SessionSet) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try set.insert(db)
        }
    }

    /// Applies a partial update from SetPatch. Returns the completedAt timestamp
    /// when isCompleted is being flipped to true, otherwise nil.
    @discardableResult
    static func update(_ setId: String, patch: SetPatch) async throws -> Date? {
        try await AppDatabase.shared.dbPool.write { db in
            var setClauses: [String] = []
            var args: [DatabaseValue] = []

            if let reps = patch.reps {
                setClauses.append("reps = ?")
                args.append(reps.databaseValue)
            }
            if let weight = patch.weight {
                setClauses.append("weight = ?")
                args.append(weight.databaseValue)
            }

            var completedAt: Date? = nil
            if let isCompleted = patch.isCompleted {
                setClauses.append("is_completed = ?")
                args.append((isCompleted ? 1 : 0).databaseValue)
                if isCompleted {
                    let now = Date()
                    completedAt = now
                    setClauses.append("completed_at = ?")
                    args.append(ISO8601DateFormatter.shared.string(from: now).databaseValue)
                } else {
                    setClauses.append("completed_at = NULL")
                }
            }
            if let setNumber = patch.setNumber {
                setClauses.append("set_number = ?")
                args.append(setNumber.databaseValue)
            }
            if let setType = patch.setType {
                setClauses.append("set_type = ?")
                args.append(setType.rawValue.databaseValue)
            }

            guard !setClauses.isEmpty else { return nil }

            let sql = "UPDATE session_sets SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            args.append(setId.databaseValue)
            try db.execute(sql: sql, arguments: StatementArguments(args))
            return completedAt
        }
    }

    static func setCompletedAt(_ setId: String, date: Date) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "UPDATE session_sets SET completed_at = ? WHERE id = ?",
                arguments: [ISO8601DateFormatter.shared.string(from: date), setId]
            )
        }
    }

    static func setGroupId(_ setId: String, groupId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "UPDATE session_sets SET group_id = ? WHERE id = ?",
                arguments: [groupId, setId]
            )
        }
    }

    static func delete(_ setId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM session_sets WHERE id = ?",
                arguments: [setId]
            )
        }
    }

    static func deleteForSession(_ sessionId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM session_sets WHERE session_id = ?",
                arguments: [sessionId]
            )
        }
    }
}
