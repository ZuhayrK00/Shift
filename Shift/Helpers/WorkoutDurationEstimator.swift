import Foundation

// MARK: - WorkoutDurationEstimator

/// Estimates how long a workout will take based on exercises, sets, reps, and rest time.
///
/// Assumptions:
/// - Each rep takes ~3 seconds (eccentric + concentric + pause)
/// - Transition time between exercises: 60 seconds (walk to station, adjust weight, etc.)
/// - Warm-up: 5 minutes for the overall session
///
/// Usage:
///     let minutes = WorkoutDurationEstimator.estimate(exercises: planExercises, defaultRestSeconds: 90)
///     let label = WorkoutDurationEstimator.formatDuration(minutes: minutes) // "45 min" or "1 hr 15 min"
enum WorkoutDurationEstimator {

    private static let secondsPerRep: Double = 3
    private static let transitionSeconds: Double = 60
    private static let warmupSeconds: Double = 300

    /// Estimates total workout duration in minutes from plan exercises.
    /// - Parameters:
    ///   - exercises: The plan exercises with sets, reps, and rest info.
    ///   - defaultRestSeconds: Fallback rest time when an exercise doesn't specify one (from user settings).
    /// - Returns: Estimated duration in minutes (rounded up).
    static func estimate(exercises: [PlanExercise], defaultRestSeconds: Int = 90) -> Int {
        guard !exercises.isEmpty else { return 0 }

        var totalSeconds = warmupSeconds

        for (index, exercise) in exercises.enumerated() {
            let sets = max(exercise.targetSets, 1)
            let reps = exercise.targetRepsMax ?? exercise.targetRepsMin ?? 10
            let rest = exercise.restSeconds ?? defaultRestSeconds

            // Time under tension per set
            let setDuration = Double(reps) * secondsPerRep

            // Total for this exercise: (set duration + rest) × sets, minus rest after final set
            let exerciseTotal = Double(sets) * (setDuration + Double(rest)) - Double(rest)
            totalSeconds += exerciseTotal

            // Transition time between exercises (not after the last one)
            if index < exercises.count - 1 {
                totalSeconds += transitionSeconds
            }
        }

        return Int(ceil(totalSeconds / 60))
    }

    /// Estimates total workout duration from raw counts (when full PlanExercise data isn't available).
    /// - Parameters:
    ///   - exerciseCount: Number of exercises.
    ///   - totalSets: Total number of sets across all exercises.
    ///   - avgReps: Average reps per set (default 10).
    ///   - defaultRestSeconds: Rest time between sets.
    /// - Returns: Estimated duration in minutes.
    static func estimate(
        exerciseCount: Int,
        totalSets: Int,
        avgReps: Int = 10,
        defaultRestSeconds: Int = 90
    ) -> Int {
        guard exerciseCount > 0, totalSets > 0 else { return 0 }

        var totalSeconds = warmupSeconds

        let setDuration = Double(avgReps) * secondsPerRep
        let exerciseTotal = Double(totalSets) * (setDuration + Double(defaultRestSeconds)) - Double(exerciseCount) * Double(defaultRestSeconds)
        totalSeconds += exerciseTotal

        // Transition time between exercises
        totalSeconds += Double(max(0, exerciseCount - 1)) * transitionSeconds

        return Int(ceil(totalSeconds / 60))
    }

    /// Formats a duration in minutes to a human-readable string.
    ///
    ///     formatDuration(minutes: 45)  → "45 min"
    ///     formatDuration(minutes: 75)  → "1 hr 15 min"
    ///     formatDuration(minutes: 120) → "2 hrs"
    static func formatDuration(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }

        let hours = minutes / 60
        let mins = minutes % 60

        if hours == 0 {
            return "\(mins) min"
        } else if mins == 0 {
            return "\(hours) \(hours == 1 ? "hr" : "hrs")"
        } else {
            return "\(hours) \(hours == 1 ? "hr" : "hrs") \(mins) min"
        }
    }
}
