import Foundation

enum ProgressionAction: String, Equatable, Sendable {
    case increase
    case hold
    case decrease
}

struct ProgressionRecommendation: Equatable, Sendable {
    var exerciseID: String
    var weight: Double
    var explanation: String
    var action: ProgressionAction

    var isIncrease: Bool { action == .increase }
}

enum ProgressionRecommendationService {
    static func recommendations(
        latestSets: [String: [SessionSet]],
        targets: [String: (repsMin: Int, repsMax: Int)],
        increment: Double,
        recentSessions: [String: [[SessionSet]]] = [:]
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
            let recentMisses = (recentSessions[exerciseID] ?? [])
                .prefix(2)
                .filter { sessionSets in
                    let working = sessionSets.filter {
                        $0.isCompleted && $0.setType == .normal
                    }
                    return !working.isEmpty
                        && (working.map(\.reps).min() ?? target.repsMin) < target.repsMin
                }
            let repeatedMiss = recentMisses.count >= 2
            let shouldDecrease = repeatedMiss && validIncrement > 0
            let action: ProgressionAction = shouldIncrease
                ? .increase
                : (shouldDecrease ? .decrease : .hold)
            let suggestedWeight: Double
            switch action {
            case .increase:
                suggestedWeight = lastWeight + validIncrement
            case .decrease:
                let deloaded = (lastWeight * 0.925 / validIncrement).rounded(.down) * validIncrement
                suggestedWeight = max(validIncrement, deloaded)
            case .hold:
                suggestedWeight = lastWeight
            }

            result[exerciseID] = ProgressionRecommendation(
                exerciseID: exerciseID,
                weight: suggestedWeight,
                explanation: {
                    switch action {
                    case .increase:
                        return "Top of the rep range completed with room to progress."
                    case .decrease:
                        return "The rep target was missed twice. A short reset should help you rebuild."
                    case .hold:
                        return "Keep this weight and build more reps before progressing."
                    }
                }(),
                action: action
            )
        }
        return result
    }

    static func recentSessionSets(
        exerciseIDs: [String],
        limit: Int = 3
    ) async -> [String: [[SessionSet]]] {
        var result: [String: [[SessionSet]]] = [:]
        for exerciseID in exerciseIDs {
            guard let history = try? await SessionSetRepository.findHistory(exerciseId: exerciseID)
            else { continue }
            var orderedSessionIDs: [String] = []
            var setsBySession: [String: [SessionSet]] = [:]
            for item in history {
                if setsBySession[item.set.sessionId] == nil {
                    orderedSessionIDs.append(item.set.sessionId)
                }
                setsBySession[item.set.sessionId, default: []].append(item.set)
            }
            result[exerciseID] = orderedSessionIDs.prefix(limit).compactMap {
                setsBySession[$0]
            }
        }
        return result
    }
}
