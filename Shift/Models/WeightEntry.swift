import Foundation
@preconcurrency import GRDB

// MARK: - WeightEntry

struct WeightEntry: Identifiable, Hashable, Sendable {
    var id: String
    var userId: String
    var weight: Double      // stored in user's display unit
    var unit: String        // "kg" or "lbs"
    var source: String      // "manual" or "healthkit"
    var recordedAt: Date
    var createdAt: Date
}

// MARK: - GRDB conformances

extension WeightEntry: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        weight = row["weight"]
        unit = row["unit"] ?? "kg"
        source = row["source"] ?? "manual"

        let recordedAtStr: String = row["recorded_at"] ?? ""
        recordedAt = ISO8601DateFormatter.shared.date(from: recordedAtStr)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: recordedAtStr)
            ?? Date()

        let createdAtStr: String = row["created_at"] ?? ""
        createdAt = ISO8601DateFormatter.shared.date(from: createdAtStr)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtStr)
            ?? Date()
    }
}

extension WeightEntry: PersistableRecord {
    static let databaseTableName = "weight_entries"

    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["weight"] = weight
        container["unit"] = unit
        container["source"] = source
        container["recorded_at"] = ISO8601DateFormatter.shared.string(from: recordedAt)
        container["created_at"] = ISO8601DateFormatter.shared.string(from: createdAt)
    }
}

extension WeightEntry: TableRecord {}
