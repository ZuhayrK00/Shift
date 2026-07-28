import Foundation
@preconcurrency import GRDB

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

    // MARK: - Plans

    static func listPlans() async throws -> [WorkoutPlanWithCount] {
        let userId = try authManager.requireUserId()
        return try await PlanRepository.findPlansWithCount(userId: userId)
    }

    static func getPlanWithExercises(_ id: String) async throws -> PlanWithExercises? {
        let userId = try authManager.requireUserId()
        guard let plan = try await PlanRepository.findById(id),
              plan.userId == userId else { return nil }

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
        let id = UUID().uuidString.lowercased()

        // Put new plans at the end
        let existing = try await PlanRepository.findPlansWithCount(userId: userId)
        let nextPosition = (existing.map { $0.plan.position }.max() ?? -1) + 1

        let plan = WorkoutPlan(id: id, userId: userId, name: name, position: nextPosition, createdAt: Date())

        let mutation = LocalMutation(table: "workout_plans", op: "insert", payload: [
            "id": id,
            "user_id": userId,
            "name": name,
            "notes": NSNull(),
            "position": nextPosition,
            "created_at": ISO8601DateFormatter.shared.string(from: plan.createdAt)
        ])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try plan.insert(db)
        }
        return plan
    }

    static func updatePlan(_ id: String, name: String?, notes: String?) async throws {
        var payload: [String: Any] = ["id": id]
        if let name  { payload["name"]  = name }
        if let notes { payload["notes"] = notes }
        let mutation = LocalMutation(table: "workout_plans", op: "update", payload: payload)
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            guard var plan = try WorkoutPlan.fetchOne(db, key: id) else { return }
            if let name { plan.name = name }
            if let notes { plan.notes = notes }
            try plan.update(db)
        }
    }

    static func reorderPlans(_ planIds: [String]) async throws {
        let positions = planIds.enumerated().map { (id: $1, position: $0) }
        let mutations = planIds.enumerated().map { index, planId in
            LocalMutation(table: "workout_plans", op: "update", payload: [
                "id": planId,
                "position": index,
            ])
        }
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            for item in positions {
                try db.execute(
                    sql: "UPDATE workout_plans SET position = ? WHERE id = ?",
                    arguments: [item.position, item.id]
                )
            }
        }
    }

    static func deletePlan(_ id: String) async throws {
        // Remove all plan exercises first
        let exercises = try await PlanRepository.findExercises(planId: id)
        let mutations = exercises.map {
            LocalMutation(table: "plan_exercises", op: "delete", payload: ["id": $0.id])
        } + [LocalMutation(table: "workout_plans", op: "delete", payload: ["id": id])]
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            try db.execute(sql: "DELETE FROM plan_exercises WHERE plan_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM workout_plans WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Plan exercises

    static func addExercises(
        planId: String,
        exerciseIds: [String],
        asGroup: Bool = false
    ) async throws -> [PlanExercise] {
        var maxPosition = try await PlanRepository.findMaxPosition(planId: planId)
        var added: [PlanExercise] = []
        let groupId: String? = asGroup ? UUID().uuidString.lowercased() : nil

        for exerciseId in exerciseIds {
            maxPosition += 1
            let id = UUID().uuidString.lowercased()
            let pe = PlanExercise(
                id: id,
                planId: planId,
                exerciseId: exerciseId,
                position: maxPosition,
                targetSets: 3,
                groupId: groupId
            )
            added.append(pe)
        }

        let mutations = added.map { pe in
            LocalMutation(table: "plan_exercises", op: "insert", payload: [
                "id": pe.id,
                "plan_id": pe.planId,
                "exercise_id": pe.exerciseId,
                "position": pe.position,
                "target_sets": pe.targetSets,
                "target_reps_min": NSNull(),
                "target_reps_max": NSNull(),
                "target_weight": NSNull(),
                "rest_seconds": NSNull(),
                "group_id": pe.groupId.map { $0 as Any } ?? NSNull()
            ])
        }
        let addedExercises = added
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            for exercise in addedExercises { try exercise.insert(db) }
        }
        return added
    }

    static func updateExercise(_ id: String, patch: PlanExercisePatch) async throws {
        var payload: [String: Any] = ["id": id]
        if let v = patch.targetSets    { payload["target_sets"]     = v }
        if let v = patch.targetRepsMin { payload["target_reps_min"] = v }
        if let v = patch.targetRepsMax { payload["target_reps_max"] = v }
        if let value = patch.targetWeight {
            payload["target_weight"] = value.map { $0 as Any } ?? NSNull()
        }
        if let v = patch.restSeconds   { payload["rest_seconds"]    = v }

        let mutation = LocalMutation(table: "plan_exercises", op: "update", payload: payload)
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            guard var exercise = try PlanExercise.fetchOne(db, key: id) else { return }
            if let value = patch.targetSets { exercise.targetSets = value }
            if let value = patch.targetRepsMin { exercise.targetRepsMin = value }
            if let value = patch.targetRepsMax { exercise.targetRepsMax = value }
            if let value = patch.targetWeight { exercise.targetWeight = value }
            if let value = patch.restSeconds { exercise.restSeconds = value }
            try exercise.update(db)
        }
    }

    static func reorderExercises(planId: String, exerciseIds: [String]) async throws {
        let positions = exerciseIds.enumerated().map { (id: $1, position: $0) }
        let mutations = exerciseIds.enumerated().map { index, id in
            LocalMutation(table: "plan_exercises", op: "update", payload: [
                "id": id,
                "position": index,
            ])
        }
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            for item in positions {
                try db.execute(
                    sql: "UPDATE plan_exercises SET position = ? WHERE id = ?",
                    arguments: [item.position, item.id]
                )
            }
        }
    }

    static func removeExercise(_ id: String) async throws {
        let mutation = LocalMutation(table: "plan_exercises", op: "delete", payload: ["id": id])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try db.execute(sql: "DELETE FROM plan_exercises WHERE id = ?", arguments: [id])
        }
    }

    /// Inserts preconfigured exercises (templates/AI) and their sync mutations
    /// in one transaction.
    static func addConfiguredExercises(_ exercises: [PlanExercise]) async throws {
        let mutations = exercises.map {
            LocalMutation(
                table: "plan_exercises",
                op: "insert",
                payload: planExercisePayload($0)
            )
        }
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            for exercise in exercises { try exercise.insert(db) }
        }
    }

    // MARK: - Session from plan

    /// Creates a new in-progress session pre-populated with placeholder sets from the plan.
    static func createSessionFromPlan(
        _ planId: String,
        startedAt: Date = Date()
    ) async throws -> WorkoutSession {
        let userId = try authManager.requireUserId()
        guard let plan = try await PlanRepository.findById(planId),
              plan.userId == userId else {
            throw PlanServiceError.planNotFound(planId)
        }

        let sessionId = UUID().uuidString.lowercased()
        let session = WorkoutSession(
            id: sessionId,
            userId: userId,
            planId: planId,
            name: plan.name,
            startedAt: startedAt
        )

        // Add placeholder sets for each plan exercise, respecting targetSets count.
        // Preserve superset grouping: exercises sharing a plan group_id get
        // the same session group_id so the workout UI treats them as a superset.
        let planExercises = try await PlanRepository.findExercises(planId: planId)
        var planGroupToSessionGroup: [String: String] = [:]

        var placeholders: [SessionSet] = []
        for pe in planExercises {
            let sessionGroupId: String? = {
                guard let pgid = pe.groupId else { return nil }
                if let existing = planGroupToSessionGroup[pgid] { return existing }
                let newId = UUID().uuidString.lowercased()
                planGroupToSessionGroup[pgid] = newId
                return newId
            }()

            let setCount = max(pe.targetSets, 1)
            for setNum in 1...setCount {
                let setId = UUID().uuidString.lowercased()
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
                placeholders.append(placeholder)
            }
        }

        let sessionMutation = LocalMutation(table: "workout_sessions", op: "insert", payload: [
            "id": sessionId,
            "user_id": userId,
            "plan_id": planId,
            "name": plan.name,
            "started_at": ISO8601DateFormatter.shared.string(from: startedAt),
            "ended_at": NSNull(),
            "notes": NSNull()
        ])
        let setMutations = placeholders.map {
            LocalMutation(
                table: "session_sets",
                op: "insert",
                payload: WorkoutService.setPayload($0)
            )
        }
        let sessionPlaceholders = placeholders
        try await MutationQueueRepository.performAtomically(
            mutations: [sessionMutation] + setMutations
        ) { db in
            try SessionRepository.insert(session, in: db)
            for placeholder in sessionPlaceholders {
                try SessionSetRepository.insert(placeholder, in: db)
            }
        }

        return session
    }

    private static func planExercisePayload(_ exercise: PlanExercise) -> [String: Any] {
        [
            "id": exercise.id,
            "plan_id": exercise.planId,
            "exercise_id": exercise.exerciseId,
            "position": exercise.position,
            "target_sets": exercise.targetSets,
            "target_reps_min": exercise.targetRepsMin.map { $0 as Any } ?? NSNull(),
            "target_reps_max": exercise.targetRepsMax.map { $0 as Any } ?? NSNull(),
            "target_weight": exercise.targetWeight.map { $0 as Any } ?? NSNull(),
            "rest_seconds": exercise.restSeconds.map { $0 as Any } ?? NSNull(),
            "group_id": exercise.groupId.map { $0 as Any } ?? NSNull(),
        ]
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
