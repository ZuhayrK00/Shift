import Foundation
@preconcurrency import GRDB

struct ExerciseGoal: Identifiable, Hashable, Codable {
    var id: String
    var userId: String
    var exerciseId: String
    var targetWeightIncrease: Double
    var baselineWeight: Double
    var deadline: Date
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date

    // MARK: Codable (Supabase JSON — dates as ISO 8601 strings)

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case targetWeightIncrease = "target_weight_increase"
        case baselineWeight = "baseline_weight"
        case deadline
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    init(id: String, userId: String, exerciseId: String,
         targetWeightIncrease: Double, baselineWeight: Double,
         deadline: Date, isCompleted: Bool = false,
         completedAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.targetWeightIncrease = targetWeightIncrease
        self.baselineWeight = baselineWeight
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        targetWeightIncrease = try container.decode(Double.self, forKey: .targetWeightIncrease)
        baselineWeight = try container.decode(Double.self, forKey: .baselineWeight)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)

        let deadlineString = try container.decode(String.self, forKey: .deadline)
        deadline = ISO8601DateFormatter.shared.date(from: deadlineString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: deadlineString)
            ?? Date()

        if let completedAtString = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = ISO8601DateFormatter.shared.date(from: completedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: completedAtString)
        } else {
            completedAt = nil
        }

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(exerciseId, forKey: .exerciseId)
        try container.encode(targetWeightIncrease, forKey: .targetWeightIncrease)
        try container.encode(baselineWeight, forKey: .baselineWeight)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(ISO8601DateFormatter.shared.string(from: deadline), forKey: .deadline)
        try container.encode(ISO8601DateFormatter.shared.string(from: createdAt), forKey: .createdAt)
        if let completedAt {
            try container.encode(ISO8601DateFormatter.shared.string(from: completedAt), forKey: .completedAt)
        }
    }

    /// Target weight the user is aiming for.
    var targetWeight: Double { baselineWeight + targetWeightIncrease }

    /// Days remaining until the deadline. Negative if overdue.
    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: deadline)).day ?? 0
    }
}

// MARK: - GRDB conformance

extension ExerciseGoal: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        exerciseId = row["exercise_id"]
        targetWeightIncrease = row["target_weight_increase"]
        baselineWeight = row["baseline_weight"]
        isCompleted = (row["is_completed"] as Int) != 0

        if let deadlineString: String = row["deadline"] {
            deadline = ISO8601DateFormatter.shared.date(from: deadlineString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: deadlineString)
                ?? Date()
        } else {
            deadline = Date()
        }

        if let completedAtString: String = row["completed_at"] {
            completedAt = ISO8601DateFormatter.shared.date(from: completedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: completedAtString)
        } else {
            completedAt = nil
        }

        if let createdAtString: String = row["created_at"] {
            createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
                ?? Date()
        } else {
            createdAt = Date()
        }
    }
}

extension ExerciseGoal: PersistableRecord {
    static var databaseTableName: String { "exercise_goals" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["exercise_id"] = exerciseId
        container["target_weight_increase"] = targetWeightIncrease
        container["baseline_weight"] = baselineWeight
        container["deadline"] = ISO8601DateFormatter.shared.string(from: deadline)
        container["is_completed"] = isCompleted ? 1 : 0
        container["completed_at"] = completedAt.map { ISO8601DateFormatter.shared.string(from: $0) }
        container["created_at"] = ISO8601DateFormatter.shared.string(from: createdAt)
    }
}

extension ExerciseGoal: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
