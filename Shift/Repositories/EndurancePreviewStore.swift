import Foundation
@preconcurrency import GRDB

struct EndurancePreviewStore: @unchecked Sendable {
    let database: AppDatabase
    static var shared: Self { .init(database: .shared) }

    func receipt(owner: String) async throws -> EnduranceWeekPreview? {
        try await database.dbPool.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT details FROM endurance_week_previews WHERE user_id = ?", arguments: [owner]) else { return nil }
            return try EnduranceCoding.decoder().decode(EnduranceWeekPreview.self, from: Data(json.utf8))
        }
    }
    func remember(_ receipt: EnduranceWeekPreview) async throws {
        let json = String(decoding: try EnduranceCoding.encoder().encode(receipt), as: UTF8.self)
        try await database.dbPool.write { db in
            try db.execute(sql: "INSERT INTO endurance_week_previews(user_id,details) VALUES (?,?) ON CONFLICT(user_id) DO UPDATE SET details=excluded.details", arguments: [receipt.userID, json])
        }
    }
    /// Remote save and claim have already committed. Cache both locally in one transaction.
    /// Never enqueue another remote insert or overwrite a locally pending edit/deletion.
    func apply(_ receipt: EnduranceWeekPreview, sessions: [TrainingSession]) async throws {
        guard sessions.allSatisfy({ $0.userId == receipt.userID && receipt.sessionIDs.contains($0.id) && $0.isValid }) else { throw EnduranceError.wrongAccount }
        let json = String(decoding: try EnduranceCoding.encoder().encode(receipt), as: UTF8.self)
        try await database.dbPool.write { db in
            if try Bool.fetchOne(db, sql: "SELECT applied FROM endurance_week_previews WHERE user_id=?", arguments: [receipt.userID]) == true { return }
            for record in sessions {
                let pending = try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM mutation_queue WHERE table_name='training_sessions' AND user_id=?
                    AND json_valid(payload) AND json_extract(payload,'$.id')=?)
                    """, arguments: [receipt.userID, record.id]) ?? false
                let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM training_sessions WHERE id=? AND user_id=?)", arguments: [record.id, receipt.userID]) ?? false
                if !pending && !exists { try EnduranceStore.upsert(record, in: db) }
            }
            try db.execute(sql: "INSERT INTO endurance_week_previews(user_id,details,applied) VALUES (?,?,1) ON CONFLICT(user_id) DO UPDATE SET details=excluded.details, applied=1", arguments: [receipt.userID, json])
        }
    }
}
