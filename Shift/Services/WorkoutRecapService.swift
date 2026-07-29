import Foundation
@preconcurrency import GRDB

struct WorkoutRecap: Equatable, Sendable {
    var personalBestExerciseIDs: Set<String>
    var previousVolume: Double?
    var volumeChangePercent: Int?
}

enum WorkoutRecapService {
    static func build(
        session: WorkoutSession,
        sets: [SessionSet]
    ) async throws -> WorkoutRecap {
        let exerciseIDs = Array(Set(sets.map(\.exerciseId)))
        let previousMax = try await previousMaxWeights(
            userID: session.userId,
            before: session.startedAt,
            exerciseIDs: exerciseIDs
        )
        let currentMax = Dictionary(grouping: sets.filter(\.isCompleted), by: \.exerciseId)
            .mapValues { $0.compactMap(\.weight).max() ?? 0 }
        let personalBestIDs: Set<String> = Set(currentMax.compactMap { entry -> String? in
            let (exerciseID, weight) = entry
            guard weight > 0 else { return nil }
            let oldBest = previousMax[exerciseID] ?? 0
            return weight > oldBest ? exerciseID : nil
        })

        let previousSession = try await SessionRepository
            .findCompleted(userId: session.userId)
            .filter {
                $0.id != session.id
                    && $0.startedAt < session.startedAt
                    && (session.planId == nil || $0.planId == session.planId)
            }
            .max(by: { $0.startedAt < $1.startedAt })
        let previousSets = if let previousSession {
            try await SessionSetRepository.findForSession(previousSession.id)
        } else {
            [SessionSet]()
        }
        let currentVolume = volume(of: sets)
        let oldVolume = volume(of: previousSets)
        let change: Int? = oldVolume > 0
            ? Int((((currentVolume - oldVolume) / oldVolume) * 100).rounded())
            : nil

        return WorkoutRecap(
            personalBestExerciseIDs: personalBestIDs,
            previousVolume: oldVolume > 0 ? oldVolume : nil,
            volumeChangePercent: change
        )
    }

    private static func volume(of sets: [SessionSet]) -> Double {
        sets.filter(\.isCompleted).reduce(0) {
            $0 + (($1.weight ?? 0) * Double($1.reps))
        }
    }

    private static func previousMaxWeights(
        userID: String,
        before date: Date,
        exerciseIDs: [String]
    ) async throws -> [String: Double] {
        guard !exerciseIDs.isEmpty else { return [:] }
        return try await AppDatabase.shared.dbPool.read { db in
            let placeholders = exerciseIDs.map { _ in "?" }.joined(separator: ",")
            let arguments = [
                userID,
                ISO8601DateFormatter.shared.string(from: date)
            ] + exerciseIDs
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT ss.exercise_id, MAX(ss.weight) AS max_weight
                    FROM session_sets ss
                    JOIN workout_sessions ws ON ws.id = ss.session_id
                    WHERE ws.user_id = ?
                      AND ws.ended_at IS NOT NULL
                      AND ws.started_at < ?
                      AND ss.is_completed = 1
                      AND ss.weight IS NOT NULL
                      AND ss.exercise_id IN (\(placeholders))
                    GROUP BY ss.exercise_id
                    """,
                arguments: StatementArguments(arguments)
            )
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let id: String = row["exercise_id"],
                      let weight: Double = row["max_weight"] else { return nil }
                return (id, weight)
            })
        }
    }
}
