import Foundation
@preconcurrency import GRDB

// MARK: - WeightEntry

struct WeightEntry: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var userId: String
    var weight: Double      // stored in user's display unit
    var unit: String        // "kg" or "lbs"
    var source: String      // "manual" or "healthkit"
    var recordedAt: Date
    var createdAt: Date

    // MARK: Codable (Supabase JSON)

    enum CodingKeys: String, CodingKey {
        case id, weight, unit, source
        case userId = "user_id"
        case recordedAt = "recorded_at"
        case createdAt = "created_at"
    }

    init(id: String, userId: String, weight: Double, unit: String = "kg",
         source: String = "manual", recordedAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.weight = weight
        self.unit = unit
        self.source = source
        self.recordedAt = recordedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        weight = try container.decode(Double.self, forKey: .weight)
        unit = (try? container.decode(String.self, forKey: .unit)) ?? "kg"
        source = (try? container.decode(String.self, forKey: .source)) ?? "manual"

        let recordedAtStr = try container.decode(String.self, forKey: .recordedAt)
        recordedAt = ISO8601DateFormatter.shared.date(from: recordedAtStr)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: recordedAtStr)
            ?? Date()

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter.shared.date(from: createdAtStr)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtStr)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(weight, forKey: .weight)
        try container.encode(unit, forKey: .unit)
        try container.encode(source, forKey: .source)
        try container.encode(ISO8601DateFormatter.shared.string(from: recordedAt), forKey: .recordedAt)
        try container.encode(ISO8601DateFormatter.shared.string(from: createdAt), forKey: .createdAt)
    }
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
