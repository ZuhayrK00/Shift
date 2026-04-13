import Foundation
@preconcurrency import GRDB

struct PlanExercise: Identifiable, Hashable, Codable {
    var id: String
    var planId: String
    var exerciseId: String
    var position: Int
    var targetSets: Int
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetWeight: Double?
    var restSeconds: Int?
    var groupId: String?

    // MARK: - Computed helpers

    /// "8-10" when both min and max differ, "8" when they are equal or only one is present, nil if neither.
    func repRangeText() -> String? {
        switch (targetRepsMin, targetRepsMax) {
        case let (.some(min), .some(max)) where min != max:
            return "\(min)-\(max)"
        case let (.some(min), .some):
            return "\(min)"
        case let (.some(min), .none):
            return "\(min)"
        case let (.none, .some(max)):
            return "\(max)"
        default:
            return nil
        }
    }

    /// "3 sets × 8-10 reps" style label shown in plan detail screens.
    func subtitle() -> String {
        let setsLabel = pluralise(targetSets, "set")
        if let range = repRangeText() {
            return "\(setsLabel) × \(range) reps"
        }
        return setsLabel
    }

    /// Preferred starting rep count when logging a new set for this plan exercise.
    var defaultReps: Int { targetRepsMax ?? targetRepsMin ?? 0 }

    // MARK: Codable (Supabase JSON)

    enum CodingKeys: String, CodingKey {
        case id, position
        case planId = "plan_id"
        case exerciseId = "exercise_id"
        case targetSets = "target_sets"
        case targetRepsMin = "target_reps_min"
        case targetRepsMax = "target_reps_max"
        case targetWeight = "target_weight"
        case restSeconds = "rest_seconds"
        case groupId = "group_id"
    }
}

// MARK: - GRDB conformance

extension PlanExercise: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        planId = row["plan_id"]
        exerciseId = row["exercise_id"]
        position = row["position"] ?? 0
        targetSets = row["target_sets"] ?? 0
        targetRepsMin = row["target_reps_min"]
        targetRepsMax = row["target_reps_max"]
        targetWeight = row["target_weight"]
        restSeconds = row["rest_seconds"]
        groupId = row["group_id"]
    }
}

extension PlanExercise: PersistableRecord {
    static var databaseTableName: String { "plan_exercises" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["plan_id"] = planId
        container["exercise_id"] = exerciseId
        container["position"] = position
        container["target_sets"] = targetSets
        container["target_reps_min"] = targetRepsMin
        container["target_reps_max"] = targetRepsMax
        container["target_weight"] = targetWeight
        container["rest_seconds"] = restSeconds
        container["group_id"] = groupId
    }
}

extension PlanExercise: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
