import Foundation
import SwiftUI

/// Observable state for the active workout on Watch.
@Observable
final class WatchWorkoutState {
    var sessionId: String?
    var sessionName: String = "Workout"
    var startedAt: Date?
    var exercises: [WatchSessionExercise] = []
    var isActive: Bool { sessionId != nil }

    // Per-exercise logged set counts (tracked locally on Watch)
    var localSetCounts: [String: Int] = [:]

    func start(sessionId: String, name: String, startedAt: Date, exercises: [WatchSessionExercise] = []) {
        self.sessionId = sessionId
        self.sessionName = name
        self.startedAt = startedAt
        self.exercises = exercises
        self.localSetCounts = [:]
        for ex in exercises {
            localSetCounts[ex.exerciseId] = ex.completedSets
        }
    }

    func loggedSet(for exerciseId: String) {
        localSetCounts[exerciseId, default: 0] += 1
        if let idx = exercises.firstIndex(where: { $0.exerciseId == exerciseId }) {
            exercises[idx].completedSets = localSetCounts[exerciseId] ?? exercises[idx].completedSets
        }
    }

    func addExercise(_ exercise: WatchSessionExercise) {
        exercises.append(exercise)
        localSetCounts[exercise.exerciseId] = 0
    }

    func clear() {
        sessionId = nil
        sessionName = "Workout"
        startedAt = nil
        exercises = []
        localSetCounts = [:]
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
