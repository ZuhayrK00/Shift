import Foundation
import Supabase

// MARK: - ProfilePatch

struct ProfilePatch {
    var name: String?
    var age: Int?
    var weight: Double?
    var profilePictureUrl: String?
    var settings: UserSettings?
}

// MARK: - ProfileService

struct ProfileService {

    // MARK: - Profile update

    /// Applies a partial patch to the current user's profile.
    /// Writes to SQLite first, then enqueues a remote update.
    @discardableResult
    static func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        let userId = try authManager.requireUserId()

        // Load existing profile from local cache or create a default.
        // Never fetch from remote here — this is the save path and must not hang on network.
        var profile: Profile
        if let cached = try await ProfileRepository.findById(userId) {
            profile = cached
        } else {
            profile = Profile(
                id: userId,
                settings: .default,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        // Apply patch
        if let name = patch.name                         { profile.name               = name  }
        if let age  = patch.age                          { profile.age                = age   }
        if let weight = patch.weight                     { profile.weight             = weight }
        if let url  = patch.profilePictureUrl            { profile.profilePictureUrl  = url   }
        if let settings = patch.settings                 { profile.settings           = settings }
        profile.updatedAt = Date()

        // Persist locally
        try await ProfileRepository.upsert(profile)

        // Build remote payload
        let settingsData = (try? JSONEncoder().encode(profile.settings)) ?? Data()
        let settingsDict = (try? JSONSerialization.jsonObject(with: settingsData)) as? [String: Any]

        var payload: [String: Any] = [
            "id": userId,
            "updated_at": ISO8601DateFormatter.shared.string(from: profile.updatedAt)
        ]
        if let name = profile.name               { payload["name"]                = name  }
        if let age  = profile.age                { payload["age"]                 = age   }
        if let weight = profile.weight           { payload["weight"]              = weight }
        if let url  = profile.profilePictureUrl  { payload["profile_picture_url"] = url   }
        if let s    = settingsDict               { payload["settings"]            = s     }

        try await MutationQueueRepository.enqueue(
            table: "profiles",
            op: "update",
            payload: payload
        )
        SyncService.flushInBackground()

        return profile
    }

    /// Convenience: update just the settings block.
    @discardableResult
    static func updateSettings(_ settings: UserSettings) async throws -> Profile {
        try await updateProfile(ProfilePatch(settings: settings))
    }

    // MARK: - Remote fetch

    /// Fetches the profile from Supabase, caches it locally, and returns it.
    /// Returns nil when no row exists yet (e.g. new sign-up before the trigger fires).
    @discardableResult
    static func fetchAndCacheProfile(_ userId: String) async throws -> Profile? {
        struct RemoteProfile: Decodable {
            var id: String
            var name: String?
            var age: Int?
            var weight: Double?
            var profilePictureUrl: String?
            var settings: UserSettings?
            var createdAt: String
            var updatedAt: String

            enum CodingKeys: String, CodingKey {
                case id, name, age, weight, settings
                case profilePictureUrl = "profile_picture_url"
                case createdAt = "created_at"
                case updatedAt = "updated_at"
            }
        }

        let response = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()

        guard let remote = try? JSONDecoder().decode(RemoteProfile.self, from: response.data) else {
            return nil
        }

        let createdAt = ISO8601DateFormatter.shared.date(from: remote.createdAt)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: remote.createdAt)
            ?? Date()
        let updatedAt = ISO8601DateFormatter.shared.date(from: remote.updatedAt)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: remote.updatedAt)
            ?? Date()

        let profile = Profile(
            id: remote.id,
            name: remote.name,
            age: remote.age,
            weight: remote.weight,
            profilePictureUrl: remote.profilePictureUrl,
            settings: remote.settings ?? .default,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await ProfileRepository.upsert(profile)
        return profile
    }

    // MARK: - Avatar upload

    /// Presents a photo picker, uploads the selected image to Supabase Storage,
    /// patches the profile with the resulting public URL, and returns that URL.
    ///
    /// This function must be called from a SwiftUI context that can present a sheet.
    /// It uses `PhotosUI` / `UIImagePickerController` bridging — the caller is
    /// expected to have already obtained image `Data` and passes it here directly.
    static func uploadProfilePicture(imageData: Data, userId: String) async throws -> String? {
        let timestamp = Int(Date().timeIntervalSince1970)
        // Supabase auth.uid()::text returns lowercase UUIDs; Swift's uuidString is uppercase.
        // The storage RLS policy compares folder name to auth.uid(), so the path must be lowercase.
        let path = "\(userId.lowercased())/\(timestamp).jpg"

        _ = try await supabase.storage
            .from("avatars")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg", upsert: true))

        let publicURL = try supabase.storage
            .from("avatars")
            .getPublicURL(path: path)

        let urlString = publicURL.absoluteString
        try await updateProfile(ProfilePatch(profilePictureUrl: urlString))
        return urlString
    }
}
