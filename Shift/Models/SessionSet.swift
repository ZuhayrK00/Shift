import Foundation
@preconcurrency import GRDB

// MARK: - SetType

enum SetType: String, Codable, CaseIterable {
    case normal
    case warmup
    case drop
    case failure
}

// MARK: - SessionSet

struct SessionSet: Identifiable, Hashable, Codable {
    var id: String
    var sessionId: String
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weight: Double?
    var rpe: Double?
    var isCompleted: Bool
    var completedAt: Date?
    var setType: SetType
    var groupId: String?

    /// Badge label shown on the set row: "W", "D", "F" for special types, or the set number for normal.
    var badgeLabel: String {
        switch setType {
        case .warmup: return "W"
        case .drop: return "D"
        case .failure: return "F"
        case .normal: return "\(setNumber)"
        }
    }

    // MARK: Codable (Supabase JSON)

    enum CodingKeys: String, CodingKey {
        case id, reps, weight, rpe
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case setNumber = "set_number"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case setType = "set_type"
        case groupId = "group_id"
    }

    init(id: String, sessionId: String, exerciseId: String, setNumber: Int,
         reps: Int = 0, weight: Double? = nil, rpe: Double? = nil,
         isCompleted: Bool = false, completedAt: Date? = nil,
         setType: SetType = .normal, groupId: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.setType = setType
        self.groupId = groupId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        reps = try container.decode(Int.self, forKey: .reps)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        setType = (try? container.decode(SetType.self, forKey: .setType)) ?? .normal

        if let completedAtString = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = ISO8601DateFormatter.shared.date(from: completedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: completedAtString)
        } else {
            completedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(exerciseId, forKey: .exerciseId)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encode(reps, forKey: .reps)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encode(setType, forKey: .setType)
        if let completedAt {
            try container.encode(ISO8601DateFormatter.shared.string(from: completedAt), forKey: .completedAt)
        }
    }
}

// MARK: - GRDB conformance (isCompleted as 0/1 Int, dates as ISO strings)

extension SessionSet: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        sessionId = row["session_id"]
        exerciseId = row["exercise_id"]
        setNumber = row["set_number"]
        reps = row["reps"] ?? 0
        weight = row["weight"]
        rpe = row["rpe"]
        groupId = row["group_id"]

        let isCompletedInt: Int = row["is_completed"] ?? 0
        isCompleted = isCompletedInt != 0

        let setTypeRaw: String = row["set_type"] ?? "normal"
        setType = SetType(rawValue: setTypeRaw) ?? .normal

        if let completedAtString: String = row["completed_at"] {
            completedAt = ISO8601DateFormatter.shared.date(from: completedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: completedAtString)
        } else {
            completedAt = nil
        }
    }
}

extension SessionSet: PersistableRecord {
    static var databaseTableName: String { "session_sets" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["session_id"] = sessionId
        container["exercise_id"] = exerciseId
        container["set_number"] = setNumber
        container["reps"] = reps
        container["weight"] = weight
        container["rpe"] = rpe
        container["is_completed"] = isCompleted ? 1 : 0
        container["completed_at"] = completedAt.map { ISO8601DateFormatter.shared.string(from: $0) }
        container["set_type"] = setType.rawValue
        container["group_id"] = groupId
    }
}

extension SessionSet: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
