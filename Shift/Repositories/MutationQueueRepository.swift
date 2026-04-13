import Foundation
@preconcurrency import GRDB

// MARK: - MutationQueueRepository

struct MutationQueueRepository {

    // MARK: - Writes

    /// Serialises the payload dictionary to JSON and appends a row to the queue.
    static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())

        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO mutation_queue (table_name, op, payload, created_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [table, op, payloadString, createdAt]
            )
        }
    }

    static func delete(rowId: Int64) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM mutation_queue WHERE id = ?",
                arguments: [rowId]
            )
        }
    }

    // MARK: - Reads

    static func readPending() async throws -> [MutationQueueRow] {
        try await AppDatabase.shared.dbPool.read { db in
            try MutationQueueRow.fetchAll(db, sql: "SELECT * FROM mutation_queue ORDER BY id ASC")
        }
    }
}
