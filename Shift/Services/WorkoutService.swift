import Foundation

// MARK: - WorkoutService

struct WorkoutService {

    // MARK: - Internal enqueue helper

    /// Appends a mutation to the local queue and kicks off a background flush.
    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    // MARK: - Sessions

    static func createSession(
        name: String = "Workout",
        startedAt: Date = Date()
    ) async throws -> WorkoutSession {
        guard let userId = try? authManager.requireUserId() else {
            throw WorkoutServiceError.notAuthenticated
        }
        let id = UUID().uuidString
        let session = WorkoutSession(
            id: id,
            userId: userId,
            name: name,
            startedAt: startedAt
        )
        try await SessionRepository.insert(session)
        try await enqueue(table: "workout_sessions", op: "insert", payload: [
            "id": id,
            "user_id": userId,
            "plan_id": NSNull(),
            "name": name,
            "started_at": ISO8601DateFormatter.shared.string(from: startedAt),
            "ended_at": NSNull(),
            "notes": NSNull()
        ])
        return session
    }

    static func getSession(_ id: String) async throws -> WorkoutSession? {
        try await SessionRepository.findById(id)
    }

    static func getLatestInProgress() async throws -> WorkoutSession? {
        try await SessionRepository.findLatestInProgress()
    }

    static func finishSession(_ sessionId: String) async throws {
        let endedAt = Date()
        try await SessionRepository.setEndedAt(sessionId, endedAt)
        try await enqueue(table: "workout_sessions", op: "update", payload: [
            "id": sessionId,
            "ended_at": ISO8601DateFormatter.shared.string(from: endedAt)
        ])

        // Check exercise goals for completion and reschedule notifications
        Task {
            let exerciseIds = (try? await SessionSetRepository.findExerciseIds(sessionId: sessionId)) ?? []
            for exerciseId in exerciseIds {
                let goals = (try? await ExerciseGoalRepository.findByExercise(exerciseId)) ?? []
                for goal in goals where !goal.isCompleted {
                    _ = try? await GoalService.checkGoalCompletion(goal.id)
                }
            }
            await GoalNotificationService.scheduleAllNotifications()
        }
    }

    static func resumeSession(_ sessionId: String) async throws {
        try await SessionRepository.setEndedAt(sessionId, nil)
        try await enqueue(table: "workout_sessions", op: "update", payload: [
            "id": sessionId,
            "ended_at": NSNull() as Any
        ])
    }

    static func deleteSession(_ sessionId: String) async throws {
        // Delete all sets and enqueue deletes for each
        let setIds = try await SessionSetRepository.findSetIds(sessionId: sessionId)
        for setId in setIds {
            try await SessionSetRepository.delete(setId)
            try await enqueue(table: "session_sets", op: "delete", payload: ["id": setId])
        }
        // Delete the session itself
        try await SessionRepository.delete(sessionId)
        try await enqueue(table: "workout_sessions", op: "delete", payload: ["id": sessionId])
    }

    // MARK: - Exercises in session

    static func getSessionExerciseIds(_ sessionId: String) async throws -> [String] {
        try await SessionSetRepository.findExerciseIds(sessionId: sessionId)
    }

    static func getSetsFor(sessionId: String, exerciseId: String) async throws -> [SessionSet] {
        try await SessionSetRepository.findForExercise(sessionId: sessionId, exerciseId: exerciseId)
    }

