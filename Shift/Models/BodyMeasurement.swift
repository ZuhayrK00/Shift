import Foundation
@preconcurrency import GRDB

// MARK: - MeasurementType

enum MeasurementType: String, CaseIterable, Codable {
    case neck
    case shoulders
    case chest
    case waist
    case hips
    case bicepLeft = "bicep_left"
    case bicepRight = "bicep_right"
    case forearmLeft = "forearm_left"
    case forearmRight = "forearm_right"
    case thighLeft = "thigh_left"
    case thighRight = "thigh_right"
    case calfLeft = "calf_left"
    case calfRight = "calf_right"

    var displayName: String {
        switch self {
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .chest: return "Chest"
        case .waist: return "Waist"
        case .hips: return "Hips"
        case .bicepLeft: return "Bicep (L)"
        case .bicepRight: return "Bicep (R)"
        case .forearmLeft: return "Forearm (L)"
        case .forearmRight: return "Forearm (R)"
        case .thighLeft: return "Thigh (L)"
        case .thighRight: return "Thigh (R)"
        case .calfLeft: return "Calf (L)"
        case .calfRight: return "Calf (R)"
        }
    }

    var icon: String {
        switch self {
        case .neck: return "person.crop.circle"
        case .shoulders: return "figure.arms.open"
        case .chest: return "heart.fill"
        case .waist: return "circle.dashed"
        case .hips: return "figure.stand"
        case .bicepLeft, .bicepRight: return "figure.strengthtraining.traditional"
        case .forearmLeft, .forearmRight: return "hand.raised.fill"
        case .thighLeft, .thighRight: return "figure.walk"
        case .calfLeft, .calfRight: return "shoeprints.fill"
        }
    }
}

// MARK: - BodyMeasurement

struct BodyMeasurement: Identifiable, Hashable, Codable {
    var id: String
    var userId: String
    var type: String
    var value: Double
    var unit: String
    var recordedAt: Date

    var measurementType: MeasurementType? {
        MeasurementType(rawValue: type)
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, type, value, unit
        case userId = "user_id"
        case recordedAt = "recorded_at"
    }

    init(id: String, userId: String, type: String, value: Double, unit: String, recordedAt: Date) {
        self.id = id
        self.userId = userId
        self.type = type
        self.value = value
        self.unit = unit
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)
        let dateString = try container.decode(String.self, forKey: .recordedAt)
        recordedAt = ISO8601DateFormatter.shared.date(from: dateString)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: dateString)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(ISO8601DateFormatter.shared.string(from: recordedAt), forKey: .recordedAt)
    }
}

// MARK: - GRDB

extension BodyMeasurement: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        userId = row["user_id"]
        type = row["type"]
        value = row["value"]
        unit = row["unit"]
        if let dateString: String = row["recorded_at"] {
            recordedAt = ISO8601DateFormatter.shared.date(from: dateString)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: dateString)
                ?? Date()
        } else {
            recordedAt = Date()
        }
    }
}

extension BodyMeasurement: PersistableRecord {
    static var databaseTableName: String { "body_measurements" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["user_id"] = userId
        container["type"] = type
        container["value"] = value
        container["unit"] = unit
        container["recorded_at"] = ISO8601DateFormatter.shared.string(from: recordedAt)
    }
}

extension BodyMeasurement: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
