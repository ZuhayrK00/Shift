import Foundation
import SwiftUI

/// Observable state for the active workout on Watch.
@Observable
final class WatchWorkoutState {
    var sessionId: String?
    var sessionName: String = "Workout"
    var planId: String?
    var startedAt: Date?
    var exercises: [WatchSessionExercise] = []
    var isActive: Bool { sessionId != nil }

    // Per-exercise logged set counts (tracked locally on Watch)
    var localSetCounts: [String: Int] = [:]

    // Per-exercise logged set details
    var loggedSetDetails: [String: [LoggedSetDetail]] = [:]

    struct LoggedSetDetail {
        var weight: Double?
        var reps: Int
    }

    func start(sessionId: String, name: String, planId: String? = nil, startedAt: Date, exercises: [WatchSessionExercise] = []) {
        self.sessionId = sessionId
        self.sessionName = name
        self.planId = planId
        self.startedAt = startedAt
        self.exercises = exercises
        self.localSetCounts = [:]
        self.loggedSetDetails = [:]
        for ex in exercises {
            localSetCounts[ex.exerciseId] = ex.completedSets
        }
    }

    func loggedSet(for exerciseId: String, weight: Double?, reps: Int) {
        localSetCounts[exerciseId, default: 0] += 1
        loggedSetDetails[exerciseId, default: []].append(LoggedSetDetail(weight: weight, reps: reps))
        if let idx = exercises.firstIndex(where: { $0.exerciseId == exerciseId }) {
            exercises[idx].completedSets = localSetCounts[exerciseId] ?? exercises[idx].completedSets
        }
    }

    func addExercise(_ exercise: WatchSessionExercise) {
        exercises.append(exercise)
        localSetCounts[exercise.exerciseId] = 0
    }

    func syncExercises(from active: WatchActiveSession) {
        for ex in active.exercises {
            if !exercises.contains(where: { $0.exerciseId == ex.exerciseId }) {
                exercises.append(ex)
                if localSetCounts[ex.exerciseId] == nil {
                    localSetCounts[ex.exerciseId] = ex.completedSets
                }
            }
        }
    }

    func clear() {
        sessionId = nil
        sessionName = "Workout"
        planId = nil
        startedAt = nil
        exercises = []
        localSetCounts = [:]
        loggedSetDetails = [:]
    }

    var elapsedText: String {
        guard let start = startedAt else { return "0:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let mins = (elapsed % 3600) / 60
        let secs = elapsed % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
