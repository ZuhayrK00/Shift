import Foundation
@preconcurrency import GRDB

// MARK: - FrequencyProgress

struct FrequencyProgress {
    var target: Int
    var completed: Int
    var dayOfWeek: Int          // 1 = first day of user's week, 7 = last
    var daysRemainingInWeek: Int
    var trainingDays: [Int]     // ISO weekdays selected by the user
}

// MARK: - GoalService

struct GoalService {

    // MARK: - Exercise Goals

    static func createGoal(
        exerciseId: String,
        targetWeightIncrease: Double,
        deadline: Date
    ) async throws -> ExerciseGoal {
        let userId = try authManager.requireUserId()

        let currentMax = try await ExerciseGoalRepository.findCurrentMaxWeight(exerciseId: exerciseId) ?? 0

        let id = UUID().uuidString.lowercased()
        let goal = ExerciseGoal(
            id: id,
            userId: userId,
            exerciseId: exerciseId,
            targetWeightIncrease: targetWeightIncrease,
            baselineWeight: currentMax,
            deadline: deadline
        )

        let mutation = LocalMutation(
            table: "exercise_goals",
            op: "insert",
            payload: goalPayload(goal)
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try goal.insert(db)
        }

        return goal
    }

    static func updateGoal(
        _ goalId: String,
        targetWeightIncrease: Double,
        deadline: Date
    ) async throws {
        let userId = try authManager.requireUserId()
        guard var goal = try await ExerciseGoalRepository.findById(goalId),
              goal.userId == userId else { return }

        goal.targetWeightIncrease = targetWeightIncrease
        goal.deadline = deadline

        let mutation = LocalMutation(
            table: "exercise_goals",
            op: "update",
            payload: goalPayload(goal)
        )
        let goalToSave = goal
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try goalToSave.update(db)
        }
    }

    static func deleteGoal(_ goalId: String) async throws {
        let userId = try authManager.requireUserId()
        guard let goal = try await ExerciseGoalRepository.findById(goalId) else {
            // Deletion is idempotent. If another device already removed the
            // record, the requested end state has already been reached.
            return
        }
        guard goal.userId == userId else {
            throw GoalServiceError.goalUnavailable
        }
        let mutation = LocalMutation(
            table: "exercise_goals",
            op: "delete",
            payload: ["id": goalId]
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try db.execute(sql: "DELETE FROM exercise_goals WHERE id = ?", arguments: [goalId])
        }
    }

    /// Checks if a goal's target has been met. If so, marks it completed.
    @discardableResult
    static func checkGoalCompletion(_ goalId: String) async throws -> Bool {
        let userId = try authManager.requireUserId()
        guard var goal = try await ExerciseGoalRepository.findById(goalId),
              goal.userId == userId,
              !goal.isCompleted else { return false }

        let currentMax = try await ExerciseGoalRepository.findCurrentMaxWeight(
            exerciseId: goal.exerciseId
        ) ?? 0

        guard currentMax >= goal.targetWeight else { return false }

        goal.isCompleted = true
        goal.completedAt = Date()
        let mutation = LocalMutation(
            table: "exercise_goals",
            op: "update",
            payload: goalPayload(goal)
        )
        let completedGoal = goal
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try completedGoal.update(db)
        }

        return true
    }

    // MARK: - Frequency

    static func getFrequencyProgress() async throws -> FrequencyProgress? {
        guard let userId = try? authManager.requireUserId() else { return nil }
        let settings = authManager.user?.settings ?? .default
        guard let target = settings.effectiveWeeklyFrequencyGoal else { return nil }

        let weekStart = Self.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let sessions = try await SessionRepository.findCompletedSince(weekStart, userId: userId)

        var totalCount = sessions.count
        if settings.healthKit.countExternalWorkouts {
            totalCount += await HealthKitService.countExternalWorkouts(since: weekStart)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysSinceStart = cal.dateComponents([.day], from: cal.startOfDay(for: weekStart), to: today).day ?? 0
        let dayOfWeek = daysSinceStart + 1  // 1-based
        let daysRemaining = max(0, 7 - dayOfWeek)

        return FrequencyProgress(
            target: target,
            completed: totalCount,
            dayOfWeek: dayOfWeek,
            daysRemainingInWeek: daysRemaining,
            trainingDays: settings.normalizedWeeklyTrainingDays
        )
    }

    /// Returns the start of the current week based on the user's weekStartsOn setting.
    static func startOfCurrentWeek(weekStartsOn: String) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOn == "sunday" ? 1 : 2  // 1=Sunday, 2=Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    // MARK: - Private

    private static func goalPayload(_ goal: ExerciseGoal) -> [String: Any] {
        var payload: [String: Any] = [
            "id": goal.id,
            "user_id": goal.userId,
            "exercise_id": goal.exerciseId,
            "target_weight_increase": goal.targetWeightIncrease,
            "baseline_weight": goal.baselineWeight,
            "deadline": ISO8601DateFormatter.shared.string(from: goal.deadline),
            "is_completed": goal.isCompleted,
            "created_at": ISO8601DateFormatter.shared.string(from: goal.createdAt)
        ]
        if let completedAt = goal.completedAt {
            payload["completed_at"] = ISO8601DateFormatter.shared.string(from: completedAt)
        } else {
            payload["completed_at"] = NSNull()
        }
        return payload
    }
}

enum GoalServiceError: LocalizedError {
    case goalUnavailable

    var errorDescription: String? {
        switch self {
        case .goalUnavailable:
            return "This goal could not be deleted because it belongs to a different account."
        }
    }
}
