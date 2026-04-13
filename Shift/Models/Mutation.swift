import Foundation
@preconcurrency import GRDB

// MARK: - AnyCodable

/// A simple JSON value wrapper that handles String, Int, Double, Bool, and nil.
/// Used to represent the heterogeneous payload dictionary in the mutation queue.
enum AnyCodable: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unsupported JSON value type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }

    // MARK: Convenience accessors

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - MutationOp

enum MutationOp: String, Codable {
    case insert
    case update
    case delete
}

// MARK: - Mutation

/// Decoded representation of a queued mutation.
struct Mutation: Codable {
    var table: String
    var op: MutationOp
    var payload: [String: AnyCodable]
}

// MARK: - MutationQueueRow

/// Raw row as it lives in the SQLite `mutation_queue` table.
struct MutationQueueRow: Identifiable {
    var id: Int64
    var tableName: String
    var op: String
    var payload: String // JSON-encoded Mutation payload
    var createdAt: String

    /// Decode this row back into a `Mutation`. Returns nil if the JSON is malformed.
    func decode() -> Mutation? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let wrapper = try? JSONDecoder().decode(MutationPayloadWrapper.self, from: data)
        guard let wrapper else { return nil }
        return Mutation(table: tableName, op: MutationOp(rawValue: op) ?? .insert, payload: wrapper.payload)
    }

    private struct MutationPayloadWrapper: Decodable {
        var payload: [String: AnyCodable]
    }
}

extension MutationQueueRow: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        tableName = row["table_name"]
        op = row["op"]
        payload = row["payload"]
        createdAt = row["created_at"]
    }
}

extension MutationQueueRow: PersistableRecord {
    static var databaseTableName: String { "mutation_queue" }

    func encode(to container: inout PersistenceContainer) {
        // id is INTEGER PRIMARY KEY AUTOINCREMENT — omit so SQLite assigns it
        container["table_name"] = tableName
        container["op"] = op
        container["payload"] = payload
        container["created_at"] = createdAt
    }
}

extension MutationQueueRow: TableRecord {}
