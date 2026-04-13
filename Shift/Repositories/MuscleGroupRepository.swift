import Foundation
@preconcurrency import GRDB

struct MuscleGroupRepository {

    // MARK: - Reads

    static func findAll() async throws -> [MuscleGroup] {
        try await AppDatabase.shared.dbPool.read { db in
            try MuscleGroup.order(Column("name")).fetchAll(db)
        }
    }

    // MARK: - Writes

    static func upsert(_ group: MuscleGroup) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try group.save(db)
        }
    }
}
