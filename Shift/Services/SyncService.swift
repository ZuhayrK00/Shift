import Foundation
import os.log
import Supabase
@preconcurrency import GRDB

private let logger = Logger(subsystem: "com.shift.app", category: "SyncService")

private actor SyncFlushCoordinator {
    typealias Summary = (flushed: Int, failed: Int)

    private var running: Task<Summary, Error>?
    private var anotherPassRequested = false

    func flush(
        operation: @escaping @Sendable () async throws -> Summary
    ) async throws -> Summary {
        anotherPassRequested = true

        if let running {
            return try await running.value
        }

        let task = Task { try await self.drain(operation: operation) }
        running = task

        do {
            let result = try await task.value
            running = nil
            // Covers a request that arrived after the drain's final pass but
            // before the completed task was removed from this actor.
            if anotherPassRequested {
                return try await flush(operation: operation)
            }
            return result
        } catch {
            running = nil
            throw error
        }
    }

    private func drain(
        operation: @escaping @Sendable () async throws -> Summary
    ) async throws -> Summary {
        var total = Summary(flushed: 0, failed: 0)
        repeat {
            anotherPassRequested = false
            let pass = try await operation()
            total.flushed += pass.flushed
            total.failed += pass.failed
        } while anotherPassRequested
        return total
    }
}

private actor SyncRetryScheduler {
    private var scheduledTask: Task<Void, Never>?
    private var scheduledDate: Date?

    func schedule(at date: Date) {
        if let scheduledDate, scheduledDate <= date { return }
        scheduledTask?.cancel()
        scheduledDate = date
        scheduledTask = Task {
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let result = try? await SyncService.flushQueue()
            self.scheduledDate = nil
            self.scheduledTask = nil
            if let result, result.failed > 0,
               let nextDate = try? await MutationQueueRepository.nextRetryDate() {
                self.schedule(at: nextDate)
            }
        }
    }
}

// MARK: - SyncService

struct SyncService {

    private static let lastSyncedKey = "shift:last_synced_at"
    private static let flushCoordinator = SyncFlushCoordinator()
    private static let retryScheduler = SyncRetryScheduler()

    // MARK: - Queue flush

    /// Drains the local mutation queue into Supabase in FIFO order. Concurrent
    /// requests join the active drain and request another pass, so mutations
    /// enqueued during a flush cannot be stranded.
    ///
    /// - Returns: A tuple of how many mutations were flushed vs. failed.
    @discardableResult
    static func flushQueue() async throws -> (flushed: Int, failed: Int) {
        try await flushCoordinator.flush {
            try await flushPass()
        }
    }

