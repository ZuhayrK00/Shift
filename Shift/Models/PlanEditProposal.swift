import Foundation

struct ConfirmedPlanExerciseEdit: Identifiable {
    enum Action: String {
        case update
        case remove
        case replace
        case add
    }

    let id = UUID()
    let action: Action
    let planExerciseID: String?
    let exerciseID: String?
    let exerciseName: String
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let restSeconds: Int
    let explanation: String
}

struct ConfirmedPlanEdit {
    let summary: String
    let planName: String?
    let exerciseEdits: [ConfirmedPlanExerciseEdit]
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@Generable
struct GeneratedPlanEdit {
    @Guide(description: "One short sentence summarizing the proposed changes")
    var summary: String

    @Guide(description: "A new short plan name, or an empty string to keep the current name")
    var planName: String

    @Guide(description: "Only the changes needed to satisfy the request")
    var exerciseEdits: [GeneratedPlanExerciseEdit]
}

@available(iOS 26, *)
@Generable
struct GeneratedPlanExerciseEdit {
    @Guide(description: "One of update, remove, replace, or add")
    var action: String

    @Guide(description: "Exact existing plan exercise ID, or empty only when action is add")
    var planExerciseID: String

    @Guide(description: "Exact catalogue exercise ID for replace/add, otherwise empty")
    var exerciseID: String

    @Guide(description: "2 to 8 working sets")
    var sets: Int

    @Guide(description: "1 to 30 minimum repetitions")
    var repsMin: Int

    @Guide(description: "Minimum repetitions through 30 maximum repetitions")
    var repsMax: Int

    @Guide(description: "30 to 300 seconds rest")
    var restSeconds: Int

    @Guide(description: "A concise reason this change answers the user's request")
    var explanation: String
}
#endif
