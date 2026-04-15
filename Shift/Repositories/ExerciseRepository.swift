import Foundation
@preconcurrency import GRDB

struct ExerciseRepository {

    // MARK: - Reads

    static func findAll() async throws -> [Exercise] {
        try await AppDatabase.shared.dbPool.read { db in
            try Exercise.order(Column("name")).fetchAll(db)
        }
    }

    static func findById(_ id: String) async throws -> Exercise? {
        try await AppDatabase.shared.dbPool.read { db in
            try Exercise.fetchOne(db, key: id)
        }
    }

    /// Returns a dictionary keyed by exercise id. Missing ids are silently absent.
    static func findByIds(_ ids: [String]) async throws -> [String: Exercise] {
        guard !ids.isEmpty else { return [:] }
        return try await AppDatabase.shared.dbPool.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "SELECT * FROM exercises WHERE id IN (\(placeholders))"
            let exercises = try Exercise.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
            return Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
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
