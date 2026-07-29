import Foundation
import os.log
@preconcurrency import GRDB

private let logger = Logger(subsystem: "com.shift.app", category: "WorkoutService")

// MARK: - WorkoutService

struct WorkoutService {

    // MARK: - Sessions

    static func createSession(
        name: String = "Workout",
        startedAt: Date = Date(),
        id requestedId: String? = nil
    ) async throws -> WorkoutSession {
        guard let userId = try? authManager.requireUserId() else {
            throw WorkoutServiceError.notAuthenticated
        }
        let id = requestedId ?? UUID().uuidString.lowercased()
        if let existing = try await SessionRepository.findById(id) {
            guard existing.userId == userId else {
                throw WorkoutServiceError.sessionNotFound(id)
            }
            return existing
        }
        let session = WorkoutSession(
            id: id,
            userId: userId,
            name: name,
            startedAt: startedAt
        )
        let mutation = LocalMutation(table: "workout_sessions", op: "insert", payload: [
            "id": id,
            "user_id": userId,
            "plan_id": NSNull(),
            "name": name,
            "started_at": ISO8601DateFormatter.shared.string(from: startedAt),
            "ended_at": NSNull(),
            "notes": NSNull()
        ])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try SessionRepository.insert(session, in: db)
        }
        await refreshIdleAlertIfNeeded(sessionId: id)
        return session
    }

    static func getSession(_ id: String) async throws -> WorkoutSession? {
        let userId = try authManager.requireUserId()
        guard let session = try await SessionRepository.findById(id),
              session.userId == userId else { return nil }
        return session
    }

    static func getLatestInProgress() async throws -> WorkoutSession? {
        guard let userId = try? authManager.requireUserId() else { return nil }
        return try await SessionRepository.findLatestInProgress(userId: userId)
    }

    static func finishSession(_ sessionId: String) async throws {
        // Determine ended-at:
        // 1. If this session was previously completed (has originalEndedAt), restore it.
        // 2. For live sessions (< 12h old), use current time.
        // 3. For backfill sessions (> 12h old), estimate from set count.
        let endedAt: Date
        if let session = try await SessionRepository.findById(sessionId) {
            if let originalEndedAt = session.originalEndedAt {
                // Previously completed — restore original end time
                endedAt = originalEndedAt
            } else {
                let now = Date()
                let sessionAge = now.timeIntervalSince(session.startedAt)
                if sessionAge > 12 * 3600 {
                    // Backfill — estimate duration from set count (≈3 min per set, minimum 15 min)
                    let setCount = try await SessionSetRepository.countCompleted(sessionId: sessionId)
                    let estimatedMinutes = max(15, setCount * 3)
                    endedAt = session.startedAt.addingTimeInterval(Double(estimatedMinutes * 60))
                } else {
                    endedAt = now
                }
            }
        } else {
            endedAt = Date()
        }

        let mutation = LocalMutation(table: "workout_sessions", op: "update", payload: [
            "id": sessionId,
            "ended_at": ISO8601DateFormatter.shared.string(from: endedAt)
        ])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try SessionRepository.setEndedAt(sessionId, endedAt, in: db)
        }
        NotificationManager.cancelIdleWorkoutNotification(sessionId: sessionId)

        // Check exercise goals and notify only for goals completed by this event.
        do {
            let exerciseIds = try await SessionSetRepository.findExerciseIds(sessionId: sessionId)
            for exerciseId in exerciseIds {
                let goals = (try? await ExerciseGoalRepository.findByExercise(exerciseId)) ?? []
                for goal in goals where !goal.isCompleted {
                    if (try? await GoalService.checkGoalCompletion(goal.id)) == true {
                        await GoalNotificationService.notifyExerciseGoalCompleted(goal)
                    }
                }
            }
        } catch {
            logger.error("Failed to check goal completion after finishing session: \(error.localizedDescription)")
        }
        await GoalNotificationService.notifyFrequencyGoalIfReached()

        // Save workout to HealthKit if enabled
        if authManager.user?.settings.healthKit.syncWorkouts == true {
            do {
                if let session = try await SessionRepository.findById(sessionId),
                   session.endedAt != nil {
                    let eIds = try await SessionSetRepository.findExerciseIds(sessionId: sessionId)
                    let exerciseMap = try await ExerciseRepository.findByIds(eIds)
                    let nameMap = exerciseMap.mapValues(\.name)
                    try await HealthKitService.saveWorkout(session: session, exerciseNames: nameMap)
                }
            } catch {
                logger.error("Failed to save workout to HealthKit: \(error.localizedDescription)")
            }
        }

        // Update widget data
        Task { await WidgetDataService.updateSnapshot() }
    }

    static func resumeSession(_ sessionId: String) async throws {
        // Save the current endedAt as originalEndedAt before clearing,
        // so we can restore it when re-finishing instead of recalculating.
        let session = try await SessionRepository.findById(sessionId)
        let mutation = LocalMutation(table: "workout_sessions", op: "update", payload: [
            "id": sessionId,
            "ended_at": NSNull() as Any
        ])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            if let endedAt = session?.endedAt {
                let preserve = session?.originalEndedAt ?? endedAt
                try SessionRepository.setOriginalEndedAt(sessionId, preserve, in: db)
            }
            try SessionRepository.setEndedAt(sessionId, nil, in: db)
        }
        await refreshIdleAlertIfNeeded(sessionId: sessionId)
        Task { await WidgetDataService.updateSnapshot() }
    }

    static func deleteSession(_ sessionId: String) async throws {
        // Delete all sets and enqueue deletes for each
        let setIds = try await SessionSetRepository.findSetIds(sessionId: sessionId)
        let mutations = setIds.map {
            LocalMutation(table: "session_sets", op: "delete", payload: ["id": $0])
        } + [
            LocalMutation(table: "workout_sessions", op: "delete", payload: ["id": sessionId])
        ]
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            try SessionRepository.delete(sessionId, in: db)
        }
        NotificationManager.cancelIdleWorkoutNotification(sessionId: sessionId)

        // Immediately flush so the delete reaches Supabase before the app
        // is killed — prevents pullUserData from re-inserting the session.
        _ = try? await SyncService.flushQueue()
        Task { await WidgetDataService.updateSnapshot() }
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
        let mutations = sets.map {
            LocalMutation(table: "session_sets", op: "delete", payload: ["id": $0.id])
        }
        try await MutationQueueRepository.performAtomically(mutations: mutations) { db in
            for set in sets {
                try SessionSetRepository.delete(set.id, in: db)
            }
        }
    }

    // MARK: - Sets

    static func addSet(
        sessionId: String,
        exerciseId: String,
        reps requestedReps: Int? = nil,
        weight requestedWeight: Double?? = nil,
        setType requestedSetType: SetType? = nil
    ) async throws -> SessionSet {
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
        let resolvedReps = requestedReps ?? lastCompleted?.reps ?? 0
        let resolvedWeight = requestedWeight ?? lastCompleted?.weight
        let resolvedSetType = requestedSetType ?? lastCompleted?.setType ?? .normal

        let nextNumber = (existing.filter { $0.isCompleted }.count) + 1

        // If there's a placeholder, complete it in-place to preserve rowid ordering
        if let placeholder = placeholders.first {
            let patch = SetPatch(
                reps: resolvedReps,
                weight: resolvedWeight,
                isCompleted: true,
                setNumber: nextNumber,
                setType: resolvedSetType
            )
            let completedAt = try await AppDatabase.shared.dbPool.write { db in
                let completedAt = try SessionSetRepository.update(placeholder.id, patch: patch, in: db)
                if placeholder.groupId == nil, let gid = inheritedGroupId {
                    try SessionSetRepository.setGroupId(placeholder.id, groupId: gid, in: db)
                }

                var completed = placeholder
                completed.setNumber = nextNumber
                completed.reps = resolvedReps
                completed.weight = resolvedWeight
                completed.isCompleted = true
                completed.completedAt = completedAt
                completed.setType = resolvedSetType
                completed.groupId = placeholder.groupId ?? inheritedGroupId
                try MutationQueueRepository.enqueue(
                    table: "session_sets",
                    op: "update",
                    payload: setPayload(completed),
                    in: db
                )
                for extra in placeholders.dropFirst() {
                    try SessionSetRepository.delete(extra.id, in: db)
                    try MutationQueueRepository.enqueue(
                        table: "session_sets",
                        op: "delete",
                        payload: ["id": extra.id],
                        in: db
                    )
                }
                return completedAt
            }
            SyncService.flushInBackground()

            var completedSet = placeholder
            completedSet.setNumber = nextNumber
            completedSet.reps = resolvedReps
            completedSet.weight = resolvedWeight
            completedSet.isCompleted = true
            completedSet.completedAt = completedAt
            completedSet.setType = resolvedSetType
            completedSet.groupId = placeholder.groupId ?? inheritedGroupId

            await refreshIdleAlertIfNeeded(sessionId: sessionId)
            return completedSet
        }

        // No placeholders — insert a fresh set
        let id = UUID().uuidString.lowercased()
        let newSet = SessionSet(
            id: id,
            sessionId: sessionId,
            exerciseId: exerciseId,
            setNumber: nextNumber,
            reps: resolvedReps,
            weight: resolvedWeight,
            isCompleted: true,
            completedAt: Date(),
            setType: resolvedSetType,
            groupId: inheritedGroupId
        )

        let mutation = LocalMutation(
            table: "session_sets",
            op: "insert",
            payload: setPayload(newSet)
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try SessionSetRepository.insert(newSet, in: db)
        }

        await refreshIdleAlertIfNeeded(sessionId: sessionId)
        return newSet
    }

    static func addExercisesToSession(
        _ sessionId: String,
        exerciseIds: [String],
        asGroup: Bool = false
    ) async throws {
        let groupId: String? = asGroup ? UUID().uuidString.lowercased() : nil

        try await AppDatabase.shared.dbPool.write { db in
            for exerciseId in exerciseIds {
                let nextNumber = (try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM session_sets
                        WHERE session_id = ? AND exercise_id = ?
                        """,
                    arguments: [sessionId, exerciseId]
                ) ?? 0) + 1
                let placeholder = SessionSet(
                    id: UUID().uuidString.lowercased(),
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
                try SessionSetRepository.insert(placeholder, in: db)
                try MutationQueueRepository.enqueue(
                    table: "session_sets",
                    op: "insert",
                    payload: setPayload(placeholder),
                    in: db
                )
            }
        }
        SyncService.flushInBackground()
    }

    static func updateSet(_ setId: String, patch: SetPatch) async throws {
        var remote: [String: Any] = ["id": setId]
        if let reps = patch.reps { remote["reps"] = reps }
        if let weightUpdate = patch.weight {
            remote["weight"] = weightUpdate.map { $0 as Any } ?? NSNull()
        }
        if let setNumber = patch.setNumber { remote["set_number"] = setNumber }
        if let setType = patch.setType { remote["set_type"] = setType.rawValue }
        if let notes = patch.notes {
            remote["notes"] = notes.isEmpty ? NSNull() : notes as Any
        }
        let baseRemote = remote

        try await AppDatabase.shared.dbPool.write { db in
            let completedAt = try SessionSetRepository.update(setId, patch: patch, in: db)
            var queuedPayload = baseRemote
            if let isCompleted = patch.isCompleted {
                queuedPayload["is_completed"] = isCompleted
                if isCompleted, let completedAt {
                    queuedPayload["completed_at"] = ISO8601DateFormatter.shared.string(from: completedAt)
                } else if !isCompleted {
                    queuedPayload["completed_at"] = NSNull()
                }
            }
            try MutationQueueRepository.enqueue(
                table: "session_sets",
                op: "update",
                payload: queuedPayload,
                in: db
            )
        }
        SyncService.flushInBackground()

        // A completed set is the activity this alert measures. Editing an old
        // set or changing its type must not make a finished workout look active.
        if patch.isCompleted == true,
           let ownership = try? await SessionSetRepository.findOwnership(setId) {
            await refreshIdleAlertIfNeeded(sessionId: ownership.sessionId)
        }
    }

    static func deleteSet(_ setId: String) async throws {
        guard let ownership = try await SessionSetRepository.findOwnership(setId) else { return }

        try await AppDatabase.shared.dbPool.write { db in
            try SessionSetRepository.delete(setId, in: db)
            try MutationQueueRepository.enqueue(
                table: "session_sets",
                op: "delete",
                payload: ["id": setId],
                in: db
            )

            let remaining = try SessionSet
                .filter(
                    Column("session_id") == ownership.sessionId
                        && Column("exercise_id") == ownership.exerciseId
                        && Column("is_completed") == true
                )
                .order(Column("set_number").asc)
                .fetchAll(db)
            for (index, set) in remaining.enumerated() {
                let newNumber = index + 1
                guard set.setNumber != newNumber else { continue }
                try SessionSetRepository.update(
                    set.id,
                    patch: SetPatch(setNumber: newNumber),
                    in: db
                )
                try MutationQueueRepository.enqueue(
                    table: "session_sets",
                    op: "update",
                    payload: ["id": set.id, "set_number": newNumber],
                    in: db
                )
            }
        }
        SyncService.flushInBackground()
    }

    static func normalizeSetOrder(sessionId: String, exerciseId: String) async throws {
        let changed = try await AppDatabase.shared.dbPool.write { db in
            var didChange = false
            let sets = try SessionSet.fetchAll(
                db,
                sql: """
                    SELECT * FROM session_sets
                    WHERE session_id = ? AND exercise_id = ?
                    ORDER BY is_completed DESC, set_number ASC, rowid ASC
                    """,
                arguments: [sessionId, exerciseId]
            )
            for (index, set) in sets.enumerated() {
                let setNumber = index + 1
                guard set.setNumber != setNumber else { continue }
                didChange = true
                try SessionSetRepository.update(
                    set.id,
                    patch: SetPatch(setNumber: setNumber),
                    in: db
                )
                try MutationQueueRepository.enqueue(
                    table: "session_sets",
                    op: "update",
                    payload: ["id": set.id, "set_number": setNumber],
                    in: db
                )
            }
            return didChange
        }
        if changed { SyncService.flushInBackground() }
    }

    // MARK: - Exercise notes

    static func getExerciseNote(sessionId: String, exerciseId: String) async throws -> String? {
        try await SessionSetRepository.findExerciseNote(sessionId: sessionId, exerciseId: exerciseId)
    }

    static func setExerciseNote(sessionId: String, exerciseId: String, note: String?) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id FROM session_sets
                    WHERE session_id = ? AND exercise_id = ?
                    ORDER BY set_number ASC LIMIT 1
                    """,
                arguments: [sessionId, exerciseId]
            )
            guard let setId: String = row?["id"] else { return }
            try db.execute(
                sql: "UPDATE session_sets SET notes = NULL WHERE session_id = ? AND exercise_id = ?",
                arguments: [sessionId, exerciseId]
            )
            if let note, !note.isEmpty {
                try db.execute(
                    sql: "UPDATE session_sets SET notes = ? WHERE id = ?",
                    arguments: [note, setId]
                )
            }
            try MutationQueueRepository.enqueue(
                table: "session_sets",
                op: "update",
                payload: [
                    "id": setId,
                    "notes": note.map { $0 as Any } ?? NSNull()
                ],
                in: db
            )
        }
        SyncService.flushInBackground()
    }

    // MARK: - Calendar summaries

    static func getCompletedSessionDates() async throws -> Set<String> {
        guard let userId = try? authManager.requireUserId() else { return [] }
        let sessions = try await SessionRepository.findCompleted(userId: userId)
        return Set(sessions.map { toLocalDateKey($0.startedAt) })
    }

    static func getInProgressSessionDates() async throws -> Set<String> {
        guard let userId = try? authManager.requireUserId() else { return [] }
        let sessions = try await SessionRepository.findInProgress(userId: userId)
        return Set(sessions.map { toLocalDateKey($0.startedAt) })
    }

    static func getCompletedSessions(for date: Date) async throws -> [SessionSummary] {
        guard let userId = try? authManager.requireUserId() else { return [] }
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findCompleted(userId: userId)
        let onDate = sessions.filter { toLocalDateKey($0.startedAt) == key }
        return try await onDate.asyncMap { try await buildSummary($0) }
    }

    static func getInProgressSessions(for date: Date) async throws -> [SessionSummary] {
        guard let userId = try? authManager.requireUserId() else { return [] }
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findInProgress(userId: userId)
        let onDate = sessions.filter { toLocalDateKey($0.startedAt) == key }
        return try await onDate.asyncMap { try await buildSummary($0) }
    }

    static func getInProgressSessionId(for date: Date) async throws -> String? {
        guard let userId = try? authManager.requireUserId() else { return nil }
        let key = toLocalDateKey(date)
        let sessions = try await SessionRepository.findInProgress(userId: userId)
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

    private static func refreshIdleAlertIfNeeded(sessionId: String) async {
        guard let userId = authManager.currentUserId else {
            NotificationManager.cancelIdleWorkoutNotification(sessionId: sessionId)
            return
        }

        let alertsEnabled: Bool
        if let user = authManager.user, user.id == userId {
            alertsEnabled = user.settings.notifications.workoutIdleAlerts
        } else {
            alertsEnabled =
                (try? await ProfileRepository.findById(userId))?
                    .settings.notifications.workoutIdleAlerts
                ?? false
        }

        guard alertsEnabled,
              let session = try? await SessionRepository.findById(sessionId),
              session.userId == userId,
              session.endedAt == nil else {
            NotificationManager.cancelIdleWorkoutNotification(sessionId: sessionId)
            return
        }
        NotificationManager.scheduleIdleWorkoutNotification(sessionId: sessionId)
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
        payload["notes"] = set.notes.map { $0 as Any } ?? NSNull()
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
/// Thread-safe storage for the shared AuthManager reference.
/// Uses a lock to prevent data races from concurrent async contexts.
private let _authManagerLock = NSLock()
private var _authManager: AuthManager?

/// Set this once during app startup so WorkoutService can resolve the current user.
var authManager: AuthManager {
    get {
        _authManagerLock.lock()
        defer { _authManagerLock.unlock() }
        guard let m = _authManager else {
            fatalError("authManager has not been set. Call setAuthManager(_:) on app launch.")
        }
        return m
    }
}

func setAuthManager(_ manager: AuthManager) {
    _authManagerLock.lock()
    _authManager = manager
    _authManagerLock.unlock()
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
