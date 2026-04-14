import Foundation

// MARK: - FrequencyProgress

struct FrequencyProgress {
    var target: Int
    var completed: Int
    var dayOfWeek: Int          // 1 = first day of user's week, 7 = last
    var daysRemainingInWeek: Int
}

// MARK: - GoalService

struct GoalService {

    // MARK: - Internal enqueue helper

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    // MARK: - Exercise Goals

    static func createGoal(
        exerciseId: String,
        targetWeightIncrease: Double,
        deadline: Date
    ) async throws -> ExerciseGoal {
        let userId = try authManager.requireUserId()

        let currentMax = try await ExerciseGoalRepository.findCurrentMaxWeight(exerciseId: exerciseId) ?? 0

        let id = UUID().uuidString
        let goal = ExerciseGoal(
            id: id,
            userId: userId,
            exerciseId: exerciseId,
            targetWeightIncrease: targetWeightIncrease,
            baselineWeight: currentMax,
            deadline: deadline
        )

        try await ExerciseGoalRepository.insert(goal)
        try await enqueue(table: "exercise_goals", op: "insert", payload: goalPayload(goal))

        Task { await GoalNotificationService.scheduleAllNotifications() }

        return goal
    }

    static func updateGoal(
        _ goalId: String,
        targetWeightIncrease: Double,
        deadline: Date
    ) async throws {
        guard var goal = try await ExerciseGoalRepository.findById(goalId) else { return }

        goal.targetWeightIncrease = targetWeightIncrease
        goal.deadline = deadline

        try await ExerciseGoalRepository.update(goal)
        try await enqueue(table: "exercise_goals", op: "update", payload: goalPayload(goal))
        Task { await GoalNotificationService.scheduleAllNotifications() }
    }

    static func deleteGoal(_ goalId: String) async throws {
        try await ExerciseGoalRepository.delete(goalId)
        try await enqueue(table: "exercise_goals", op: "delete", payload: ["id": goalId])
        Task { await GoalNotificationService.scheduleAllNotifications() }
    }

    /// Checks if a goal's target has been met. If so, marks it completed.
    @discardableResult
    static func checkGoalCompletion(_ goalId: String) async throws -> Bool {
        guard var goal = try await ExerciseGoalRepository.findById(goalId),
              !goal.isCompleted else { return false }

        let currentMax = try await ExerciseGoalRepository.findCurrentMaxWeight(
            exerciseId: goal.exerciseId
        ) ?? 0

        guard currentMax >= goal.targetWeight else { return false }

        goal.isCompleted = true
        goal.completedAt = Date()
        try await ExerciseGoalRepository.update(goal)
        try await enqueue(table: "exercise_goals", op: "update", payload: goalPayload(goal))

        return true
    }

    // MARK: - Frequency

    static func getFrequencyProgress() async throws -> FrequencyProgress? {
        guard let userId = try? authManager.requireUserId() else { return nil }
        let settings = authManager.user?.settings ?? .default
        guard let target = settings.weeklyFrequencyGoal else { return nil }

        let weekStart = Self.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let sessions = try await SessionRepository.findCompletedSince(weekStart, userId: userId)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysSinceStart = cal.dateComponents([.day], from: cal.startOfDay(for: weekStart), to: today).day ?? 0
        let dayOfWeek = daysSinceStart + 1  // 1-based
        let daysRemaining = max(0, 7 - dayOfWeek)

        return FrequencyProgress(
            target: target,
            completed: sessions.count,
            dayOfWeek: dayOfWeek,
            daysRemainingInWeek: daysRemaining
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