    private static func flushPass() async throws -> (flushed: Int, failed: Int) {
        let pending = try await MutationQueueRepository.readPending()
        var flushed = 0
        var failed  = 0

        for row in pending {
            if let nextAttempt = row.nextAttemptAt.flatMap({
                ISO8601DateFormatter.shared.date(from: $0)
                    ?? ISO8601DateFormatter.sharedWithFractional.date(from: $0)
            }), nextAttempt > Date() {
                failed += 1
                break
            }
            do {
                guard let data = row.payload.data(using: .utf8),
                      let payloadDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    // Malformed row — log it before removing so data loss is diagnosable
                    logger.error("Malformed mutation payload (id=\(row.id), table=\(row.tableName), op=\(row.op)): \(row.payload)")
                    try await MutationQueueRepository.delete(rowId: row.id)
                    flushed += 1
                    continue
                }

                switch row.op {
                case "insert":
                    try await executeInsert(table: row.tableName, payload: payloadDict)

                case "update":
                    // Extract the row id from the payload; the rest goes into the SET clause
                    guard let rowId = payloadDict["id"] as? String else {
                        logger.error("Update mutation missing 'id' (id=\(row.id), table=\(row.tableName))")
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    var updatePayload = payloadDict
                    updatePayload.removeValue(forKey: "id")
                    try await executeUpdate(table: row.tableName, id: rowId, payload: updatePayload)

                case "delete":
                    guard let rowId = payloadDict["id"] as? String else {
                        logger.error("Delete mutation missing 'id' (id=\(row.id), table=\(row.tableName))")
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    try await executeDelete(table: row.tableName, id: rowId)

                default:
                    // Unknown op — log and remove to unblock
                    logger.error("Unknown mutation op '\(row.op)' (id=\(row.id), table=\(row.tableName))")
                    try await MutationQueueRepository.delete(rowId: row.id)
                    flushed += 1
                    continue
                }

                try await MutationQueueRepository.delete(rowId: row.id)
                flushed += 1

            } catch {
                failed += 1
                logger.error("Mutation flush failed (id=\(row.id), table=\(row.tableName), op=\(row.op)): \(error.localizedDescription)")
                try? await MutationQueueRepository.markFailure(
                    rowId: row.id,
                    message: error.localizedDescription,
                    attemptCount: row.attemptCount + 1
                )
                // Preserve FIFO dependencies (for example insert followed by
                // update). Later mutations must not overtake a failed row.
                break
            }
        }

        return (flushed: flushed, failed: failed)
    }

    /// Fire-and-forget queue flush for non-critical background syncs.
    static func flushInBackground() {
        Task {
            guard let result = try? await flushQueue(),
                  result.failed > 0,
                  let retryDate = try? await MutationQueueRepository.nextRetryDate()
            else { return }
            await retryScheduler.schedule(at: retryDate)
        }
    }

    // MARK: - Reference data pull

    /// Refreshes muscle groups and built-in exercises from Supabase, then caches the
    /// user profile. Records the sync timestamp in UserDefaults on success.
    ///
    /// - Returns: Counts of upserted muscle groups and exercises.
    @discardableResult
    static func pullReferenceData() async throws -> (muscleGroups: Int, exercises: Int) {
        // Flush first so any pending writes are committed before we read back
        _ = try? await flushQueue()

        // Muscle groups
        let mgResponse = try await supabase
            .from("muscle_groups")
            .select()
            .execute()

        let muscleGroups: [MuscleGroup]
        do {
            muscleGroups = try JSONDecoder().decode([MuscleGroup].self, from: mgResponse.data)
        } catch {
            logger.error("Failed to decode muscle groups: \(error.localizedDescription)")
            throw error
        }
        for mg in muscleGroups {
            try await MuscleGroupRepository.upsert(mg)
        }

        // Exercises
        let exResponse = try await supabase
            .from("exercises")
            .select()
            .eq("is_built_in", value: true)
            .execute()

        let decoder = JSONDecoder()
        let exercises: [Exercise]
        do {
            exercises = try decoder.decode([Exercise].self, from: exResponse.data)
        } catch {
            logger.error("Failed to decode exercises: \(error.localizedDescription)")
            throw error
        }
        try await ExerciseRepository.replaceBuiltIn(exercises)

        // Cache profile — but only if there are no pending profile mutations
        if let userId = authManager.currentUserId {
            let pendingIds = (try? await MutationQueueRepository.pendingMutationIds()) ?? []
            if !pendingIds.contains(userId) {
                _ = try? await ProfileService.fetchAndCacheProfile(userId)
            }
        }

        // Record sync timestamp
        UserDefaults.standard.set(
            ISO8601DateFormatter.shared.string(from: Date()),
            forKey: lastSyncedKey
        )

        return (muscleGroups: muscleGroups.count, exercises: exercises.count)
    }

    // MARK: - Full user data pull

    /// Pulls all user-owned data from Supabase into the local database.
    /// Called on sign-in so the user always has their full history locally.
    /// Uses upsert (replace) so it's safe to call multiple times.
    static func pullUserData() async throws {
        guard let userId = authManager.currentUserId else { return }

        // Flush pending local writes first so nothing is lost
        _ = try? await flushQueue()

        // Collect IDs that still have pending mutations (failed to flush).
        // We must not overwrite these — they have unsaved local changes.
        let pendingIds = (try? await MutationQueueRepository.pendingMutationIds()) ?? []

        let decoder = JSONDecoder()

        // 1. Custom exercises (created by this user)
        let customExData = try await supabase
            .from("exercises")
            .select()
            .eq("created_by", value: userId)
            .execute()
        let customExercises: [Exercise]
        do { customExercises = try decoder.decode([Exercise].self, from: customExData.data) }
        catch { logger.error("Failed to decode custom exercises: \(error.localizedDescription)"); throw error }
        for ex in customExercises where !pendingIds.contains(ex.id) {
            try? await ExerciseRepository.upsert(ex)
        }
        try await AppDatabase.shared.dbPool.write { db in
            try deleteMissingRows(
                table: "exercises",
                scope: "created_by = ? AND is_built_in = 0",
                scopeArguments: [userId],
                remoteIds: Set(customExercises.map(\.id)),
                pendingIds: pendingIds,
                in: db
            )
        }

        // 2. Workout plans
        let plansData = try await supabase
            .from("workout_plans")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let plans: [WorkoutPlan]
        do { plans = try decoder.decode([WorkoutPlan].self, from: plansData.data) }
        catch { logger.error("Failed to decode workout plans: \(error.localizedDescription)"); throw error }
        let activePlans = plans.filter { !pendingIds.contains($0.id) }
        try await AppDatabase.shared.dbPool.write { db in
            for plan in activePlans { try plan.save(db) }
            try deleteMissingRows(
                table: "workout_plans",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(plans.map(\.id)),
                pendingIds: pendingIds,
                childDeleteSQL: "DELETE FROM plan_exercises WHERE plan_id = ?",
                in: db
            )
        }

        // 3. Plan exercises (for all plans)
        if !activePlans.isEmpty {
            let planIds = activePlans.map { $0.id }
            let peData = try await supabase
                .from("plan_exercises")
                .select()
                .in("plan_id", values: planIds)
                .execute()
            let planExercises: [PlanExercise]
            do { planExercises = try decoder.decode([PlanExercise].self, from: peData.data) }
            catch { logger.error("Failed to decode plan exercises: \(error.localizedDescription)"); throw error }
            try await AppDatabase.shared.dbPool.write { db in
                for pe in planExercises where !pendingIds.contains(pe.id) {
                    try pe.save(db)
                }
                let planIds = activePlans.map(\.id)
                try deleteMissingRows(
                    table: "plan_exercises",
                    scope: "plan_id IN (\(sqlPlaceholders(planIds.count)))",
                    scopeArguments: planIds,
                    remoteIds: Set(planExercises.map(\.id)),
                    pendingIds: pendingIds,
                    in: db
                )
            }
        }

        // 4. Workout sessions
        let sessionsData = try await supabase
            .from("workout_sessions")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let sessions: [WorkoutSession]
        do { sessions = try decoder.decode([WorkoutSession].self, from: sessionsData.data) }
        catch { logger.error("Failed to decode workout sessions: \(error.localizedDescription)"); throw error }
        let activeSessions = sessions.filter { !pendingIds.contains($0.id) }
        try await AppDatabase.shared.dbPool.write { db in
            for session in activeSessions { try session.save(db) }
            try deleteMissingRows(
                table: "workout_sessions",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(sessions.map(\.id)),
                pendingIds: pendingIds,
                childDeleteSQL: "DELETE FROM session_sets WHERE session_id = ?",
                in: db
            )
        }

        // 5. Session sets (for all sessions)
        if !activeSessions.isEmpty {
            // Pull in batches to avoid overly large queries
            let sessionIds = activeSessions.map { $0.id }
            let batchSize = 50
            var remoteSetIds = Set<String>()
            for batch in stride(from: 0, to: sessionIds.count, by: batchSize) {
                let batchIds = Array(sessionIds[batch..<min(batch + batchSize, sessionIds.count)])
                let setsData = try await supabase
                    .from("session_sets")
                    .select()
                    .in("session_id", values: batchIds)
                    .execute()
                let sets: [SessionSet]
                do { sets = try decoder.decode([SessionSet].self, from: setsData.data) }
                catch { logger.error("Failed to decode session sets: \(error.localizedDescription)"); throw error }
                remoteSetIds.formUnion(sets.map(\.id))
                try await AppDatabase.shared.dbPool.write { db in
                    for s in sets where !pendingIds.contains(s.id) {
                        try s.save(db)
                    }
                }
            }
            let completeRemoteSetIds = remoteSetIds
            try await AppDatabase.shared.dbPool.write { db in
                try deleteMissingRows(
                    table: "session_sets",
                    scope: "session_id IN (\(sqlPlaceholders(sessionIds.count)))",
                    scopeArguments: sessionIds,
                    remoteIds: completeRemoteSetIds,
                    pendingIds: pendingIds,
                    in: db
                )
            }
        }

        // 6. Exercise goals
        let goalsData = try await supabase
            .from("exercise_goals")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let goals: [ExerciseGoal]
        do { goals = try decoder.decode([ExerciseGoal].self, from: goalsData.data) }
        catch { logger.error("Failed to decode exercise goals: \(error.localizedDescription)"); throw error }
        try await AppDatabase.shared.dbPool.write { db in
            for goal in goals where !pendingIds.contains(goal.id) {
                try goal.save(db)
            }
            try deleteMissingRows(
                table: "exercise_goals",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(goals.map(\.id)),
                pendingIds: pendingIds,
                in: db
            )
        }

        // 7. Weight entries
        let weightData = try await supabase
            .from("weight_entries")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let weightEntries: [WeightEntry]
        do { weightEntries = try decoder.decode([WeightEntry].self, from: weightData.data) }
        catch { logger.error("Failed to decode weight entries: \(error.localizedDescription)"); throw error }
        try await AppDatabase.shared.dbPool.write { db in
            for entry in weightEntries where !pendingIds.contains(entry.id) {
                try entry.save(db)
            }
            try deleteMissingRows(
                table: "weight_entries",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(weightEntries.map(\.id)),
                pendingIds: pendingIds,
                in: db
            )
        }

        // 8. Body measurements
        let measurementsData = try await supabase
            .from("body_measurements")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let measurements: [BodyMeasurement]
        do { measurements = try decoder.decode([BodyMeasurement].self, from: measurementsData.data) }
        catch { logger.error("Failed to decode body measurements: \(error.localizedDescription)"); throw error }
        try await AppDatabase.shared.dbPool.write { db in
            for m in measurements where !pendingIds.contains(m.id) {
                try m.save(db)
            }
            try deleteMissingRows(
                table: "body_measurements",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(measurements.map(\.id)),
                pendingIds: pendingIds,
                in: db
            )
        }

        // 9. Progress photos
        let photosData = try await supabase
            .from("progress_photos")
            .select()
            .eq("user_id", value: userId)
            .execute()
        let progressPhotos: [ProgressPhoto]
        do { progressPhotos = try decoder.decode([ProgressPhoto].self, from: photosData.data) }
        catch { logger.error("Failed to decode progress photos: \(error.localizedDescription)"); throw error }
        try await AppDatabase.shared.dbPool.write { db in
            for p in progressPhotos where !pendingIds.contains(p.id) {
                try p.save(db)
            }
            try deleteMissingRows(
                table: "progress_photos",
                scope: "user_id = ?",
                scopeArguments: [userId],
                remoteIds: Set(progressPhotos.map(\.id)),
                pendingIds: pendingIds,
                in: db
            )
        }

        UserDefaults.standard.set(
            ISO8601DateFormatter.shared.string(from: Date()),
            forKey: userLastSyncedKey(userId)
        )
    }

    // MARK: - Last synced

    static func getLastSyncedAt() -> Date? {
        guard let raw = UserDefaults.standard.string(forKey: lastSyncedKey) else { return nil }
        return ISO8601DateFormatter.shared.date(from: raw)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: raw)
    }

