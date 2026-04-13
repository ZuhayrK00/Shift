import Foundation
@preconcurrency import GRDB

struct WorkoutSession: Identifiable, Hashable, Codable {
    var id: String
    var userId: String
    var planId: String?
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String?

    var isInProgress: Bool { endedAt == nil }

    // MARK: Codable (Supabase JSON — dates as ISO 8601 strings)

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case userId = "user_id"
        case planId = "plan_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    init(id: String, userId: String, planId: String? = nil, name: String,
         startedAt: Date, endedAt: Date? = nil, notes: String? = nil) {
        self.id = id
        self.userId = userId
        self.planId = planId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        planId = try container.decodeIfPresent(String.self, forKey: .planId)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        let startedAtString = try container.decode(String.self, forKey: .startedAt)
        startedAt = ISO8601DateFormatter.shared.date(from: startedAtString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: startedAtString)
            ?? Date()

        if let endedAtString = try container.decodeIfPresent(String.self, forKey: .endedAt) {
            endedAt = ISO8601DateFormatter.shared.date(from: endedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: endedAtString)
        } else {
            endedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(planId, forKey: .planId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(ISO8601DateFormatter.shared.string(from: startedAt), forKey: .startedAt)
        if let endedAt {
            try container.encode(ISO8601DateFormatter.shared.string(from: endedAt), forKey: .endedAt)
        }
    }
}

// MARK: - GRDB conformance (dates stored as ISO 8601 strings)

extension WorkoutSession: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        planId = row["plan_id"]
        name = row["name"]
        notes = row["notes"]

        if let startedAtString: String = row["started_at"] {
            startedAt = ISO8601DateFormatter.shared.date(from: startedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: startedAtString)
                ?? Date()
        } else {
            startedAt = Date()
        }

        if let endedAtString: String = row["ended_at"] {
            endedAt = ISO8601DateFormatter.shared.date(from: endedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: endedAtString)
        } else {
            endedAt = nil
        }
    }
}

extension WorkoutSession: PersistableRecord {
    static var databaseTableName: String { "workout_sessions" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["plan_id"] = planId
        container["name"] = name
        container["started_at"] = ISO8601DateFormatter.shared.string(from: startedAt)
        container["ended_at"] = endedAt.map { ISO8601DateFormatter.shared.string(from: $0) }
        container["notes"] = notes
    }
}

extension WorkoutSession: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
