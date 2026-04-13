import Foundation
@preconcurrency import GRDB

struct MuscleGroup: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var slug: String
}

// MARK: - GRDB conformance

extension MuscleGroup: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        slug = row["slug"]
    }
}

extension MuscleGroup: PersistableRecord {
    static var databaseTableName: String { "muscle_groups" }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["slug"] = slug
    }
}

extension MuscleGroup: TableRecord {
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
