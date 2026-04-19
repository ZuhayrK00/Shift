import Foundation
@preconcurrency import GRDB

struct Profile: Identifiable, Hashable, Codable {
    var id: String
    var name: String?
    var age: Int?
    var weight: Double?
    var profilePictureUrl: String?
    var settings: UserSettings
    var createdAt: Date
    var updatedAt: Date

    // MARK: Codable (Supabase JSON — settings is a JSONB object)

    enum CodingKeys: String, CodingKey {
        case id, name, age, weight, settings
        case profilePictureUrl = "profile_picture_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String, name: String? = nil, age: Int? = nil, weight: Double? = nil,
         profilePictureUrl: String? = nil,
         settings: UserSettings = .default, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.age = age
        self.weight = weight
        self.profilePictureUrl = profilePictureUrl
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        profilePictureUrl = try container.decodeIfPresent(String.self, forKey: .profilePictureUrl)
        settings = (try? container.decode(UserSettings.self, forKey: .settings)) ?? .default

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
            ?? Date()

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        updatedAt = ISO8601DateFormatter.shared.date(from: updatedAtString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: updatedAtString)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(profilePictureUrl, forKey: .profilePictureUrl)
        try container.encode(settings, forKey: .settings)
        try container.encode(ISO8601DateFormatter.shared.string(from: createdAt), forKey: .createdAt)
        try container.encode(ISO8601DateFormatter.shared.string(from: updatedAt), forKey: .updatedAt)
    }
}

// MARK: - GRDB conformance (settings stored as JSON TEXT string in SQLite)

extension Profile: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        age = row["age"]
        weight = row["weight"]
        profilePictureUrl = row["profile_picture_url"]

        // settings is stored as a JSON-encoded TEXT column in SQLite
        let settingsString: String = row["settings"] ?? "{}"
        if let data = settingsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }

        if let createdAtString: String = row["created_at"] {
            createdAt = ISO8601DateFormatter.shared.date(from: createdAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: createdAtString)
                ?? Date()
        } else {
            createdAt = Date()
        }

        if let updatedAtString: String = row["updated_at"] {
            updatedAt = ISO8601DateFormatter.shared.date(from: updatedAtString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: updatedAtString)
                ?? Date()
        } else {
            updatedAt = Date()
        }
    }
}

extension Profile: PersistableRecord {
    static var databaseTableName: String { "profiles" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["age"] = age
        container["weight"] = weight
        container["profile_picture_url"] = profilePictureUrl

        // Encode settings back to JSON TEXT for SQLite
        let settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
        container["settings"] = String(data: settingsData, encoding: .utf8) ?? "{}"

        container["created_at"] = ISO8601DateFormatter.shared.string(from: createdAt)
        container["updated_at"] = ISO8601DateFormatter.shared.string(from: updatedAt)
    }
}

extension Profile: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
