import Foundation
@preconcurrency import GRDB

struct LocalMutation: @unchecked Sendable {
    var table: String
    var op: String
    var payload: [String: Any]
}

// MARK: - MutationQueueRepository

struct MutationQueueRepository {

    // MARK: - Writes

    /// Serialises the payload dictionary to JSON and appends a row to the queue.
    static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try enqueue(table: table, op: op, payload: payload, in: db)
        }
    }

    static func enqueue(
        table: String,
        op: String,
        payload: [String: Any],
        in db: Database
    ) throws {
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw MutationQueueError.invalidPayload
        }
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO mutation_queue
                    (table_name, op, payload, created_at, user_id, attempt_count)
                VALUES (?, ?, ?, ?, ?, 0)
                """,
            arguments: [
                table,
                op,
                payloadString,
                createdAt,
                authManager.currentUserId
            ]
        )
    }

    /// Commits local changes and their outbound mutations in one SQLite transaction.
    @discardableResult
    static func performAtomically<T: Sendable>(
        mutations: [LocalMutation],
        changes: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        let result = try await AppDatabase.shared.dbPool.write { db in
            let result = try changes(db)
            for mutation in mutations {
                try enqueue(
                    table: mutation.table,
                    op: mutation.op,
                    payload: mutation.payload,
                    in: db
                )
            }
            return result
        }
        SyncService.flushInBackground()
        return result
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
        let userId = authManager.currentUserId
            ?? UserDefaults.standard.string(forKey: "shift.cachedUserId")
        return try await AppDatabase.shared.dbPool.read { db in
            if let userId {
                return try MutationQueueRow.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM mutation_queue
                        WHERE (user_id = ? OR user_id IS NULL)
                        ORDER BY id ASC
                        """,
                    arguments: [userId]
                )
            }
            return []
        }
    }

    static func markFailure(rowId: Int64, message: String, attemptCount: Int) async throws {
        let cappedAttempt = min(attemptCount, 8)
        let delay = min(pow(2, Double(cappedAttempt)) * 15, 3_600)
        let nextAttempt = Date().addingTimeInterval(delay)
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE mutation_queue
                    SET attempt_count = ?, last_error = ?, next_attempt_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    attemptCount,
                    String(message.prefix(1_000)),
                    ISO8601DateFormatter.shared.string(from: nextAttempt),
                    rowId
                ]
            )
        }
    }

    static func clear(for userId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM mutation_queue WHERE user_id = ? OR user_id IS NULL",
                arguments: [userId]
            )
        }
    }

    static func nextRetryDate() async throws -> Date? {
        let userId = authManager.currentUserId
            ?? UserDefaults.standard.string(forKey: "shift.cachedUserId")
        guard let userId else { return nil }
        return try await AppDatabase.shared.dbPool.read { db in
            let value = try String.fetchOne(
                db,
                sql: """
                    SELECT MIN(next_attempt_at) FROM mutation_queue
                    WHERE (user_id = ? OR user_id IS NULL)
                      AND next_attempt_at IS NOT NULL
                    """,
                arguments: [userId]
            )
            guard let value else { return nil }
            return ISO8601DateFormatter.shared.date(from: value)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: value)
        }
    }

    /// Returns the set of record IDs that have any pending mutation in the queue.
    /// Used by pullUserData to avoid overwriting local changes with stale remote data.
    static func pendingMutationIds() async throws -> Set<String> {
        let rows = try await readPending()
        var ids = Set<String>()
        for row in rows {
            guard let data = row.payload.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = dict["id"] as? String else { continue }
            ids.insert(id)
        }
        return ids
    }
}

enum MutationQueueError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        "The local change could not be encoded for syncing."
    }
}
