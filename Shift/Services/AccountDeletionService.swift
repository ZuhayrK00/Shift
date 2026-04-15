import Foundation
import os.log
import Supabase
@preconcurrency import GRDB

private let logger = Logger(subsystem: "com.shift.app", category: "AccountDeletion")

// MARK: - AccountDeletionService

/// Handles full account deletion — removes all user data from both
/// Supabase (remote) and the local SQLite database, then signs out.
struct AccountDeletionService {

    /// Deletes all data associated with the current user from remote and local storage.
    /// After this completes, the user is signed out.
    static func deleteAccount() async throws {
        let userId = try authManager.requireUserId()

        // 1. Clear the mutation queue first so nothing re-syncs after we delete
        try await clearMutationQueue()

        // 2. Delete from Supabase (remote) — order matters for foreign key constraints
        await deleteRemoteData(userId: userId)

        // 3. Delete from Supabase Storage (avatars + progress photos)
        await deleteStorageFiles(userId: userId)

        // 4. Delete from local SQLite
        try await deleteLocalData(userId: userId)

        // 5. Delete the Supabase Auth user via RPC
        _ = try? await supabase.rpc("delete_own_account").execute()

        // 6. Sign out
        try await authManager.signOut()
    }

    // MARK: - Remote deletion

    private static func deleteRemoteData(userId: String) async {
        // Delete in dependency order: children first, then parents

        // Session sets (child of sessions)
        do {
            // Get all session IDs for this user first
            let sessionsResponse = try await supabase
                .from("workout_sessions")
                .select("id")
                .eq("user_id", value: userId)
                .execute()

            struct IdRow: Decodable { let id: String }
            if let sessionIds = try? JSONDecoder().decode([IdRow].self, from: sessionsResponse.data) {
                let ids = sessionIds.map { $0.id }
                // Delete in batches
                for batch in stride(from: 0, to: ids.count, by: 50) {
                    let batchIds = Array(ids[batch..<min(batch + 50, ids.count)])
                    try await supabase
                        .from("session_sets")
                        .delete()
                        .in("session_id", values: batchIds)
                        .execute()
                }
            }
        } catch {
            logger.error("Failed to delete remote session_sets: \(error.localizedDescription)")
        }

        // Workout sessions
        do {
            try await supabase
                .from("workout_sessions")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote workout_sessions: \(error.localizedDescription)")
        }

        // Plan exercises (child of plans)
        do {
            let plansResponse = try await supabase
                .from("workout_plans")
                .select("id")
                .eq("user_id", value: userId)
                .execute()

            struct IdRow: Decodable { let id: String }
            if let planIds = try? JSONDecoder().decode([IdRow].self, from: plansResponse.data) {
                let ids = planIds.map { $0.id }
                for batch in stride(from: 0, to: ids.count, by: 50) {
                    let batchIds = Array(ids[batch..<min(batch + 50, ids.count)])
                    try await supabase
                        .from("plan_exercises")
                        .delete()
                        .in("plan_id", values: batchIds)
                        .execute()
                }
            }
        } catch {
            logger.error("Failed to delete remote plan_exercises: \(error.localizedDescription)")
        }

        // Workout plans
        do {
            try await supabase
                .from("workout_plans")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote workout_plans: \(error.localizedDescription)")
        }

        // Exercise goals
        do {
            try await supabase
                .from("exercise_goals")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote exercise_goals: \(error.localizedDescription)")
        }

        // Custom exercises
        do {
            try await supabase
                .from("exercises")
                .delete()
                .eq("created_by", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote custom exercises: \(error.localizedDescription)")
        }

        // Weight entries
        do {
            try await supabase
                .from("weight_entries")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote weight_entries: \(error.localizedDescription)")
        }

        // Body measurements
        do {
            try await supabase
                .from("body_measurements")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote body_measurements: \(error.localizedDescription)")
        }

        // Progress photos
        do {
            try await supabase
                .from("progress_photos")
                .delete()
                .eq("user_id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote progress_photos: \(error.localizedDescription)")
        }

        // Profile (last — it's the parent row)
        do {
            try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: userId)
                .execute()
        } catch {
            logger.error("Failed to delete remote profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Storage deletion

    private static func deleteStorageFiles(userId: String) async {
        let folder = userId.lowercased()

        // Delete avatar files
        do {
            let avatarFiles = try await supabase.storage
                .from("avatars")
                .list(path: folder)
            if !avatarFiles.isEmpty {
                let paths = avatarFiles.map { "\(folder)/\($0.name)" }
                try await supabase.storage
                    .from("avatars")
                    .remove(paths: paths)
            }
        } catch {
            logger.error("Failed to delete avatar storage: \(error.localizedDescription)")
        }

        // Delete progress photo files
        do {
            let photoFiles = try await supabase.storage
                .from("progress-photos")
                .list(path: folder)
            if !photoFiles.isEmpty {
                let paths = photoFiles.map { "\(folder)/\($0.name)" }
                try await supabase.storage
                    .from("progress-photos")
                    .remove(paths: paths)
            }
        } catch {
            logger.error("Failed to delete progress photo storage: \(error.localizedDescription)")
        }
    }

    // MARK: - Local deletion

    private static func deleteLocalData(userId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            // Session sets for this user's sessions
            try db.execute(sql: """
                DELETE FROM session_sets WHERE session_id IN (
                    SELECT id FROM workout_sessions WHERE user_id = ?
                )
            """, arguments: [userId])

            // Workout sessions
            try db.execute(sql: "DELETE FROM workout_sessions WHERE user_id = ?", arguments: [userId])

            // Plan exercises for this user's plans
            try db.execute(sql: """
                DELETE FROM plan_exercises WHERE plan_id IN (
                    SELECT id FROM workout_plans WHERE user_id = ?
                )
            """, arguments: [userId])

            // Workout plans
            try db.execute(sql: "DELETE FROM workout_plans WHERE user_id = ?", arguments: [userId])

            // Exercise goals
            try db.execute(sql: "DELETE FROM exercise_goals WHERE user_id = ?", arguments: [userId])

            // Custom exercises
            try db.execute(sql: "DELETE FROM exercises WHERE created_by = ?", arguments: [userId])

            // Weight entries
            try db.execute(sql: "DELETE FROM weight_entries WHERE user_id = ?", arguments: [userId])

            // Body measurements
            try db.execute(sql: "DELETE FROM body_measurements WHERE user_id = ?", arguments: [userId])

            // Progress photos
            try db.execute(sql: "DELETE FROM progress_photos WHERE user_id = ?", arguments: [userId])

            // Profile
            try db.execute(sql: "DELETE FROM profiles WHERE id = ?", arguments: [userId])
        }
    }

    // MARK: - Queue cleanup

    private static func clearMutationQueue() async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM mutation_queue")
        }
    }
}
