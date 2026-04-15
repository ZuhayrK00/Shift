import Foundation

enum WeightEntryError: LocalizedError {
    case invalidWeight
    case futureDate

    var errorDescription: String? {
        switch self {
        case .invalidWeight: return "Weight must be a positive number under 1000 kg."
        case .futureDate: return "Recorded date cannot be in the future."
        }
    }
}

struct WeightEntryService {

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    static func insert(_ entry: WeightEntry) async throws {
        guard entry.weight > 0 && entry.weight < 1000 else { throw WeightEntryError.invalidWeight }
        guard entry.recordedAt <= Date().addingTimeInterval(60) else { throw WeightEntryError.futureDate }

        try await WeightEntryRepository.insert(entry)
        try await enqueue(table: "weight_entries", op: "insert", payload: entryPayload(entry))
        Task { await WidgetDataService.updateSnapshot() }
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
