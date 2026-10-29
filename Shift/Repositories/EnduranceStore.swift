import Foundation
@preconcurrency import GRDB

enum EnduranceCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601DateFormatter.shared.date(from: value)
                ?? ISO8601DateFormatter.sharedWithFractional.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid endurance timestamp"))
            }
            return date
        }
        return decoder
    }
}

struct EnduranceEnvelope<T: EnduranceEntity>: Codable, Sendable {
    var id: String
    var user_id: String
    var details: T
    init(_ record: T) { id = record.id; user_id = record.userId; details = record }
}

/// Owner-scoped SQLite records and durable outbound writes commit together.
struct EnduranceStore: @unchecked Sendable {
    let database: AppDatabase
    static var shared: EnduranceStore { .init(database: .shared) }

    func all<T: EnduranceEntity>(_ type: T.Type, userID: String) async throws -> [T] {
        try await database.dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT details FROM \(T.table) WHERE user_id = ? ORDER BY sort_date DESC", arguments: [userID])
                .map { try EnduranceCoding.decoder().decode(T.self, from: Data($0.utf8)) }
        }
    }

    func save<T: EnduranceEntity>(_ record: T, finishingDraft: Bool = false) async throws {
        guard record.isValid else { throw EnduranceError.invalidActivity }
        let data = try EnduranceCoding.encoder().encode(record)
        let payload = try EnduranceCoding.encoder().encode(EnduranceEnvelope(record))
        try await database.dbPool.write { db in
            try Self.upsert(record, data: data, in: db)
            try Self.enqueue(table: T.table, op: "insert", id: record.id, userID: record.userId, payload: payload, in: db)
            if finishingDraft {
                try db.execute(sql: "DELETE FROM endurance_recordings WHERE user_id = ? AND id = ?", arguments: [record.userId, record.id])
            }
        }
    }

    /// Receipt and activity commit together. A later retry must not resurrect
    /// an activity the user deleted after its first successful Watch delivery.
    func receiveWatchActivity(_ activity: EnduranceActivity) async throws {
        guard activity.isValid else { throw EnduranceError.invalidActivity }
        try await database.dbPool.write { db in
            let received = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM watch_endurance_receipts WHERE id = ? AND user_id = ?)", arguments: [activity.id, activity.userId]) ?? false
            let oldJSON = try String.fetchOne(db, sql: "SELECT details FROM endurance_activities WHERE id = ? AND user_id = ?", arguments: [activity.id, activity.userId])
            guard !received || oldJSON != nil else { throw EnduranceError.deletedActivity }
            var record = activity
            if received, let oldJSON {
                record = try EnduranceCoding.decoder().decode(EnduranceActivity.self, from: Data(oldJSON.utf8))
                record.healthKitID = record.healthKitID ?? activity.healthKitID
            }
            try Self.upsert(record, in: db)
            try Self.enqueue(table: EnduranceActivity.table, op: "insert", id: record.id, userID: record.userId,
                payload: EnduranceCoding.encoder().encode(EnduranceEnvelope(record)), in: db)
            try db.execute(sql: "INSERT OR IGNORE INTO watch_endurance_receipts (id, user_id) VALUES (?, ?)", arguments: [record.id, record.userId])
        }
    }

    func saveAll<T: EnduranceEntity>(_ records: [T]) async throws {
        guard records.allSatisfy(\.isValid) else { throw EnduranceError.invalidActivity }
        try await database.dbPool.write { db in
            for record in records {
                try Self.upsert(record, in: db)
                try Self.enqueue(table: T.table, op: "insert", id: record.id, userID: record.userId,
                    payload: EnduranceCoding.encoder().encode(EnduranceEnvelope(record)), in: db)
            }
        }
    }

    func delete<T: EnduranceEntity>(_ record: T) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["id": record.id, "user_id": record.userId])
        try await database.dbPool.write { db in
            try db.execute(sql: "DELETE FROM \(T.table) WHERE id = ? AND user_id = ?", arguments: [record.id, record.userId])
            try Self.enqueue(table: T.table, op: "delete", id: record.id, userID: record.userId, payload: payload, in: db)
        }
    }

    func saveDraft(_ draft: EnduranceDraft) async throws {
        let json = String(decoding: try EnduranceCoding.encoder().encode(draft), as: UTF8.self)
        try await database.dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO endurance_recordings (id, user_id, details) VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET id = excluded.id, details = excluded.details
                """, arguments: [draft.id, draft.userId, json])
        }
    }

    func draft(userID: String) async throws -> EnduranceDraft? {
        try await database.dbPool.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT details FROM endurance_recordings WHERE user_id = ?", arguments: [userID]) else { return nil }
            return try EnduranceCoding.decoder().decode(EnduranceDraft.self, from: Data(json.utf8))
        }
    }

    func deleteDraft(userID: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "DELETE FROM endurance_recordings WHERE user_id = ?", arguments: [userID])
        }
    }

    static func upsert<T: EnduranceEntity>(_ record: T, data: Data? = nil, in db: Database) throws {
        if let owner = try String.fetchOne(db, sql: "SELECT user_id FROM \(T.table) WHERE id = ?", arguments: [record.id]), owner != record.userId {
            throw EnduranceError.wrongAccount
        }
        let encoded = try data ?? EnduranceCoding.encoder().encode(record)
        try db.execute(sql: """
            INSERT INTO \(T.table) (id, user_id, details, sort_date) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET details = excluded.details, sort_date = excluded.sort_date
            WHERE \(T.table).user_id = excluded.user_id
            """, arguments: [record.id, record.userId, String(decoding: encoded, as: UTF8.self), record.sortDate.timeIntervalSince1970])
    }

    private static func enqueue(table: String, op: String, id: String, userID: String, payload: Data, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO mutation_queue (table_name, op, payload, created_at, user_id, attempt_count)
            VALUES (?, ?, ?, ?, ?, 0)
            """, arguments: [table, op, String(decoding: payload, as: UTF8.self), ISO8601DateFormatter.shared.string(from: Date()), userID])
    }
}