    static func removeExercise(sessionId: String, exerciseId: String) async throws {
        let sets = try await SessionSetRepository.findForExercise(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
        for s in sets {
            try await SessionSetRepository.delete(s.id)
            try await enqueue(table: "session_sets", op: "delete", payload: ["id": s.id])
        }
    }

    // MARK: - Sets

    static func addSet(sessionId: String, exerciseId: String) async throws -> SessionSet {
        guard let userId = try? authManager.requireUserId() else {
            throw WorkoutServiceError.notAuthenticated
        }
        _ = userId  // captured for context; session already owns the userId

        let existing = try await SessionSetRepository.findForExercise(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
        let placeholders = existing.filter { !$0.isCompleted && $0.reps == 0 && $0.weight == nil }
        let lastCompleted = existing.filter { $0.isCompleted }.last

        // Preserve groupId from completed sets first, then fall back to placeholders
        let inheritedGroupId = lastCompleted?.groupId ?? existing.first?.groupId

        let nextNumber = (existing.filter { $0.isCompleted }.count) + 1

        // If there's a placeholder, complete it in-place to preserve rowid ordering
        if let placeholder = placeholders.first {
            let patch = SetPatch(
                reps: lastCompleted?.reps ?? 0,
                weight: lastCompleted?.weight,
                isCompleted: true,
                setNumber: nextNumber,
                setType: lastCompleted?.setType ?? .normal
            )
            try await SessionSetRepository.update(placeholder.id, patch: patch)
            try await SessionSetRepository.setCompletedAt(placeholder.id, date: Date())
            if placeholder.groupId == nil, let gid = inheritedGroupId {
                try await SessionSetRepository.setGroupId(placeholder.id, groupId: gid)
            }

            var completedSet = placeholder
            completedSet.setNumber = nextNumber
            completedSet.reps = lastCompleted?.reps ?? 0
            completedSet.weight = lastCompleted?.weight
            completedSet.isCompleted = true
            completedSet.completedAt = Date()
            completedSet.setType = lastCompleted?.setType ?? .normal
            completedSet.groupId = placeholder.groupId ?? inheritedGroupId

            try await enqueue(table: "session_sets", op: "update", payload: setPayload(completedSet))

            // Remove remaining extra placeholders (keep only the first one that we completed)
            for extra in placeholders.dropFirst() {
                try await SessionSetRepository.delete(extra.id)
                try await enqueue(table: "session_sets", op: "delete", payload: ["id": extra.id])
            }

            return completedSet
        }

        // No placeholders — insert a fresh set
        let id = UUID().uuidString
        let newSet = SessionSet(
            id: id,
            sessionId: sessionId,
            exerciseId: exerciseId,
            setNumber: nextNumber,
            reps: lastCompleted?.reps ?? 0,
            weight: lastCompleted?.weight,
            isCompleted: true,
            completedAt: Date(),
            setType: lastCompleted?.setType ?? .normal,
            groupId: inheritedGroupId
        )

        try await SessionSetRepository.insert(newSet)
        try await enqueue(table: "session_sets", op: "insert", payload: setPayload(newSet))

        return newSet
    }

    static func addExercisesToSession(
        _ sessionId: String,
        exerciseIds: [String],
        asGroup: Bool = false
    ) async throws {
        let groupId: String? = asGroup ? UUID().uuidString : nil

        for exerciseId in exerciseIds {
            // Position placeholder after any existing sets
            let existing = try await SessionSetRepository.findForExercise(
                sessionId: sessionId,
                exerciseId: exerciseId
            )
            let nextNumber = existing.count + 1

            let id = UUID().uuidString
            let placeholder = SessionSet(
                id: id,
                sessionId: sessionId,
                exerciseId: exerciseId,
                setNumber: nextNumber,
                reps: 0,
                weight: nil,
                isCompleted: false,
                completedAt: nil,
                setType: .normal,
                groupId: groupId
            )
            try await SessionSetRepository.insert(placeholder)
            try await enqueue(table: "session_sets", op: "insert", payload: setPayload(placeholder))
        }
    }

    static func updateSet(_ setId: String, patch: SetPatch) async throws {
        try await SessionSetRepository.update(setId, patch: patch)

        var remote: [String: Any] = ["id": setId]
        if let reps = patch.reps { remote["reps"] = reps }
        if let weight = patch.weight { remote["weight"] = weight }
        if let isCompleted = patch.isCompleted { remote["is_completed"] = isCompleted }
        if let setNumber = patch.setNumber { remote["set_number"] = setNumber }
        if let setType = patch.setType { remote["set_type"] = setType.rawValue }

        try await enqueue(table: "session_sets", op: "update", payload: remote)
    }

    static func deleteSet(_ setId: String) async throws {
        guard let ownership = try await SessionSetRepository.findOwnership(setId) else { return }

        try await SessionSetRepository.delete(setId)
        try await enqueue(table: "session_sets", op: "delete", payload: ["id": setId])
        try await renumberSets(sessionId: ownership.sessionId, exerciseId: ownership.exerciseId)
    }

    // MARK: - Calendar summaries

    static func getCompletedSessionDates() async throws -> Set<String> {
        let sessions = try await SessionRepository.findCompleted()
        return Set(sessions.map { toLocalDateKey($0.startedAt) })
    }

    static func getInProgressSessionDates() async throws -> Set<String> {
        let sessions = try await SessionRepository.findInProgress()
        return Set(sessions.map { toLocalDateKey($0.startedAt) })
    }

    static func getCompletedSessions(for date: Date) async throws -> [SessionSummary] {
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findCompleted()
        let onDate = sessions.filter { toLocalDateKey($0.startedAt) == key }
        return try await onDate.asyncMap { try await buildSummary($0) }
    }

    static func getInProgressSessions(for date: Date) async throws -> [SessionSummary] {
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findInProgress()
        let onDate = sessions.filter { toLocalDateKey($0.startedAt) == key }
        return try await onDate.asyncMap { try await buildSummary($0) }
    }

    static func getInProgressSessionId(for date: Date) async throws -> String? {
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findInProgress()
        return sessions.first(where: { toLocalDateKey($0.startedAt) == key })?.id
    }

    // MARK: - Superset helper

    static func isGroupRoundComplete(sessionId: String, groupId: String?) async throws -> Bool {
        guard let groupId else { return true }
        let min = try await SessionSetRepository.findMinCompletedInGroup(
            sessionId: sessionId,
            groupId: groupId
        )
        return min > 0
    }

    // MARK: - Private helpers

    private static func renumberSets(sessionId: String, exerciseId: String) async throws {
        let remaining = try await SessionSetRepository.findForExercise(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
        let completed = remaining.filter { $0.isCompleted }
        for (index, set) in completed.enumerated() {
            let newNumber = index + 1
            guard set.setNumber != newNumber else { continue }
            try await SessionSetRepository.update(set.id, patch: SetPatch(setNumber: newNumber))
            try await enqueue(table: "session_sets", op: "update", payload: [
                "id": set.id,
                "set_number": newNumber
            ])
        }
    }

    private static func buildSummary(_ session: WorkoutSession) async throws -> SessionSummary {
        let exerciseSummaries = try await SessionRepository.findExerciseSummaries(
            sessionId: session.id
        )
        return SessionSummary(
            id: session.id,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exercises: exerciseSummaries.map {
                SessionSummaryExercise(id: $0.id, name: $0.name, setCount: $0.setCount)
            }
        )
    }

    static func setPayload(_ set: SessionSet) -> [String: Any] {
        var payload: [String: Any] = [
            "id": set.id,
            "session_id": set.sessionId,
            "exercise_id": set.exerciseId,
            "set_number": set.setNumber,
            "reps": set.reps,
            "is_completed": set.isCompleted,
            "set_type": set.setType.rawValue
        ]
        payload["weight"] = set.weight.map { $0 as Any } ?? NSNull()
        payload["rpe"] = set.rpe.map { $0 as Any } ?? NSNull()
        payload["group_id"] = set.groupId.map { $0 as Any } ?? NSNull()
        if let completedAt = set.completedAt {
            payload["completed_at"] = ISO8601DateFormatter.shared.string(from: completedAt)
        } else {
            payload["completed_at"] = NSNull()
        }
        return payload
    }
}

// MARK: - WorkoutServiceError

enum WorkoutServiceError: LocalizedError {
    case notAuthenticated
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "No signed-in user."
        case .sessionNotFound(let id): return "Session \(id) not found."
        }
    }
}

// MARK: - authManager accessor

/// Convenience reference to the shared AuthManager. Resolved via the environment
/// in UI code; here we access it directly because services are called from views
/// that already hold a reference. In practice callers pass the userId explicitly
/// via `createSession(name:startedAt:)` or the service reads it from AuthManager.
///
/// To avoid a hard coupling, the file exposes a module-level `authManager` that
/// views bind before calling service functions. Alternatively, callers can pass
/// a `userId` parameter directly — both patterns are supported.
private var _authManager: AuthManager?

/// Set this once during app startup so WorkoutService can resolve the current user.
var authManager: AuthManager {
    get {
        guard let m = _authManager else {
            fatalError("authManager has not been set. Call setAuthManager(_:) on app launch.")
        }
        return m
    }
}

func setAuthManager(_ manager: AuthManager) {
    _authManager = manager
}

// MARK: - Sequence async helpers

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
