import Foundation
@preconcurrency import GRDB

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

    static func insert(_ entry: WeightEntry) async throws {
        guard entry.weight > 0 && entry.weight < 1000 else { throw WeightEntryError.invalidWeight }
        guard entry.recordedAt <= Date().addingTimeInterval(60) else { throw WeightEntryError.futureDate }

        let mutation = LocalMutation(
            table: "weight_entries",
            op: "insert",
            payload: entryPayload(entry)
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try entry.insert(db)
        }
        Task { await WidgetDataService.updateSnapshot() }
    }

    static func delete(_ id: String) async throws {
        let userId = try authManager.requireUserId()
        let mutation = LocalMutation(table: "weight_entries", op: "delete", payload: ["id": id])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try db.execute(
                sql: "DELETE FROM weight_entries WHERE id = ? AND user_id = ?",
                arguments: [id, userId]
            )
        }
        Task { await WidgetDataService.updateSnapshot() }
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
