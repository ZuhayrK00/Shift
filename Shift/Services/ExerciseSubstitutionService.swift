import Foundation

enum ExerciseSubstitutionService {
    static func suggestions(
        for exercise: Exercise,
        from catalogue: [Exercise],
        excluding excludedIDs: Set<String>,
        limit: Int = 12
    ) -> [Exercise] {
        catalogue
            .filter { $0.id != exercise.id && !excludedIDs.contains($0.id) }
            .map { candidate in
                (exercise: candidate, score: similarityScore(candidate, to: exercise))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.exercise.name < $1.exercise.name
            }
            .prefix(limit)
            .map(\.exercise)
    }

    private static func similarityScore(_ candidate: Exercise, to original: Exercise) -> Int {
        var score = 0
        if candidate.primaryMuscleId == original.primaryMuscleId { score += 8 }
        if normalized(candidate.mechanic) == normalized(original.mechanic) { score += 3 }
        if normalized(candidate.force) == normalized(original.force) { score += 2 }
        if normalized(candidate.equipment) == normalized(original.equipment) { score += 2 }
        if normalized(candidate.level) == normalized(original.level) { score += 1 }
        if normalized(candidate.bodyPart) == normalized(original.bodyPart) { score += 1 }
        return score
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
