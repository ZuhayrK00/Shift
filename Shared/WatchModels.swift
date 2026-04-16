import Foundation

// MARK: - Lightweight Codable models for iPhone ↔ Watch transfer
// These are free of GRDB/Supabase dependencies so both targets can use them.

struct WatchExercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var equipment: String?

    var displayName: String {
        equipment.map { "\(name): \($0)" } ?? name
    }
}

struct WatchPlanExercise: Codable, Identifiable, Hashable {
    var id: String
    var exerciseId: String
    var exerciseName: String
    var equipment: String?
    var targetSets: Int
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetWeight: Double?
    var restSeconds: Int?
    var position: Int

    var displayName: String {
        equipment.map { "\(exerciseName): \($0)" } ?? exerciseName
    }

    var repsLabel: String {
        if let min = targetRepsMin, let max = targetRepsMax, min != max {
            return "\(min)-\(max)"
        } else if let min = targetRepsMin {
            return "\(min)"
        }
        return "—"
    }
}

struct WatchPlan: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var exercises: [WatchPlanExercise]
}

struct WatchSettings: Codable {
    var weightUnit: String
    var defaultWeightIncrement: Double
    var restTimerEnabled: Bool
    var restTimerDurationSeconds: Int
}

struct WatchActiveSession: Codable, Equatable {
    var sessionId: String
    var planId: String?
    var name: String
    var startedAt: Date
    var exercises: [WatchSessionExercise]
}

struct WatchSessionExercise: Codable, Identifiable, Hashable {
    var exerciseId: String
    var exerciseName: String
    var equipment: String?
    var completedSets: Int
    var totalSets: Int

    var id: String { exerciseId }

    var displayName: String {
        equipment.map { "\(exerciseName): \($0)" } ?? exerciseName
    }
}

struct WatchLoggedSet: Codable, Identifiable {
    var id: String
    var sessionId: String
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weight: Double?
    var setType: String // "normal", "warmup", "drop", "failure"
    var completedAt: Date
}

struct WatchCompletedSession: Codable {
    var sessionId: String
    var name: String
    var startedAt: Date
    var endedAt: Date
    var exerciseCount: Int
    var setCount: Int
}

// MARK: - Context payload that iPhone sends to Watch

struct WatchContext: Codable {
    var plans: [WatchPlan]
    var recentExercises: [WatchExercise]
    var activeSession: WatchActiveSession?
    var lastCompletedSession: WatchCompletedSession?
    var settings: WatchSettings
    var userId: String
    var snapshot: WatchSnapshotData

    struct WatchSnapshotData: Codable {
        var workoutsThisWeek: Int
        var weeklyGoal: Int?
        var stepsToday: Int
        var stepGoal: Int?
        var workedOutToday: Bool
        var currentStreak: Int
        var streakUnit: String
    }
}

// MARK: - Message keys

enum WatchAction: String, Codable {
    case startSession
    case startSessionFromPlan
    case finishSession
    case logSet
    case addExercise
    case deleteSession
    case requestSync
}
