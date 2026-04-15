import Foundation
@preconcurrency import GRDB

struct ProgressPhotoRepository {

    // MARK: - Reads

    /// All photos for a user, newest first.
    static func findAll(userId: String) async throws -> [ProgressPhoto] {
        try await AppDatabase.shared.dbPool.read { db in
            try ProgressPhoto
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchAll(db)
        }
    }

    /// Most recent photo for a user.
    static func findLatest(userId: String) async throws -> ProgressPhoto? {
        try await AppDatabase.shared.dbPool.read { db in
            try ProgressPhoto
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchOne(db)
        }
    }

    // MARK: - Writes

    static func upsert(_ photo: ProgressPhoto) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try photo.save(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM progress_photos WHERE id = ?", arguments: [id])
        }
    }
}