    static func shouldPullReferenceData(maxAge: TimeInterval = 6 * 3_600) -> Bool {
        guard let lastSync = getLastSyncedAt() else { return true }
        return Date().timeIntervalSince(lastSync) >= maxAge
    }

    static func shouldPullUserData(maxAge: TimeInterval = 5 * 60) -> Bool {
        guard let userId = authManager.currentUserId,
              let raw = UserDefaults.standard.string(forKey: userLastSyncedKey(userId)),
              let date = ISO8601DateFormatter.shared.date(from: raw)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: raw)
        else { return true }
        return Date().timeIntervalSince(date) >= maxAge
    }

    private static func userLastSyncedKey(_ userId: String) -> String {
        "shift:user_last_synced_at:\(userId)"
    }

    // MARK: - Private Supabase helpers

    private static func executeInsert(table: String, payload: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonValue = try? JSONDecoder().decode(AnyJSON.self, from: jsonData) else {
            throw SyncError.encodingFailed
        }
        // Use upsert for all tables so replayed mutations are idempotent
        try await supabase
            .from(table)
            .upsert(jsonValue)
            .execute()
    }

    private static func sqlPlaceholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    /// Removes locally cached rows that are absent from a complete remote snapshot,
    /// while preserving records that still have an outbound local mutation.
    private static func deleteMissingRows(
        table: String,
        scope: String,
        scopeArguments: [String],
        remoteIds: Set<String>,
        pendingIds: Set<String>,
        childDeleteSQL: String? = nil,
        in db: Database
    ) throws {
        // PostgREST projects commonly cap a response at 1,000 rows. At that
        // boundary we cannot prove the snapshot is complete, so never reconcile
        // deletions from it. Upserts still proceed and a later paginated sync can
        // safely reconcile the remainder.
        guard remoteIds.count < 1_000 else { return }
        let keepIds = remoteIds.union(pendingIds)
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id FROM \(table) WHERE \(scope)",
            arguments: StatementArguments(scopeArguments)
        )
        let idsToDelete: [String] = rows.compactMap { row in
            let id: String = row["id"]
            return keepIds.contains(id) ? nil : id
        }
        for id in idsToDelete {
            if let childDeleteSQL {
                try db.execute(sql: childDeleteSQL, arguments: [id])
            }
            try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
        }
    }

    private static func executeUpdate(table: String, id: String, payload: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonValue = try? JSONDecoder().decode(AnyJSON.self, from: jsonData) else {
            throw SyncError.encodingFailed
        }
        // Use upsert for profiles to handle the case where the row doesn't exist yet
        if table == "profiles" {
            var fullPayload = payload
            fullPayload["id"] = id
            let upsertData = try JSONSerialization.data(withJSONObject: fullPayload)
            guard let upsertValue = try? JSONDecoder().decode(AnyJSON.self, from: upsertData) else {
                throw SyncError.encodingFailed
            }
            try await supabase
                .from(table)
                .upsert(upsertValue)
                .execute()
        } else {
            try await supabase
                .from(table)
                .update(jsonValue)
                .eq("id", value: id)
                .execute()
        }
    }

    private static func executeDelete(table: String, id: String) async throws {
        try await supabase
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

// MARK: - SyncError

enum SyncError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode mutation payload for Supabase."
        }
    }
}
