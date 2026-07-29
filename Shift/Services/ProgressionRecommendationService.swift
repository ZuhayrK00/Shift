import Foundation

struct ProgressionRecommendation: Equatable, Sendable {
    var exerciseID: String
    var weight: Double
    var explanation: String
    var isIncrease: Bool
}

enum ProgressionRecommendationService {
    static func recommendations(
        latestSets: [String: [SessionSet]],
        targets: [String: (repsMin: Int, repsMax: Int)],
        increment: Double
    ) -> [String: ProgressionRecommendation] {
        var result: [String: ProgressionRecommendation] = [:]
        for (exerciseID, sets) in latestSets {
            let workingSets = sets.filter {
                $0.setType == .normal && $0.isCompleted && ($0.weight ?? 0) > 0
            }
            guard !workingSets.isEmpty,
                  let lastWeight = workingSets.compactMap(\.weight).max(),
                  let target = targets[exerciseID] else { continue }

            let minimumReps = workingSets.map(\.reps).min() ?? 0
            let rpes = workingSets.compactMap(\.rpe)
            let averageRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
            let comfortablyCompleted = minimumReps >= target.repsMax
                && (averageRPE == nil || averageRPE! <= 8)
            let validIncrement = increment.isFinite ? max(0, increment) : 0
            let shouldIncrease = comfortablyCompleted && validIncrement > 0
            let suggestedWeight = shouldIncrease ? lastWeight + validIncrement : lastWeight

            result[exerciseID] = ProgressionRecommendation(
                exerciseID: exerciseID,
                weight: suggestedWeight,
                explanation: shouldIncrease
                    ? "You completed the top of the rep range last time."
                    : "Start with the weight you used most recently.",
                isIncrease: shouldIncrease
            )
        }
        return result
    }
}
