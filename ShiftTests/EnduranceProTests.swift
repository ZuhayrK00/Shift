import XCTest
import GRDB
@testable import Shift

final class EnduranceProTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"
    private let other = "22222222-2222-4222-8222-222222222222"
    private let program = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private func session(owner: String? = nil, at date: Date = Date()) -> TrainingSession {
        TrainingSession(userId: owner ?? self.owner, title: "Fixture walk", scheduledAt: date, kind: .endurance, sport: .walk, targetSeconds: 1_800, programID: program)
    }
    private func database() throws -> AppDatabase {
        try AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-tests-\(UUID()).sqlite"))
    }
    private func receipt(_ sessions: [TrainingSession]) -> EnduranceWeekPreview {
        .init(userID: owner, programID: program, sessionIDs: sessions.map(\.id), createdAt: Date())
    }
    func testEntitlementAndUsageDecisionMatrixFailsClosed() {
        XCTAssertEqual(EnduranceProPolicy.planningAccess(isChecking: true, isPro: false, previewChecked: false, hasUsedPreview: false), .checking)
        XCTAssertEqual(EnduranceProPolicy.planningAccess(isChecking: false, isPro: true, previewChecked: false, hasUsedPreview: true), .pro)
        XCTAssertEqual(EnduranceProPolicy.planningAccess(isChecking: false, isPro: false, previewChecked: false, hasUsedPreview: false), .unavailable)
        XCTAssertEqual(EnduranceProPolicy.planningAccess(isChecking: false, isPro: false, previewChecked: true, hasUsedPreview: false), .freeWeek)
        XCTAssertEqual(EnduranceProPolicy.planningAccess(isChecking: false, isPro: false, previewChecked: false, hasUsedPreview: true), .upgradeRequired)
        XCTAssertFalse(EndurancePlanningAccess.unavailable.canPlan)
        XCTAssertFalse(EndurancePlanningAccess.upgradeRequired.canPlan)
    }
    func testACompleteSevenDayWeekIsAcceptedButDuplicatesOwnersAndExtraWeeksAreRejected() {
        let now = Date()
        let week = (0..<7).map { session(at: now.addingTimeInterval(Double($0 * 86_400))) }
        XCTAssertTrue(EnduranceProPolicy.isValidPreview(week, owner: owner, programID: program))
        XCTAssertFalse(EnduranceProPolicy.isValidPreview([], owner: owner, programID: program))
        XCTAssertFalse(EnduranceProPolicy.isValidPreview(week + [session()], owner: owner, programID: program))
        XCTAssertFalse(EnduranceProPolicy.isValidPreview([week[0], week[0]], owner: owner, programID: program))
        XCTAssertFalse(EnduranceProPolicy.isValidPreview([session(owner: other)], owner: owner, programID: program))
        XCTAssertFalse(EnduranceProPolicy.isValidPreview([week[0], session(at: now.addingTimeInterval(7 * 86_400))], owner: owner, programID: program))
    }
    func testSuccessfulPreviewCachesEverySessionAndReceiptWithoutAnOutboundDuplicate() async throws {
        let db = try database(), store = EndurancePreviewStore(database: db)
        let records = (0..<5).map { session(at: Date().addingTimeInterval(Double($0 * 86_400))) }
        try await store.apply(receipt(records), sessions: records)
        let saved = try await EnduranceStore(database: db).all(TrainingSession.self, userID: owner)
        XCTAssertEqual(Set(saved.map(\.id)), Set(records.map(\.id)))
        let claim = try await store.receipt(owner: owner)
        XCTAssertEqual(claim?.programID, program)
        let pending = try await db.dbPool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM mutation_queue") }
        XCTAssertEqual(pending, 0)
        let otherClaim = try await store.receipt(owner: other)
        XCTAssertNil(otherClaim)
    }
    func testRememberedRemoteUsageCanStillHydrateAfterLostResponse() async throws {
        let db = try database(), store = EndurancePreviewStore(database: db), record = session()
        let claim = receipt([record])
        try await store.remember(claim)
        try await store.apply(claim, sessions: [record])
        let saved = try await EnduranceStore(database: db).all(TrainingSession.self, userID: owner)
        XCTAssertEqual(saved.count, 1)
    }
    func testRetryCannotResurrectDeletedSessionsOrOverwriteEdits() async throws {
        let db = try database(), store = EndurancePreviewStore(database: db)
        let records = [session(), session()];let claim = receipt(records)
        try await store.apply(claim, sessions: records)
        try await db.dbPool.write { db in
            try db.execute(sql: "DELETE FROM training_sessions WHERE id=?", arguments: [records[0].id])
            var edited = records[1]; edited.title = "My edited session"
            try EnduranceStore.upsert(edited, in: db)
        }
        try await store.apply(claim, sessions: records)
        let saved = try await EnduranceStore(database: db).all(TrainingSession.self, userID: owner)
        XCTAssertEqual(saved.map(\.title), ["My edited session"])
        let remainingClaim = try await store.receipt(owner: owner)
        XCTAssertNotNil(remainingClaim)
    }
    func testPendingLocalDeletionWinsOverRemotePreviewHydration() async throws {
        let db = try database(), store = EndurancePreviewStore(database: db), record = session()
        try await EnduranceStore(database: db).delete(record)
        try await store.apply(receipt([record]), sessions: [record])
        let saved = try await EnduranceStore(database: db).all(TrainingSession.self, userID: owner)
        XCTAssertTrue(saved.isEmpty)
        let claim = try await store.receipt(owner: owner)
        XCTAssertNotNil(claim)
    }
    func testFailedLocalTransactionDoesNotMarkReceiptApplied() async throws {
        let db = try database(), store = EndurancePreviewStore(database: db)
        var record = session(); var foreign = record; foreign.userId = other
        try await EnduranceStore(database: db).save(foreign)
        do { try await store.apply(receipt([record]), sessions: [record]); XCTFail("Expected owner collision") } catch { }
        let claim = try await store.receipt(owner: owner)
        XCTAssertNil(claim)
        record.id = UUID().uuidString.lowercased()
        try await store.apply(receipt([record]), sessions: [record])
        let saved = try await EnduranceStore(database: db).all(TrainingSession.self, userID: owner)
        XCTAssertEqual(saved.count, 1)
    }
    func testPreviewReceiptDecodesPostgresTimestampAndRoundTrips() throws {
        let json = """
        {"user_id":"\(owner)","program_id":"\(program)","session_ids":[],"created_at":"2026-10-26T08:30:45.123456+00:00"}
        """
        let value = try EnduranceCoding.decoder().decode(EnduranceWeekPreview.self, from: Data(json.utf8))
        let restored = try EnduranceCoding.decoder().decode(EnduranceWeekPreview.self, from: EnduranceCoding.encoder().encode(value))
        XCTAssertEqual(restored.userID, value.userID)
        XCTAssertEqual(restored.programID, value.programID)
        XCTAssertEqual(restored.sessionIDs, value.sessionIDs)
        // The shared ISO-8601 cache encoder stores second precision.
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, value.createdAt.timeIntervalSince1970, accuracy: 1)
    }
    func testExpiredProCacheCannotKeepExtensionsUnlocked() {
        let now = Date()
        let expired = StoreEntitlementSnapshot(isPro: true, activeProductIDs: [StoreProduct.monthlyPro.rawValue], verifiedAt: now, expiresAt: now.addingTimeInterval(-1))
        let fresh = StoreEntitlementSnapshot(isPro: false, activeProductIDs: [], verifiedAt: now)
        XCTAssertFalse(StoreEntitlementCache.resolveForExtension(fresh, cached: expired, at: now).isPro)
        var valid = expired; valid.expiresAt = now.addingTimeInterval(3_600)
        XCTAssertTrue(StoreEntitlementCache.resolveForExtension(fresh, cached: valid, at: now).isPro)
    }
}
