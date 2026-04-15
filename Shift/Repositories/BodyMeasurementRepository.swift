import Foundation
@preconcurrency import GRDB

struct BodyMeasurementRepository {

    // MARK: - Reads

    /// All measurements for a user, newest first.
    static func findAll(userId: String) async throws -> [BodyMeasurement] {
        try await AppDatabase.shared.dbPool.read { db in
            try BodyMeasurement
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchAll(db)
        }
    }

    /// All measurements of a specific type for a user, newest first.
    static func findByType(userId: String, type: String) async throws -> [BodyMeasurement] {
        try await AppDatabase.shared.dbPool.read { db in
            try BodyMeasurement
                .filter(Column("user_id") == userId && Column("type") == type)
                .order(Column("recorded_at").desc)
                .fetchAll(db)
        }
    }

    /// Latest measurement for each type.
    static func findLatestPerType(userId: String) async throws -> [BodyMeasurement] {
        try await AppDatabase.shared.dbPool.read { db in
            let sql = """
                SELECT m.* FROM body_measurements m
                INNER JOIN (
                    SELECT type, MAX(recorded_at) as max_date
                    FROM body_measurements
                    WHERE user_id = ?
                    GROUP BY type
                ) latest ON m.type = latest.type AND m.recorded_at = latest.max_date
                WHERE m.user_id = ?
                ORDER BY m.type
                """
            return try BodyMeasurement.fetchAll(db, sql: sql, arguments: [userId, userId])
        }
    }

    /// Most recent measurement date for a user (any type).
    static func findMostRecentDate(userId: String) async throws -> Date? {
        try await AppDatabase.shared.dbPool.read { db in
            try BodyMeasurement
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchOne(db)?
                .recordedAt
        }
    }

    // MARK: - Writes

    static func upsert(_ measurement: BodyMeasurement) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try measurement.save(db)
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM body_measurements WHERE id = ?", arguments: [id])
        }
    }
}
