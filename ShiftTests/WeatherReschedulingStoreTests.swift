import XCTest
import GRDB
@testable import Shift

final class WeatherReschedulingStoreTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"
    private func fixture() async throws -> (EnduranceStore, TrainingSession) {
        let database = try AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("weather-tests-\(UUID()).sqlite"))
        let store = EnduranceStore(database: database)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var session = TrainingSession(userId: owner, title: "Fixture run", scheduledAt: now.addingTimeInterval(2*86_400), kind: .endurance, sport: .run, targetSeconds: 1_800)
        session.weatherPlan = .init(location: .init(latitude: 51.5, longitude: -0.12, place: "London"),
            availability: (1...7).map { .init(weekday: $0, startMinute: 0, endMinute: 1_440) }, weekStart: now,
            weekEnd: now.addingTimeInterval(7*86_400), timeZoneID: "Europe/London", preferDry: true, daylightOnly: false, checkCalendar: false,
            baseline: .init(rain: 0.1, wind: 8, gust: 12, low: 14, high: 14, uv: 1, dark: false, hazardous: false), checkedAt: now)
        try await store.save(session)
        return (store, session)
    }
    func testConfirmedMoveKeepsIdentityDurationAndCommitsOneMutation() async throws {
        let (store, original) = try await fixture()
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        try await store.replaceWeatherSession(original, with: moved)
        let rows = try await store.all(TrainingSession.self, userID: owner)
        XCTAssertEqual(rows, [moved])
        let mutations = try await store.database.dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM mutation_queue") }
        XCTAssertEqual(mutations, 2)
    }
    func testDeletedSessionCannotBeResurrectedByStaleSuggestion() async throws {
        let (store, original) = try await fixture()
        try await store.delete(original)
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        do { try await store.replaceWeatherSession(original, with: moved); XCTFail("Deleted session moved") } catch { }
        let rows = try await store.all(TrainingSession.self, userID: owner)
        XCTAssertTrue(rows.isEmpty)
    }
    func testEditedSessionCannotBeOverwrittenAndNoMutationIsAdded() async throws {
        let (store, original) = try await fixture()
        var edited = original; edited.title = "Changed by user"
        try await store.save(edited)
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        do { try await store.replaceWeatherSession(original, with: moved); XCTFail("Overwrote an edit") } catch { }
        let rows = try await store.all(TrainingSession.self, userID: owner)
        XCTAssertEqual(rows, [edited])
        let mutations = try await store.database.dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM mutation_queue") }
        XCTAssertEqual(mutations, 2)
    }
    func testNewlyConflictingAppointmentBlocksMoveAtomically() async throws {
        let (store, original) = try await fixture()
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        var clash = moved; clash.id = UUID().uuidString.lowercased(); clash.weatherPlan = nil
        try await store.save(clash)
        do { try await store.replaceWeatherSession(original, with: moved); XCTFail("Allowed conflict") } catch { }
        let rows = try await store.all(TrainingSession.self, userID: owner)
        XCTAssertEqual(rows.first { $0.id == original.id }, original)
    }
    func testActiveRecordingPreventsMovingItsPlannedSession() async throws {
        let (store, original) = try await fixture()
        var draft = EnduranceDraft(userId: owner, sport: .run, startedAt: Date(), checkpointAt: Date())
        draft.trainingSessionID = original.id
        try await store.saveDraft(draft)
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        do { try await store.replaceWeatherSession(original, with: moved); XCTFail("Moved active recording") } catch { }
    }
    func testCompletedActivityPreventsMove() async throws {
        let (store, original) = try await fixture()
        var activity = EnduranceActivity(userId: owner, sport: .run, title: "Finished", startedAt: Date().addingTimeInterval(-1_800), endedAt: Date(), activeSeconds: 1_800, distanceMeters: 4_000)
        activity.trainingSessionID = original.id
        try await store.save(activity)
        var moved = original; moved.scheduledAt = original.scheduledAt.addingTimeInterval(3_600)
        do { try await store.replaceWeatherSession(original, with: moved); XCTFail("Moved completed activity") } catch { }
    }
    func testKeepOriginalAndPreferencesUpdateCannotAlterOtherFields() async throws {
        let (store, original) = try await fixture()
        var kept = original; kept.weatherPlan?.dismissedChange = "rain"
        try await store.replaceWeatherSession(original, with: kept)
        var off = kept; off.weatherPlan = nil
        try await store.updateWeatherPreferences(kept, with: off)
        var invalid = off; invalid.scheduledAt = off.scheduledAt.addingTimeInterval(3_600)
        do { try await store.updateWeatherPreferences(off, with: invalid); XCTFail("Preference save moved session") } catch { }
        let rows = try await store.all(TrainingSession.self, userID: owner)
        XCTAssertEqual(rows, [off])
    }
    func testCrossAccountReplacementIsRejected() async throws {
        let (store, original) = try await fixture()
        var foreign = original; foreign.userId = "22222222-2222-4222-8222-222222222222"
        do { try await store.replaceWeatherSession(original, with: foreign); XCTFail("Changed owner") } catch { }
    }
}
