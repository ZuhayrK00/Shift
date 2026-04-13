import Foundation
@preconcurrency import GRDB

struct ProfileRepository {

    // MARK: - Reads

    static func findById(_ id: String) async throws -> Profile? {
        try await AppDatabase.shared.dbPool.read { db in
            try Profile.fetchOne(db, key: id)
        }
    }

    // MARK: - Writes

    /// Upsert a profile row. All mutable columns are updated on conflict.
    static func upsert(_ profile: Profile) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try profile.save(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM profiles WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
