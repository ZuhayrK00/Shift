import XCTest
@preconcurrency import GRDB
@testable import Shift

final class EnduranceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let owner = "11111111-1111-4111-8111-111111111111"
    private let other = "22222222-2222-4222-8222-222222222222"

    private func draft() -> EnduranceDraft {
        EnduranceDraft(userId: owner, sport: .run, startedAt: start, resumedAt: start, checkpointAt: start)
    }
    private func point(_ lat: Double, seconds: Double, accuracy: Double = 5) -> EnduranceRoutePoint {
        .init(latitude: lat, longitude: 0, altitude: 10, timestamp: start.addingTimeInterval(seconds).timeIntervalSince1970,
              horizontalAccuracy: accuracy, verticalAccuracy: 5, activeSeconds: 0, segment: 0)
    }
    private func activity(userID: String? = nil, at date: Date? = nil) -> EnduranceActivity {
        let date = date ?? start
        return .init(userId: userID ?? owner, sport: .run, title: "Morning run", startedAt: date,
                     endedAt: date.addingTimeInterval(600), activeSeconds: 540, distanceMeters: 1_500)
    }

    func testDistanceAndPaceUseSIUnits() {
        XCTAssertEqual(point(0, seconds: 0).distance(to: point(0.001, seconds: 10)), 111.195, accuracy: 0.1)
        XCTAssertEqual(EnduranceFormat.distance(1_609.344, unit: "mi"), "1.00 mi")
        XCTAssertEqual(EnduranceFormat.pace(distance: 5_000, seconds: 1_500, sport: .run, unit: "km"), "5:00 /km")
        XCTAssertEqual(EnduranceFormat.pace(distance: 10_000, seconds: 1_800, sport: .cycle, unit: "km"), "20.0 km/h")
    }

    func testImportIdentityIsStableAndAccountScoped() {
        let workoutID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let first = EnduranceIdentity.importedID(workoutID: workoutID, userID: owner)
        XCTAssertEqual(first, EnduranceIdentity.importedID(workoutID: workoutID.lowercased(), userID: owner.uppercased()))
        XCTAssertNotEqual(first, EnduranceIdentity.importedID(workoutID: workoutID, userID: other))
        XCTAssertNotNil(UUID(uuidString: first))
    }

    func testHealthRoutePreferenceSurvivesReopeningAndIsAccountScoped() throws {
        let suite = "ShiftEndurancePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(EnduranceHealthPreferences.includesRoutes(userID: owner, defaults: defaults))
        EnduranceHealthPreferences.setIncludesRoutes(true, userID: owner, defaults: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(EnduranceHealthPreferences.includesRoutes(userID: owner.uppercased(), defaults: reopened))
        XCTAssertFalse(EnduranceHealthPreferences.includesRoutes(userID: other, defaults: reopened))
        EnduranceHealthPreferences.setIncludesRoutes(false, userID: owner, defaults: reopened)
        XCTAssertFalse(EnduranceHealthPreferences.includesRoutes(userID: owner, defaults: defaults))
    }

    func testDeletingHealthPreferenceKeepsOtherAccountsPreference() throws {
        let suite = "ShiftEndurancePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        EnduranceHealthPreferences.setIncludesRoutes(true, userID: owner, defaults: defaults)
        EnduranceHealthPreferences.setIncludesRoutes(true, userID: other, defaults: defaults)
        EnduranceHealthPreferences.clear(userID: owner, defaults: defaults)
        XCTAssertFalse(EnduranceHealthPreferences.includesRoutes(userID: owner, defaults: defaults))
        XCTAssertTrue(EnduranceHealthPreferences.includesRoutes(userID: other, defaults: defaults))
    }

    func testRepeatImportReportsExistingActivitiesInsteadOfEmptyHealthData() {
        let repeated = EnduranceImportReport(foundCount: 4, alreadyImportedCount: 4, previouslyImportedCount: 4)
        let noReadResults = EnduranceImportReport(previouslyImportedCount: 4)
        XCTAssertEqual(repeated.title, "You're up to date")
        XCTAssertNotEqual(repeated.title, noReadResults.title)
        XCTAssertTrue(repeated.message.contains("already in Shift"))
        XCTAssertFalse(repeated.message.contains("read access"))
        XCTAssertTrue(noReadResults.message.contains("still saved in Activities"))
    }

    func testUnavailableHealthRoutesAreNotReportedAsSuccessfulMapUpdates() {
        let missingRoutes = EnduranceImportReport(foundCount: 2, alreadyImportedCount: 2, unavailableRouteCount: 2)
        let updatedRoutes = EnduranceImportReport(foundCount: 2, updatedRouteCount: 2)
        XCTAssertNotEqual(missingRoutes.title, updatedRoutes.title)
        XCTAssertTrue(missingRoutes.message.contains("didn't provide map data"))
        XCTAssertFalse(missingRoutes.message.contains("Added maps"))
        XCTAssertTrue(updatedRoutes.message.contains("Added maps to 2 previously imported activities"))
    }

    func testInaccurateStaleAndFutureLocationsAreRejected() {
        var recording = draft()
        XCTAssertFalse(recording.append(point(0, seconds: 0, accuracy: 51), now: start))
        XCTAssertFalse(recording.append(point(0, seconds: -1), now: start))
        XCTAssertFalse(recording.append(point(0, seconds: 0), now: start.addingTimeInterval(21)))
        XCTAssertFalse(recording.append(point(0, seconds: 6), now: start))
        XCTAssertTrue(recording.route.isEmpty)
        XCTAssertEqual(recording.distanceMeters, 0)
    }

    func testImpossibleJumpDoesNotIncreaseDistance() {
        var recording = draft()
        XCTAssertTrue(recording.append(point(0, seconds: 0), now: start))
        XCTAssertFalse(recording.append(point(1, seconds: 5), now: start.addingTimeInterval(5)))
        XCTAssertEqual(recording.route.count, 1)
        XCTAssertEqual(recording.distanceMeters, 0)
    }

    func testSmallStationaryJitterDoesNotAccumulate() {
        var recording = draft()
        _ = recording.append(point(0, seconds: 0), now: start)
        for second in 1...10 {
            _ = recording.append(point(second.isMultiple(of: 2) ? 0.000001 : -0.000001, seconds: Double(second)), now: start.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(recording.distanceMeters, 0)
        XCTAssertEqual(recording.route.count, 1)
    }

    func testPauseExcludesTimeAndDoesNotConnectRouteSegments() {
        var recording = draft()
        _ = recording.append(point(0, seconds: 0), now: start)
        _ = recording.append(point(0.0009, seconds: 10), now: start.addingTimeInterval(10))
        let beforePause = recording.distanceMeters
        recording.pause(at: start.addingTimeInterval(10))
        XCTAssertFalse(recording.append(point(0.01, seconds: 20), now: start.addingTimeInterval(20)))
        recording.resume(at: start.addingTimeInterval(70))
        _ = recording.append(point(0.01, seconds: 70), now: start.addingTimeInterval(70))
        XCTAssertEqual(recording.distanceMeters, beforePause)
        XCTAssertEqual(recording.route.map(\.segment), [0, 0, 1])
        XCTAssertEqual(recording.activeSeconds(at: start.addingTimeInterval(80)), 20)
    }

    func testSignalGapStartsNewSegmentWithoutInventingDistance() {
        var recording = draft()
        _ = recording.append(point(0, seconds: 0), now: start)
        _ = recording.append(point(0.01, seconds: 40), now: start.addingTimeInterval(40))
        XCTAssertEqual(recording.route.map(\.segment), [0, 1])
        XCTAssertEqual(recording.distanceMeters, 0)
    }

    func testCachedLocationBeforeResumeIsRejected() {
        var recording = draft()
        recording.pause(at: start.addingTimeInterval(10))
        recording.resume(at: start.addingTimeInterval(20))
        XCTAssertFalse(recording.append(point(0, seconds: 19), now: start.addingTimeInterval(20)))
    }

    func testStationarySpeedPreventsLargerLocationDrift() {
        var recording = draft()
        _ = recording.append(point(0, seconds: 0), now: start)
        var drift = point(0.00005, seconds: 5)
        drift.speedMetersPerSecond = 0
        XCTAssertFalse(recording.append(drift, now: start.addingTimeInterval(5)))
        XCTAssertEqual(recording.distanceMeters, 0)
    }

    func testSmallAlternatingAltitudeNoiseDoesNotInflateElevation() {
        var recording = draft()
        for index in 0...20 {
            let seconds = Double(index * 10)
            var sample = point(Double(index) * 0.0001, seconds: seconds)
            sample.altitude = index.isMultiple(of: 2) ? 10 : 13
            _ = recording.append(sample, now: start.addingTimeInterval(seconds))
        }
        XCTAssertEqual(recording.elevationGainMeters, 0)
    }

    func testSplitsInterpolateTheKilometreBoundaryAndIncludeRemainder() {
        var recording = draft()
        for index in 0...11 {
            let seconds = Double(index * 10)
            _ = recording.append(point(Double(index) * 0.0009, seconds: seconds), now: start.addingTimeInterval(seconds))
        }
        let saved = recording.finished(title: "Run", notes: "", at: start.addingTimeInterval(110))
        XCTAssertEqual(saved.splits.count, 2)
        XCTAssertEqual(saved.splits[0].distanceMeters, 1_000)
        XCTAssertEqual(saved.splits[0].activeSeconds, 99.92, accuracy: 0.2)
        XCTAssertEqual(saved.splits.reduce(0) { $0 + $1.distanceMeters }, saved.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(saved.splits.reduce(0) { $0 + $1.activeSeconds }, saved.activeSeconds, accuracy: 0.001)
    }

    func testRecoveryPausesAtLastCheckpointNotCurrentTime() {
        var recording = draft()
        recording.checkpointAt = start.addingTimeInterval(12)
        recording.pause(at: recording.checkpointAt)
        XCTAssertTrue(recording.isPaused)
        XCTAssertEqual(recording.activeSeconds(at: start.addingTimeInterval(3_600)), 12)
    }

    func testJSONEnvelopeRoundTripsRouteAndDates() throws {
        var record = activity()
        record.route = [point(0, seconds: 0)]
        let encoded = try EnduranceCoding.encoder().encode(EnduranceEnvelope(record))
        let decoded = try EnduranceCoding.decoder().decode(EnduranceEnvelope<EnduranceActivity>.self, from: encoded)
        XCTAssertEqual(decoded.details, record)
        XCTAssertEqual(decoded.user_id, record.userId)
        XCTAssertEqual(decoded.id, record.id)
    }

    func testWeeklyGoalsFilterOwnerSportAndCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = ISO8601DateFormatter.shared.date(from: "2026-10-24T12:00:00Z")!
        let interval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        let valid = activity(at: interval.start)
        var cycling = activity(at: interval.start); cycling.sport = .cycle
        let foreign = activity(userID: other, at: interval.start)
        let old = activity(at: interval.start.addingTimeInterval(-1_000))
        let nextWeek = activity(at: interval.end)
        let goal = EnduranceGoal(userId: owner, sport: .run, metric: .distance, target: 5_000, period: .week)
        XCTAssertEqual(goal.progress(in: [valid, cycling, foreign, old, nextWeek], at: now, calendar: calendar), 1_500)
    }

    func testAllSportsDurationUsesActiveTimeAndDeadlineExcludesEarlierActivities() {
        let record = activity()
        let goal = EnduranceGoal(userId: owner, metric: .duration, target: 1_000, period: .deadline,
                                createdAt: start, deadline: start.addingTimeInterval(86_400))
        XCTAssertEqual(goal.progress(in: [record, activity(at: start.addingTimeInterval(-1_000))], at: start.addingTimeInterval(700)), 540)
    }

    func testInvalidTargetsAndRecordingsAreRejected() {
        XCTAssertFalse(EnduranceGoal(userId: owner, metric: .distance, target: .nan, period: .week).isValid)
        XCTAssertFalse(EnduranceGoal(userId: owner, metric: .activities, target: 1.5, period: .week).isValid)
        XCTAssertFalse(EnduranceGoal(userId: owner, metric: .duration, target: -1, period: .week).isValid)
        var record = activity(); record.distanceMeters = .infinity
        XCTAssertFalse(record.isValid)
        record = activity(); record.activeSeconds = record.elapsedSeconds + 2
        XCTAssertFalse(record.isValid)
    }

    func testPersistenceScopesRecordsAndDraftsAndDeduplicatesIDs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try AppDatabase(databaseURL: folder.appendingPathComponent("test.db"))
        let store = EnduranceStore(database: database)
        var record = activity()
        record.source = "healthkit"; record.healthKitID = record.id
        try await store.save(record)
        try await store.save(record)
        try await store.save(activity(userID: other))
        let own = try await store.all(EnduranceActivity.self, userID: owner)
        let foreign = try await store.all(EnduranceActivity.self, userID: other)
        XCTAssertEqual(own.count, 1)
        XCTAssertEqual(foreign.count, 1)
        let recording = draft()
        try await store.saveDraft(recording)
        let foreignDraft = try await store.draft(userID: other)
        XCTAssertNil(foreignDraft)
        let queueOwners = try await database.dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT user_id FROM mutation_queue ORDER BY id")
        }
        XCTAssertEqual(queueOwners, [owner, owner, other])
        try await store.delete(record)
        let remaining = try await store.all(EnduranceActivity.self, userID: other)
        XCTAssertEqual(remaining.count, 1)
    }

    func testQueueFailureRollsBackRecordAndKeepsRecoveryDraft() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try AppDatabase(databaseURL: folder.appendingPathComponent("test.db"))
        let store = EnduranceStore(database: database)
        let recording = draft()
        try await store.saveDraft(recording)
        try await database.dbPool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_queue BEFORE INSERT ON mutation_queue BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        do {
            try await store.save(recording.finished(title: "Run", notes: "", at: start.addingTimeInterval(100)), finishingDraft: true)
            XCTFail("Expected queue failure")
        } catch { /* The entire save must roll back. */ }
        let records = try await store.all(EnduranceActivity.self, userID: owner)
        let recovered = try await store.draft(userID: owner)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(recovered?.id, recording.id)
    }

    func testRecordIDCollisionCannotOverwriteAnotherAccount() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EnduranceStore(database: try AppDatabase(databaseURL: folder.appendingPathComponent("test.db")))
        let own = activity()
        try await store.save(own)
        var collision = own; collision.userId = other; collision.title = "Must not overwrite"
        do { try await store.save(collision); XCTFail("Expected owner collision to fail") } catch { }
        let stored = try await store.all(EnduranceActivity.self, userID: owner)
        let foreign = try await store.all(EnduranceActivity.self, userID: other)
        XCTAssertEqual(stored.first?.title, own.title)
        XCTAssertTrue(foreign.isEmpty)
    }
}
