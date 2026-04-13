import Foundation
@preconcurrency import GRDB

struct WorkoutPlan: Identifiable, Hashable, Codable {
    var id: String
    var userId: String
    var name: String
    var notes: String?
    var createdAt: Date

    // MARK: Codable (Supabase JSON)

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case userId = "user_id"
        case createdAt = "created_at"
    }

    init(id: String, userId: String, name: String, notes: String? = nil, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(ISO8601DateFormatter.shared.string(from: createdAt), forKey: .createdAt)
    }
}

// MARK: - GRDB conformance

extension WorkoutPlan: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        name = row["name"]
        notes = row["notes"]

        if let createdAtString: String = row["created_at"] {
            createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
                ?? Date()
        } else {
            createdAt = Date()
        }
    }
}

extension WorkoutPlan: PersistableRecord {
    static var databaseTableName: String { "workout_plans" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["name"] = name
        container["notes"] = notes
        container["created_at"] = ISO8601DateFormatter.shared.string(from: createdAt)
    }
}

extension WorkoutPlan: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
