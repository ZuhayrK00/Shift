import Foundation

struct ExerciseSubstitution: Identifiable {
    let exercise: Exercise
    let score: Int
    let reasons: [String]

    var id: String { exercise.id }
    var explanation: String {
        reasons.prefix(2).joined(separator: " · ")
    }
}

enum ExerciseSubstitutionService {
    static func rankedSuggestions(
        for exercise: Exercise,
        from catalogue: [Exercise],
        excluding excludedIDs: Set<String>,
        limit: Int = 12
    ) -> [ExerciseSubstitution] {
        catalogue
            .filter { $0.id != exercise.id && !excludedIDs.contains($0.id) }
            .map { candidate in
                let match = similarity(candidate, to: exercise)
                return ExerciseSubstitution(
                    exercise: candidate,
                    score: match.score,
                    reasons: match.reasons
                )
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name)
                    == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    static func suggestions(
        for exercise: Exercise,
        from catalogue: [Exercise],
        excluding excludedIDs: Set<String>,
        limit: Int = 12
    ) -> [Exercise] {
        rankedSuggestions(
            for: exercise,
            from: catalogue,
            excluding: excludedIDs,
            limit: limit
        ).map(\.exercise)
    }

    private static func similarity(
        _ candidate: Exercise,
        to original: Exercise
    ) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []
        if candidate.primaryMuscleId == original.primaryMuscleId {
            score += 10
            reasons.append("Same target muscle")
        }
        if equalNonEmpty(candidate.mechanic, original.mechanic) {
            score += 4
            reasons.append("Similar movement")
        }
        if equalNonEmpty(candidate.force, original.force) {
            score += 3
            reasons.append("Same force pattern")
        }
        if equalNonEmpty(candidate.equipment, original.equipment) {
            score += 3
            reasons.append("Same equipment")
        } else if isCommonGymEquipment(candidate.equipment) {
            score += 1
            reasons.append("Common gym equipment")
        }
        if equalNonEmpty(candidate.level, original.level) {
            score += 2
            reasons.append("Similar difficulty")
        }
        if equalNonEmpty(candidate.bodyPart, original.bodyPart) {
            score += 2
        }
        return (score, reasons)
    }

    private static func equalNonEmpty(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        return !left.isEmpty && left == normalized(rhs)
    }

    private static func isCommonGymEquipment(_ value: String?) -> Bool {
        let common = [
            "barbell", "dumbbell", "cable", "machine", "smith machine",
            "ez curl bar", "kettlebell"
        ]
        let equipment = normalized(value)
        return common.contains { equipment.contains($0) }
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
