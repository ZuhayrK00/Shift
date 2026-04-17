import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@Generable
struct GeneratedPlan {
    @Guide(description: "Name for this activity sequence")
    var planName: String

    @Guide(description: "2-3 sentence rationale explaining the overall structure: how sessions are split, which categories each session emphasizes, and why modules were distributed this way for the stated optimization")
    var summary: String

    @Guide(description: "Individual sessions in the sequence")
    var days: [GeneratedDay]
}

@available(iOS 26, *)
@Generable
struct GeneratedDay {
    @Guide(description: "Label for this session, e.g. 'Session A' or 'Upper'")
    var dayName: String

    @Guide(description: "1 sentence explaining the focus of this session — which muscle categories are targeted and why these specific modules were selected together")
    var focus: String

    @Guide(description: "Movement modules assigned to this session, ordered by priority")
    var exercises: [GeneratedExercise]
}

@available(iOS 26, *)
@Generable
struct GeneratedExercise {
    @Guide(description: "The exact module name from the provided list")
    var exerciseName: String

    @Guide(description: "Number of rounds, typically 2-5")
    var sets: Int

    @Guide(description: "Minimum repetitions per round")
    var repsMin: Int

    @Guide(description: "Maximum repetitions per round, must be >= repsMin")
    var repsMax: Int

    @Guide(description: "Pause between rounds in seconds, typically 60-180")
    var restSeconds: Int
}
#endif
