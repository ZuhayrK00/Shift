import Foundation
import Supabase

// MARK: - SyncService

struct SyncService {

    private static let lastSyncedKey = "shift:last_synced_at"

    // MARK: - Queue flush

    /// Drains the local mutation queue into Supabase in FIFO order.
    /// Stops processing on the first failure so ordering is preserved.
    ///
    /// - Returns: A tuple of how many mutations were flushed vs. failed.
    @discardableResult
    static func flushQueue() async throws -> (flushed: Int, failed: Int) {
        let pending = try await MutationQueueRepository.readPending()
        var flushed = 0
        var failed  = 0

        for row in pending {
            do {
                guard let data = row.payload.data(using: .utf8),
                      let payloadDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    // Malformed row — remove it so it doesn't block the queue
                    try await MutationQueueRepository.delete(rowId: row.id)
                    flushed += 1
                    continue
                }

                switch row.op {
                case "insert":
                    try await executeInsert(table: row.tableName, payload: payloadDict)

                case "update":
                    // Extract the row id from the payload; the rest goes into the SET clause
                    guard let rowId = payloadDict["id"] as? String else {
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    var updatePayload = payloadDict
                    updatePayload.removeValue(forKey: "id")
                    try await executeUpdate(table: row.tableName, id: rowId, payload: updatePayload)

                case "delete":
                    guard let rowId = payloadDict["id"] as? String else {
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    try await executeDelete(table: row.tableName, id: rowId)

                default:
                    // Unknown op — remove to unblock
                    try await MutationQueueRepository.delete(rowId: row.id)
                    flushed += 1
                    continue
                }

                try await MutationQueueRepository.delete(rowId: row.id)
                flushed += 1

            } catch {
                failed += 1
                // Stop processing on error to preserve mutation ordering
                break
            }
        }

        return (flushed: flushed, failed: failed)
    }

    /// Fire-and-forget queue flush for non-critical background syncs.
    static func flushInBackground() {
        Task { try? await flushQueue() }
    }

    // MARK: - Reference data pull

    /// Refreshes muscle groups and built-in exercises from Supabase, then caches the
    /// user profile. Records the sync timestamp in UserDefaults on success.
    ///
    /// - Returns: Counts of upserted muscle groups and exercises.
    @discardableResult
    static func pullReferenceData() async throws -> (muscleGroups: Int, exercises: Int) {
        // Flush first so any pending writes are committed before we read back
        try? await flushQueue()

        // Muscle groups
        let mgResponse = try await supabase
            .from("muscle_groups")
            .select()
            .execute()

        let muscleGroups = (try? JSONDecoder().decode([MuscleGroup].self, from: mgResponse.data)) ?? []
        for mg in muscleGroups {
            try await MuscleGroupRepository.upsert(mg)
        }

        // Exercises
        let exResponse = try await supabase
            .from("exercises")
            .select()
            .eq("is_built_in", value: true)
            .execute()

        let decoder = JSONDecoder()
        let exercises = (try? decoder.decode([Exercise].self, from: exResponse.data)) ?? []
        try await ExerciseRepository.replaceBuiltIn(exercises)

        // Cache profile
        if let userId = authManager.currentUserId {
            _ = try? await ProfileService.fetchAndCacheProfile(userId)
        }

        // Record sync timestamp
        UserDefaults.standard.set(
            ISO8601DateFormatter.shared.string(from: Date()),
            forKey: lastSyncedKey
        )

        return (muscleGroups: muscleGroups.count, exercises: exercises.count)
    }

    // MARK: - Last synced

    static func getLastSyncedAt() -> Date? {
        guard let raw = UserDefaults.standard.string(forKey: lastSyncedKey) else { return nil }
        return ISO8601DateFormatter.shared.date(from: raw)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: raw)
    }

    // MARK: - Private Supabase helpers

    private static func executeInsert(table: String, payload: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonValue = try? JSONDecoder().decode(AnyJSON.self, from: jsonData) else {
            throw SyncError.encodingFailed
        }
        try await supabase
            .from(table)
            .insert(jsonValue)
            .execute()
    }

    private static func executeUpdate(table: String, id: String, payload: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonValue = try? JSONDecoder().decode(AnyJSON.self, from: jsonData) else {
            throw SyncError.encodingFailed
        }
        try await supabase
            .from(table)
            .update(jsonValue)
            .eq("id", value: id)
            .execute()
    }

    private static func executeDelete(table: String, id: String) async throws {
        try await supabase
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

// MARK: - SyncError

enum SyncError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode mutation payload for Supabase."
        }
    }
}
