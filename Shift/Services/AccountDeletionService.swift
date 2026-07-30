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

        // Supabase forbids deleting rows from storage.objects directly, including
        // from a database function. Remove owned files through the Storage API
        // while the user's authenticated session and storage RLS access still
        // exist, then let the RPC remove database rows and the Auth user.
        try await deleteRemoteStorage(userId: userId)
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

    // MARK: - Remote storage deletion

    private static func deleteRemoteStorage(userId: String) async throws {
        let userFolder = userId.lowercased()
        try await deleteAllObjects(in: "progress-photos", userFolder: userFolder)
        try await deleteAllObjects(in: "avatars", userFolder: userFolder)
    }

    /// Deletes every object in one user-owned bucket folder. Always reading the
    /// first page after a removal avoids skipping objects as the result set
    /// shrinks, while still handling accounts with more than Storage's default
    /// 100-object page.
    private static func deleteAllObjects(in bucket: String, userFolder: String) async throws {
        let pageSize = 100
        let storage = supabase.storage.from(bucket)

        while true {
            let files = try await storage.list(
                path: userFolder,
                options: SearchOptions(limit: pageSize, offset: 0)
            )
            let paths = storagePaths(
                userFolder: userFolder,
                fileNames: files.compactMap { file in
                    // Folder placeholders have no object id and cannot be
                    // removed with the file API.
                    file.id == nil ? nil : file.name
                }
            )

            guard !paths.isEmpty else { return }
            try await storage.remove(paths: paths)

            if files.count < pageSize { return }
        }
    }

    static func storagePaths(userFolder: String, fileNames: [String]) -> [String] {
        let folder = userFolder
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        guard !folder.isEmpty else { return [] }
        return fileNames.compactMap { name in
            let cleanName = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !cleanName.isEmpty, !cleanName.contains("/") else { return nil }
            return "\(folder)/\(cleanName)"
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

}
