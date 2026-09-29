import Foundation
@preconcurrency import GRDB

struct ExerciseRepository {
    struct CatalogueRedirect: Decodable, Sendable {
        let oldId: String
        let newId: String
        enum CodingKeys: String, CodingKey { case oldId = "old_id", newId = "new_id" }
    }

    // MARK: - Reads

    static func resolveId(_ id: String) async throws -> String {
        try await AppDatabase.shared.dbPool.read { db in try resolveId(id, in: db) }
    }

    static func resolveId(_ id: String, in db: Database) throws -> String {
        try String.fetchOne(db, sql: "SELECT new_id FROM exercise_catalogue_redirects WHERE old_id = ?", arguments: [id]) ?? id
    }

    static func findAll() async throws -> [Exercise] {
        let userId = authManager.currentUserId
        return try await AppDatabase.shared.dbPool.read { db in
            if let userId {
                return try Exercise
                    .filter(Column("is_built_in") == true || Column("created_by") == userId)
                    .order(Column("name"))
                    .fetchAll(db)
            }
            return try Exercise
                .filter(Column("is_built_in") == true)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    static func findById(_ id: String) async throws -> Exercise? {
        let userId = authManager.currentUserId
        return try await AppDatabase.shared.dbPool.read { db in
            if let userId {
                return try Exercise
                    .filter(Column("id") == id)
                    .filter(Column("is_built_in") == true || Column("created_by") == userId)
                    .fetchOne(db)
            }
            return try Exercise
                .filter(Column("id") == id && Column("is_built_in") == true)
                .fetchOne(db)
        }
    }

    /// Returns a dictionary keyed by exercise id. Missing ids are silently absent.
    static func findByIds(_ ids: [String]) async throws -> [String: Exercise] {
        guard !ids.isEmpty else { return [:] }
        let userId = authManager.currentUserId
        return try await AppDatabase.shared.dbPool.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql: String
            var arguments = ids
            if let userId {
                sql = """
                    SELECT * FROM exercises
                    WHERE id IN (\(placeholders))
                      AND (is_built_in = 1 OR created_by = ?)
                    """
                arguments.append(userId)
            } else {
                sql = "SELECT * FROM exercises WHERE id IN (\(placeholders)) AND is_built_in = 1"
            }
            let exercises = try Exercise.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(arguments)
            )
            return Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        }
    }

    /// Returns a dictionary keyed by slug. Used for matching template plans to real exercises.
    static func findBySlugs(_ slugs: [String]) async throws -> [String: Exercise] {
        guard !slugs.isEmpty else { return [:] }
        let userId = authManager.currentUserId
        return try await AppDatabase.shared.dbPool.read { db in
            let placeholders = slugs.map { _ in "?" }.joined(separator: ", ")
            let sql: String
            var arguments = slugs
            if let userId {
                sql = """
                    SELECT * FROM exercises
                    WHERE slug IN (\(placeholders))
                      AND (is_built_in = 1 OR created_by = ?)
                    """
                arguments.append(userId)
            } else {
                sql = "SELECT * FROM exercises WHERE slug IN (\(placeholders)) AND is_built_in = 1"
            }
            let exercises = try Exercise.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(arguments)
            )
            return Dictionary(uniqueKeysWithValues: exercises.map { ($0.slug, $0) })
        }
    }

    // MARK: - Writes

    /// Replace the full built-in catalogue with the remote snapshot.
    /// Exercises created by users (is_built_in = 0) are untouched.
    static func replaceBuiltIn(_ remote: [Exercise], redirects: [CatalogueRedirect] = []) async throws {
        guard !remote.isEmpty else { return }
        try await AppDatabase.shared.dbPool.write { db in
            try applyBuiltIn(remote, redirects: redirects, in: db)
        }
    }

    /// Called inside a single transaction, including the offline queue rewrite.
    static func applyBuiltIn(_ remote: [Exercise], redirects: [CatalogueRedirect], in db: Database) throws {
        guard !remote.isEmpty else { return }
        for redirect in redirects {
            try db.execute(sql: """
                INSERT INTO exercise_catalogue_redirects(old_id,new_id) VALUES(?,?)
                ON CONFLICT(old_id) DO UPDATE SET new_id=excluded.new_id
                WHERE new_id <> excluded.new_id
                """, arguments: [redirect.oldId, redirect.newId])
        }
        // After the first migration, none of the old IDs remain. Avoid thousands
        // of pointless UPDATEs on each routine refresh, particularly large histories.
        let referenced = Set(try String.fetchAll(db, sql: """
            SELECT exercise_id FROM plan_exercises UNION SELECT exercise_id FROM session_sets
            UNION SELECT exercise_id FROM exercise_goals UNION
            SELECT CASE WHEN json_valid(payload) THEN json_extract(payload, '$.exercise_id') END
            FROM mutation_queue WHERE table_name IN ('plan_exercises','session_sets','exercise_goals')
              AND CASE WHEN json_valid(payload) THEN json_extract(payload, '$.exercise_id') END IS NOT NULL
            """).map { $0.lowercased() })
        for redirect in redirects where referenced.contains(redirect.oldId.lowercased()) {
            for table in ["plan_exercises", "session_sets", "exercise_goals"] {
                try db.execute(sql: "UPDATE \(table) SET exercise_id = ? WHERE exercise_id = ? COLLATE NOCASE",
                               arguments: [redirect.newId, redirect.oldId])
            }
            try db.execute(
                sql: """
                UPDATE mutation_queue SET payload = json_set(payload, '$.exercise_id', ?)
                WHERE table_name IN ('plan_exercises', 'session_sets', 'exercise_goals')
                  AND CASE WHEN json_valid(payload) THEN json_extract(payload, '$.exercise_id') END = ? COLLATE NOCASE
                """, arguments: [redirect.newId, redirect.oldId])
        }
        let remoteIds = remote.map { $0.id }
        let placeholders = remoteIds.map { _ in "?" }.joined(separator: ", ")
        try db.execute(sql: "DELETE FROM exercises WHERE is_built_in = 1 AND id NOT IN (\(placeholders))",
                       arguments: StatementArguments(remoteIds))
        for exercise in remote { try exercise.save(db) }
    }

    static func upsert(_ exercise: Exercise) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try exercise.save(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM exercises WHERE id = ?", arguments: [id])
        }
    }
}
