import Foundation
import Supabase
@preconcurrency import GRDB

// MARK: - SyncService

struct SyncService {

    private static let lastSyncedKey = "shift:last_synced_at"

    /// Prevents concurrent flush calls from double-processing the same mutations.
    private static let flushLock = NSLock()
    private static var isFlushing = false

    // MARK: - Queue flush

    /// Drains the local mutation queue into Supabase in FIFO order.
    /// Stops processing on the first failure so ordering is preserved.
    /// Serialized — concurrent calls return immediately if a flush is already in progress.
    ///
    /// - Returns: A tuple of how many mutations were flushed vs. failed.
    @discardableResult
    static func flushQueue() async throws -> (flushed: Int, failed: Int) {
        // Skip if another flush is already running
        let acquired: Bool = flushLock.withLock {
            guard !isFlushing else { return false }
            isFlushing = true
            return true
        }
        guard acquired else { return (flushed: 0, failed: 0) }
        defer { flushLock.withLock { isFlushing = false } }

        let pending = try await MutationQueueRepository.readPending()
        var flushed = 0
        var failed  = 0

        for row in pending {
            do {
                guard let data = row.payload.data(using: .utf8),
                      let payloadDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    // Malformed row — remove it so it doesn't block the queue
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
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    var updatePayload = payloadDict
                    updatePayload.removeValue(forKey: "id")
                    try await executeUpdate(table: row.tableName, id: rowId, payload: updatePayload)

                case "delete":
                    guard let rowId = payloadDict["id"] as? String else {
                        try await MutationQueueRepository.delete(rowId: row.id)
                        flushed += 1
                        continue
                    }
                    try await executeDelete(table: row.tableName, id: rowId)

                default:
                    // Unknown op — remove to unblock
                    try await MutationQueueRepository.delete(rowId: row.id)
                    flushed += 1
                    continue
                }

                try await MutationQueueRepository.delete(rowId: row.id)
                flushed += 1

            } catch {
                failed += 1
                // Stop processing on error to preserve mutation ordering
                break
            }
        }

        return (flushed: flushed, failed: failed)
    }

    /// Fire-and-forget queue flush for non-critical background syncs.
    static func flushInBackground() {
        Task { try? await flushQueue() }
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

        let muscleGroups = (try? JSONDecoder().decode([MuscleGroup].self, from: mgResponse.data)) ?? []
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
        let exercises = (try? decoder.decode([Exercise].self, from: exResponse.data)) ?? []
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
        let customExercises = (try? decoder.decode([Exercise].self, from: customExData.data)) ?? []
        for ex in customExercises where !pendingIds.contains(ex.id) {
            try? await ExerciseRepository.upsert(ex)
        }

        // 2. Workout plans
        let plansData = try await supabase
            .from("workout_plans")
            .select()
            .execute()
        let plans = (try? decoder.decode([WorkoutPlan].self, from: plansData.data)) ?? []
        let activePlans = plans.filter { !pendingIds.contains($0.id) }
        try await AppDatabase.shared.dbPool.write { db in
            for plan in activePlans { try plan.save(db) }
        }

        // 3. Plan exercises (for all plans)
        if !activePlans.isEmpty {
            let planIds = activePlans.map { $0.id }
            let peData = try await supabase
                .from("plan_exercises")
                .select()
                .in("plan_id", values: planIds)
                .execute()
            let planExercises = (try? decoder.decode([PlanExercise].self, from: peData.data)) ?? []
            try await AppDatabase.shared.dbPool.write { db in
                for pe in planExercises where !pendingIds.contains(pe.id) {
                    try pe.save(db)
                }
            }
        }

        // 4. Workout sessions
        let sessionsData = try await supabase
            .from("workout_sessions")
            .select()
            .execute()
        let sessions = (try? decoder.decode([WorkoutSession].self, from: sessionsData.data)) ?? []
        let activeSessions = sessions.filter { !pendingIds.contains($0.id) }
        try await AppDatabase.shared.dbPool.write { db in
            for session in activeSessions { try session.save(db) }
        }

        // 5. Session sets (for all sessions)
        if !activeSessions.isEmpty {
            // Pull in batches to avoid overly large queries
            let sessionIds = activeSessions.map { $0.id }
            let batchSize = 50
            for batch in stride(from: 0, to: sessionIds.count, by: batchSize) {
                let batchIds = Array(sessionIds[batch..<min(batch + batchSize, sessionIds.count)])
                let setsData = try await supabase
                    .from("session_sets")
                    .select()
                    .in("session_id", values: batchIds)
                    .execute()
                let sets = (try? decoder.decode([SessionSet].self, from: setsData.data)) ?? []
                try await AppDatabase.shared.dbPool.write { db in
                    for s in sets where !pendingIds.contains(s.id) {
                        try s.save(db)
                    }
                }
            }
        }

        // 6. Exercise goals
        let goalsData = try await supabase
            .from("exercise_goals")
            .select()
            .execute()
        let goals = (try? decoder.decode([ExerciseGoal].self, from: goalsData.data)) ?? []
        try await AppDatabase.shared.dbPool.write { db in
            for goal in goals where !pendingIds.contains(goal.id) {
                try goal.save(db)
            }
        }

        // 7. Weight entries
        let weightData = try await supabase
            .from("weight_entries")
            .select()
            .execute()
        let weightEntries = (try? decoder.decode([WeightEntry].self, from: weightData.data)) ?? []
        try await AppDatabase.shared.dbPool.write { db in
            for entry in weightEntries where !pendingIds.contains(entry.id) {
                try entry.save(db)
            }
        }
    }

    // MARK: - Last synced

    static func getLastSyncedAt() -> Date? {
        guard let raw = UserDefaults.standard.string(forKey: lastSyncedKey) else { return nil }
        return ISO8601DateFormatter.shared.date(from: raw)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: raw)
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
