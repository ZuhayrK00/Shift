import Foundation
import Supabase
@preconcurrency import GRDB

// MARK: - AccountDeletionService

/// Handles full account deletion — removes all user data from both
/// Supabase (remote) and the local SQLite database, then signs out.
struct AccountDeletionService {

    /// Deletes all data associated with the current user from remote and local storage.
    /// After this completes, the user is signed out.
    static func deleteAccount() async throws {
        let userId = try authManager.requireUserId()

        // Account deletion intentionally discards this user's pending writes.
        // Scope the cleanup so another account's queue is never affected.
        try await MutationQueueRepository.clear(for: userId)

        // The security-definer function deletes the Auth user, owned storage
        // objects, and every dependent database row in one server transaction.
        // Keep this operation in a versioned migration rather than relying on a
        // sequence of best-effort client requests.
        try await supabase.rpc("delete_own_account").execute()

        do {
            try await deleteLocalData(userId: userId)
            try await MutationQueueRepository.clear(for: userId)
        } catch {
            // The server account no longer exists. Never leave its invalid
            // session active even if local cleanup reports an error.
            try? await authManager.signOut()
            throw error
        }

        // Clear the now-invalid local Auth session.
        try await authManager.signOut()
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

}
