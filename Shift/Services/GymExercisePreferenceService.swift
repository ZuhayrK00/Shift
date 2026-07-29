import Foundation

/// Keeps unrestricted plan generation centred on equipment that people can
/// reasonably expect to find in a modern commercial gym.
enum GymExercisePreferenceService {
    static func sorted(
        _ exercises: [Exercise],
        familiarExerciseIDs: Set<String> = []
    ) -> [Exercise] {
        exercises.sorted { lhs, rhs in
            let lhsEquipment = equipmentPriority(lhs.equipment)
            let rhsEquipment = equipmentPriority(rhs.equipment)
            if lhsEquipment != rhsEquipment { return lhsEquipment < rhsEquipment }

            let lhsFamiliar = familiarExerciseIDs.contains(lhs.id)
            let rhsFamiliar = familiarExerciseIDs.contains(rhs.id)
            if lhsFamiliar != rhsFamiliar { return lhsFamiliar }

            let lhsCompound = lhs.mechanic?.lowercased() == "compound"
            let rhsCompound = rhs.mechanic?.lowercased() == "compound"
            if lhsCompound != rhsCompound { return lhsCompound }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func equipmentPriority(_ equipment: String?) -> Int {
        let value = equipment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if containsAny(
            value,
            [
                "barbell", "dumbbell", "cable", "machine", "smith",
                "e-z curl", "ez curl", "trap bar", "landmine"
            ]
        ) {
            return 0
        }
        if containsAny(
            value,
            [
                "kettlebell", "band", "sled", "plate", "medicine ball",
                "rope", "weighted"
            ]
        ) {
            return 1
        }
        if containsAny(value, ["body only", "bodyweight", "body weight", "no equipment"]) {
            return 3
        }
        return 2
    }

    private static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }
}
