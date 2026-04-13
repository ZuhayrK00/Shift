import Foundation
@preconcurrency import GRDB

// MARK: - Helpers

private func decodeJSONStringArray(_ string: String?) -> [String] {
    guard let string, let data = string.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}

private func decodeJSONStringArrayOptional(_ string: String?) -> [String]? {
    guard let string, let data = string.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode([String].self, from: data)
}

private func encodeJSONStringArray(_ array: [String]) -> String {
    let data = (try? JSONEncoder().encode(array)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "[]"
}

private func encodeJSONStringArrayOptional(_ array: [String]?) -> String? {
    guard let array else { return nil }
    let data = (try? JSONEncoder().encode(array)) ?? Data()
    return String(data: data, encoding: .utf8)
}

// MARK: - Exercise

struct Exercise: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var slug: String
    var instructions: String?
    var primaryMuscleId: String
    var secondaryMuscleIds: [String]
    var equipment: String?
    var isBuiltIn: Bool
    var createdBy: String?
    var imageUrl: String?
    var secondaryImageUrl: String?
    var level: String?
    var force: String?
    var mechanic: String?
    var category: String?
    var instructionsSteps: [String]?
    var bodyPart: String?
    var description: String?

    // "exercise: equipment" or just "exercise" when equipment is nil
    var displayName: String { equipment.map { "\(name): \($0)" } ?? name }

    // MARK: Codable (Supabase JSON — booleans are real bools, arrays are real arrays)

    enum CodingKeys: String, CodingKey {
        case id, name, slug, instructions, equipment, level, force, mechanic, category, description
        case primaryMuscleId = "primary_muscle_id"
        case secondaryMuscleIds = "secondary_muscle_ids"
        case isBuiltIn = "is_built_in"
        case createdBy = "created_by"
        case imageUrl = "image_url"
        case secondaryImageUrl = "secondary_image_url"
        case instructionsSteps = "instructions_steps"
        case bodyPart = "body_part"
    }
}

// MARK: - GRDB conformance (SQLite — booleans as 0/1 Int, arrays as JSON strings)

extension Exercise: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        slug = row["slug"]
        instructions = row["instructions"]
        primaryMuscleId = row["primary_muscle_id"]
        secondaryMuscleIds = decodeJSONStringArray(row["secondary_muscle_ids"])
        equipment = row["equipment"]
        let isBuiltInInt: Int = row["is_built_in"] ?? 1
        isBuiltIn = isBuiltInInt != 0
        createdBy = row["created_by"]
        imageUrl = row["image_url"]
        secondaryImageUrl = row["secondary_image_url"]
        level = row["level"]
        force = row["force"]
        mechanic = row["mechanic"]
        category = row["category"]
        instructionsSteps = decodeJSONStringArrayOptional(row["instructions_steps"])
        bodyPart = row["body_part"]
        description = row["description"]
    }
}

extension Exercise: PersistableRecord {
    static var databaseTableName: String { "exercises" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["slug"] = slug
        container["instructions"] = instructions
        container["primary_muscle_id"] = primaryMuscleId
        container["secondary_muscle_ids"] = encodeJSONStringArray(secondaryMuscleIds)
        container["equipment"] = equipment
        container["is_built_in"] = isBuiltIn ? 1 : 0
        container["created_by"] = createdBy
        container["image_url"] = imageUrl
        container["secondary_image_url"] = secondaryImageUrl
        container["level"] = level
        container["force"] = force
        container["mechanic"] = mechanic
        container["category"] = category
        container["instructions_steps"] = encodeJSONStringArrayOptional(instructionsSteps)
        container["body_part"] = bodyPart
        container["description"] = description
    }
}

extension Exercise: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
