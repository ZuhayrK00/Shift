import Foundation
@preconcurrency import GRDB

struct WeightEntryRepository {

    static func findAll(userId: String) async throws -> [WeightEntry] {
        try await AppDatabase.shared.dbPool.read { db in
            try WeightEntry
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchAll(db)
        }
    }

    static func findLatest(userId: String) async throws -> WeightEntry? {
        try await AppDatabase.shared.dbPool.read { db in
            try WeightEntry
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchOne(db)
        }
    }

    static func insert(_ entry: WeightEntry) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try entry.insert(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM weight_entries WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