enum EnduranceError: LocalizedError {
    case invalidActivity, invalidGoal, wrongAccount, unavailable, locationDenied, waitingForGPS, deletedActivity
    var errorDescription: String? {
        switch self {
        case .deletedActivity: return "This Watch activity was already received and then deleted."
        case .invalidActivity: return "This activity could not be saved. Check the title and recording, then try again."
        case .invalidGoal: return "Enter a positive target and a future deadline. Activity counts must be whole numbers."
        case .wrongAccount: return "Sign in to the account that owns this activity."
        case .unavailable: return "Apple Health is not available on this device."
        case .locationDenied: return "Allow precise location for Shift in Settings to record your route."
        case .waitingForGPS: return "Wait for an accurate GPS location before starting. Try moving outdoors."
        }
    }
}

@MainActor
enum EnduranceService {
    static func save(_ activity: EnduranceActivity, finishingDraft: Bool = false, fromWatch: Bool = false) async throws {
        var activity = activity
        guard activity.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        guard activity.isValid else { throw EnduranceError.invalidActivity }
        let before = try? await EnduranceStore.shared.all(EnduranceActivity.self, userID: activity.userId)
        if activity.trainingSessionID == nil {
            if let previous = before?.first(where: { $0.id == activity.id }) { activity.trainingSessionID = previous.trainingSessionID; activity.savedRouteID = activity.savedRouteID ?? previous.savedRouteID }
            else if let planned = try? await EnduranceStore.shared.all(TrainingSession.self, userID: activity.userId) {
                activity.trainingSessionID = TrainingLinkPolicy.candidate(sessions: planned, userID: activity.userId, kind: .endurance,
                    sport: activity.sport, date: activity.startedAt, excluding: Set((before ?? []).compactMap(\.trainingSessionID)))
            }
        }
        if fromWatch { try await EnduranceStore.shared.receiveWatchActivity(activity) }
        else { try await EnduranceStore.shared.save(activity, finishingDraft: finishingDraft) }
        if let before { await TrainingNotificationService.activitySaved(activity, before: before) }
        await TrainingNotificationService.reconcile()
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
    }
    static func save(_ goal: EnduranceGoal) async throws {
        guard goal.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        guard goal.isValid else { throw EnduranceError.invalidGoal }
        try await EnduranceStore.shared.save(goal)
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await refreshSummaries()
    }
    static func save<T: EnduranceEntity>(_ record: T) async throws {
        guard record.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        try await EnduranceStore.shared.save(record)
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await TrainingNotificationService.reconcile()
        await refreshSummaries()
    }
    static func schedule(_ records: [TrainingSession]) async throws {
        let owner = try authManager.requireUserId()
        guard records.allSatisfy({ $0.userId == owner }) else { throw EnduranceError.wrongAccount }
        try await EnduranceStore.shared.saveAll(records)
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await TrainingNotificationService.reconcile()
        await refreshSummaries()
    }
    static func delete<T: EnduranceEntity>(_ record: T) async throws {
        guard record.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        try await EnduranceStore.shared.delete(record)
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await WidgetDataService.updateSnapshot()
        await TrainingNotificationService.reconcile()
        PhoneSessionManager.shared.sendContextToWatch()
    }

    static func refreshSummaries() async {
        await GoalNotificationService.notifyFrequencyGoalIfReached()
        await WidgetDataService.updateSnapshot()
        PhoneSessionManager.shared.sendContextToWatch()
    }
}

extension Notification.Name {
    static let shiftEnduranceDidChange = Notification.Name("shiftEnduranceDidChange")
}
