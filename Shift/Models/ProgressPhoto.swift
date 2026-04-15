import Foundation
@preconcurrency import GRDB

struct ProgressPhoto: Identifiable, Hashable, Codable {
    var id: String
    var userId: String
    var imageUrl: String
    var recordedAt: Date

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case imageUrl = "image_url"
        case recordedAt = "recorded_at"
    }

    init(id: String, userId: String, imageUrl: String, recordedAt: Date) {
        self.id = id
        self.userId = userId
        self.imageUrl = imageUrl
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        imageUrl = try container.decode(String.self, forKey: .imageUrl)
        let dateString = try container.decode(String.self, forKey: .recordedAt)
        recordedAt = ISO8601DateFormatter.shared.date(from: dateString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: dateString)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(ISO8601DateFormatter.shared.string(from: recordedAt), forKey: .recordedAt)
    }
}

// MARK: - GRDB

extension ProgressPhoto: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        imageUrl = row["image_url"]
        if let dateString: String = row["recorded_at"] {
            recordedAt = ISO8601DateFormatter.shared.date(from: dateString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: dateString)
                ?? Date()
        } else {
            recordedAt = Date()
        }
    }
}

extension ProgressPhoto: PersistableRecord {
    static var databaseTableName: String { "progress_photos" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["image_url"] = imageUrl
        container["recorded_at"] = ISO8601DateFormatter.shared.string(from: recordedAt)
    }
}

extension ProgressPhoto: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
