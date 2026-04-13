import Foundation

// NOT a database record — synthesized from a query joining sessions and sets.

struct SessionSummary {
    var id: String
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [SessionSummaryExercise]
}
