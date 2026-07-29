import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@Generable
struct GeneratedPlan: Codable {
    @Guide(description: "A short, specific name for this training program")
    var planName: String

    @Guide(description: "Two concise sentences explaining the training split and how it supports the user's goal")
    var summary: String

    @Guide(description: "The requested number of workout days in the program")
    var days: [GeneratedDay]
}

@available(iOS 26, *)
@Generable
struct GeneratedDay: Codable {
    @Guide(description: "A short workout name, for example Upper A, Push, or Full Body")
    var dayName: String

    @Guide(description: "One concise sentence explaining the muscles and movement patterns trained")
    var focus: String

    @Guide(description: "Exercises in performance order, with compound movements before accessories")
    var exercises: [GeneratedExercise]
}

@available(iOS 26, *)
@Generable
struct GeneratedExercise: Codable {
    @Guide(description: "The exact stable exercise ID from the provided catalogue")
    var exerciseID: String

    @Guide(description: "The exact exercise name paired with the exercise ID")
    var exerciseName: String

    @Guide(description: "Working sets, between 2 and 5")
    var sets: Int

    @Guide(description: "Minimum repetitions per working set, between 1 and 30")
    var repsMin: Int

    @Guide(description: "Maximum repetitions per working set, between the minimum and 30")
    var repsMax: Int

    @Guide(description: "Rest between working sets in seconds, between 30 and 300")
    var restSeconds: Int
}
#endif
