import Foundation

struct WeightEntryService {

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    static func insert(_ entry: WeightEntry) async throws {
        try await WeightEntryRepository.insert(entry)
        try await enqueue(table: "weight_entries", op: "insert", payload: entryPayload(entry))
    }

    static func delete(_ id: String) async throws {
        try await WeightEntryRepository.delete(id)
        try await enqueue(table: "weight_entries", op: "delete", payload: ["id": id])
    }

    // MARK: - Private

    private static func entryPayload(_ entry: WeightEntry) -> [String: Any] {
        [
            "id": entry.id,
            "user_id": entry.userId,
            "weight": entry.weight,
            "unit": entry.unit,
            "source": entry.source,
            "recorded_at": ISO8601DateFormatter.shared.string(from: entry.recordedAt),
            "created_at": ISO8601DateFormatter.shared.string(from: entry.createdAt)
        ]
    }
}
