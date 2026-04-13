import Foundation

// MARK: - Supporting types

struct EnrichedPlanExercise: Identifiable {
    var planExercise: PlanExercise
    var exercise: Exercise
    var id: String { planExercise.id }
}

struct PlanWithExercises {
    var plan: WorkoutPlan
    var exercises: [EnrichedPlanExercise]
}

// MARK: - PlanService

struct PlanService {

    // MARK: - Internal enqueue helper

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    // MARK: - Plans

    static func listPlans() async throws -> [WorkoutPlanWithCount] {
        let userId = try authManager.requireUserId()
        return try await PlanRepository.findPlansWithCount(userId: userId)
    }

    static func getPlanWithExercises(_ id: String) async throws -> PlanWithExercises? {
        guard let plan = try await PlanRepository.findById(id) else { return nil }

        let planExercises = try await PlanRepository.findExercises(planId: id)
        let exerciseIds = planExercises.map { $0.exerciseId }
        let exerciseMap = try await ExerciseRepository.findByIds(exerciseIds)

        let enriched: [EnrichedPlanExercise] = planExercises.compactMap { pe in
            guard let exercise = exerciseMap[pe.exerciseId] else { return nil }
            return EnrichedPlanExercise(planExercise: pe, exercise: exercise)
        }

        return PlanWithExercises(plan: plan, exercises: enriched)
    }

    static func createPlan(name: String) async throws -> WorkoutPlan {
        let userId = try authManager.requireUserId()
        let id = UUID().uuidString
        let plan = WorkoutPlan(id: id, userId: userId, name: name, createdAt: Date())

        try await PlanRepository.insert(plan)
        try await enqueue(table: "workout_plans", op: "insert", payload: [
            "id": id,
            "user_id": userId,
            "name": name,
            "notes": NSNull(),
            "created_at": ISO8601DateFormatter.shared.string(from: plan.createdAt)
        ])
        return plan
    }

    static func updatePlan(_ id: String, name: String?, notes: String?) async throws {
        try await PlanRepository.update(id, name: name, notes: notes)

        var payload: [String: Any] = ["id": id]
        if let name  { payload["name"]  = name }
        if let notes { payload["notes"] = notes }
        try await enqueue(table: "workout_plans", op: "update", payload: payload)
    }

    static func deletePlan(_ id: String) async throws {
        // Remove all plan exercises first
        let exercises = try await PlanRepository.findExercises(planId: id)
        for pe in exercises {
            try await PlanRepository.deleteExercise(pe.id)
            try await enqueue(table: "plan_exercises", op: "delete", payload: ["id": pe.id])
        }
        try await PlanRepository.delete(id)
        try await enqueue(table: "workout_plans", op: "delete", payload: ["id": id])
    }

    // MARK: - Plan exercises

    static func addExercises(
        planId: String,
        exerciseIds: [String],
        asGroup: Bool = false
    ) async throws -> [PlanExercise] {
        var maxPosition = try await PlanRepository.findMaxPosition(planId: planId)
        var added: [PlanExercise] = []
        let groupId: String? = asGroup ? UUID().uuidString : nil

        for exerciseId in exerciseIds {
            maxPosition += 1
            let id = UUID().uuidString
            let pe = PlanExercise(
                id: id,
                planId: planId,
                exerciseId: exerciseId,
                position: maxPosition,
                targetSets: 3,
                groupId: groupId
            )
            try await PlanRepository.insertExercise(pe)
            try await enqueue(table: "plan_exercises", op: "insert", payload: [
                "id": id,
                "plan_id": planId,
                "exercise_id": exerciseId,
                "position": maxPosition,
                "target_sets": 3,
                "target_reps_min": NSNull(),
                "target_reps_max": NSNull(),
                "target_weight": NSNull(),
                "rest_seconds": NSNull(),
                "group_id": groupId.map { $0 as Any } ?? NSNull()
            ])
            added.append(pe)
        }

        return added
    }

    static func updateExercise(_ id: String, patch: PlanExercisePatch) async throws {
        try await PlanRepository.updateExercise(id, patch: patch)

        var payload: [String: Any] = ["id": id]
        if let v = patch.targetSets    { payload["target_sets"]     = v }
        if let v = patch.targetRepsMin { payload["target_reps_min"] = v }
        if let v = patch.targetRepsMax { payload["target_reps_max"] = v }
        if let v = patch.targetWeight  { payload["target_weight"]   = v }
        if let v = patch.restSeconds   { payload["rest_seconds"]    = v }

        try await enqueue(table: "plan_exercises", op: "update", payload: payload)
    }

    static func removeExercise(_ id: String) async throws {
        try await PlanRepository.deleteExercise(id)
        try await enqueue(table: "plan_exercises", op: "delete", payload: ["id": id])
    }

    // MARK: - Session from plan

    /// Creates a new in-progress session pre-populated with placeholder sets from the plan.
    static func createSessionFromPlan(
        _ planId: String,
        startedAt: Date = Date()
    ) async throws -> WorkoutSession {
        guard let plan = try await PlanRepository.findById(planId) else {
            throw PlanServiceError.planNotFound(planId)
        }

        let userId = try authManager.requireUserId()
        let sessionId = UUID().uuidString
        let session = WorkoutSession(
            id: sessionId,
            userId: userId,
            planId: planId,
            name: plan.name,
            startedAt: startedAt
        )

        try await SessionRepository.insert(session)
        try await MutationQueueRepository.enqueue(
            table: "workout_sessions",
            op: "insert",
            payload: [
                "id": sessionId,
                "user_id": userId,
                "plan_id": planId,
                "name": plan.name,
                "started_at": ISO8601DateFormatter.shared.string(from: startedAt),
                "ended_at": NSNull(),
                "notes": NSNull()
            ]
        )
        SyncService.flushInBackground()

        // Add placeholder sets for each plan exercise, respecting targetSets count.
        // Preserve superset grouping: exercises sharing a plan group_id get
        // the same session group_id so the workout UI treats them as a superset.
        let planExercises = try await PlanRepository.findExercises(planId: planId)
        var planGroupToSessionGroup: [String: String] = [:]

        for pe in planExercises {
            let sessionGroupId: String? = {
                guard let pgid = pe.groupId else { return nil }
                if let existing = planGroupToSessionGroup[pgid] { return existing }
                let newId = UUID().uuidString
                planGroupToSessionGroup[pgid] = newId
                return newId
            }()

            let setCount = max(pe.targetSets, 1)
            for setNum in 1...setCount {
                let setId = UUID().uuidString
                let placeholder = SessionSet(
                    id: setId,
                    sessionId: sessionId,
                    exerciseId: pe.exerciseId,
                    setNumber: setNum,
                    reps: pe.defaultReps,
                    weight: pe.targetWeight,
                    isCompleted: false,
                    groupId: sessionGroupId
                )
                try await SessionSetRepository.insert(placeholder)
                try await MutationQueueRepository.enqueue(
                    table: "session_sets",
                    op: "insert",
                    payload: WorkoutService.setPayload(placeholder)
                )
            }
        }
        SyncService.flushInBackground()

        return session
    }
}

// MARK: - PlanServiceError

enum PlanServiceError: LocalizedError {
    case planNotFound(String)

    var errorDescription: String? {
        switch self {
        case .planNotFound(let id): return "Plan \(id) not found."
        }
    }
}
