import Foundation

struct ExerciseMatchingService {

    private static let noise: Set<String> = [
        "with", "the", "a", "an", "on", "of", "full", "range", "motion"
    ]

    /// Matches an exercise name string against the provided exercise list using
    /// exact name matching first, then keyword scoring with plural handling.
    /// Marks matched exercises in `usedIds` to avoid duplicates.
    static func match(
        _ name: String,
        against exercises: [Exercise],
        usedIds: inout Set<String>
    ) -> Exercise? {
        let searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Exact name match
        if let match = exercises.first(where: { $0.name.lowercased() == searchName && !usedIds.contains($0.id) }) {
            usedIds.insert(match.id)
            return match
        }

        // 2. Keyword scoring
        let keywords = searchName
            .split(separator: " ")
            .map(String.init)
            .filter { !noise.contains($0) }

        guard !keywords.isEmpty else { return nil }

        var bestMatch: Exercise?
        var bestScore = 0

        for exercise in exercises where !usedIds.contains(exercise.id) {
            let exerciseName = exercise.name.lowercased()
            var score = 0
            for keyword in keywords {
                if exerciseName.contains(keyword) {
                    score += 1
                } else if keyword.hasSuffix("s") && exerciseName.contains(String(keyword.dropLast())) {
                    score += 1
                } else if exerciseName.contains(keyword + "s") {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestMatch = exercise
            }
        }

        if let match = bestMatch, bestScore >= max(1, keywords.count / 2) {
            usedIds.insert(match.id)
            return match
        }
        return nil
    }
}
