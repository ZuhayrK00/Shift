import Foundation
@preconcurrency import GRDB

struct ExerciseRepository {

    // MARK: - Reads

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
    static func replaceBuiltIn(_ remote: [Exercise]) async throws {
        guard !remote.isEmpty else { return }
        try await AppDatabase.shared.dbPool.write { db in
            // Remove stale built-ins no longer in the remote list
            let remoteIds = remote.map { $0.id }
            let placeholders = remoteIds.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: "DELETE FROM exercises WHERE is_built_in = 1 AND id NOT IN (\(placeholders))",
                arguments: StatementArguments(remoteIds)
            )
            // Upsert every remote exercise (PersistenceConflictPolicy is .replace)
            for exercise in remote {
                try exercise.save(db)
            }
        }
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
