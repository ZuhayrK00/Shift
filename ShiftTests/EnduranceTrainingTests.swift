import XCTest
import SwiftUI
import UIKit
@preconcurrency import GRDB
@testable import Shift

final class EnduranceTrainingTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    let other = "22222222-2222-4222-8222-222222222222"
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func activity(owner: String? = nil) -> EnduranceActivity {
        .init(userId: owner ?? self.owner, sport: .run, title: "Evening loop", startedAt: now.addingTimeInterval(-1_800), endedAt: now, activeSeconds: 1_500, distanceMeters: 5_000)
    }
    func planned(at date: Date? = nil) -> TrainingSession {
        .init(userId: owner, title: "Easy run", scheduledAt: date ?? now.addingTimeInterval(3_600), kind: .endurance, sport: .run)
    }
    func splits(_ seconds: [Double]) -> [EnduranceSplit] { seconds.enumerated().map { .init(number: $0.offset + 1, distanceMeters: 1_000, activeSeconds: $0.element) } }

    func testBestBlockUsesConsecutiveMeasuredKilometres() {
        XCTAssertEqual(EnduranceInsights.bestBlock(splits([400, 300, 290, 280, 270, 260]), kilometers: 5), 1_400)
        var partial = splits([300, 300, 300, 300, 300]); partial[2].distanceMeters = 999
        XCTAssertNil(EnduranceInsights.bestBlock(partial, kilometers: 5))
        partial = splits([300, 300, 300, 300, 300]); partial[3].number = 5
        XCTAssertNil(EnduranceInsights.bestBlock(partial, kilometers: 5))
        XCTAssertEqual(EnduranceInsights.bestBlock(splits([.nan, 300]), kilometers: 1), 300)
        XCTAssertNil(EnduranceInsights.bestBlock([], kilometers: 0))
    }
    func testTimedRecordsNeverExtrapolateImportsOrMixAccounts() {
        var own = activity(); own.splits = splits([300, 300, 300, 300, 300])
        var imported = activity(); imported.source = "healthkit"; imported.activeSeconds = 400
        var foreign = activity(owner: other); foreign.splits = splits([100, 100, 100, 100, 100]); foreign.distanceMeters = 100_000
        let records = EnduranceInsights.records([own, imported, foreign], userID: owner)
        XCTAssertEqual(records.first { $0.id == "run-5k" }?.activityID, own.id)
        XCTAssertFalse(records.contains { $0.activityID == foreign.id })
        XCTAssertNil(EnduranceInsights.records([imported], userID: owner).first { $0.isTime })
    }
    func testMonthlyAggregationIncludesEmptyMonthsAndScopesOwner() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows = EnduranceInsights.months([activity(), activity(owner: other)], userID: owner, now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 6); XCTAssertEqual(rows.last?.distance, 5_000); XCTAssertEqual(rows.last?.count, 1)
        XCTAssertEqual(rows.dropLast().reduce(0) { $0 + $1.count }, 0)
        XCTAssertEqual(Set(rows.map(\.start)).count, 6)
    }
    func testMilestonesAreDerivedFromOwnedCompletedActivities() {
        XCTAssertEqual(EnduranceInsights.milestones([activity(owner: other)], userID: owner), [])
        let achieved = EnduranceInsights.milestones([activity()], userID: owner)
        XCTAssertTrue(achieved.contains("First adventure")); XCTAssertTrue(achieved.contains("First 5K run"))
        XCTAssertFalse(achieved.contains("10 activities"))
    }
    func testProgramsHaveDistinctSessionsOneGroupAndDSTSafeDates() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9)))
        for program in EnduranceProgramTemplate.all {
            let sessions = program.sessions(userID: owner, starting: start, calendar: calendar)
            XCTAssertEqual(sessions.count, program.weeks * program.sessionsPerWeek)
            XCTAssertEqual(Set(sessions.map(\.id)).count, sessions.count)
            XCTAssertEqual(Set(sessions.compactMap(\.programID)).count, 1)
            XCTAssertTrue(sessions.allSatisfy { $0.userId == owner && $0.isValid && $0.sport == program.sport })
            XCTAssertTrue(sessions.allSatisfy { calendar.component(.hour, from: $0.scheduledAt) == 9 })
            XCTAssertEqual(calendar.dateComponents([.day], from: sessions[0].scheduledAt, to: sessions[program.sessionsPerWeek].scheduledAt).day, 7)
        }
    }
    func testAutomaticCalendarLinkNeverGuessesBetweenTwoSessions() {
        let first = planned(at: now)
        XCTAssertEqual(TrainingLinkPolicy.candidate(sessions: [first], userID: owner, kind: .endurance, sport: .run, date: now, excluding: []), first.id)
        let second = planned(at: now)
        XCTAssertNil(TrainingLinkPolicy.candidate(sessions: [first, second], userID: owner, kind: .endurance, sport: .run, date: now, excluding: []))
        XCTAssertNil(TrainingLinkPolicy.candidate(sessions: [first], userID: other, kind: .endurance, sport: .run, date: now, excluding: []))
        XCTAssertNil(TrainingLinkPolicy.candidate(sessions: [first], userID: owner, kind: .endurance, sport: .walk, date: now, excluding: []))
        XCTAssertNil(TrainingLinkPolicy.candidate(sessions: [first], userID: owner, kind: .endurance, sport: .run, date: now, excluding: [first.id]))
    }
    func testReminderPolicyCancelsCompletedSkippedAndElapsedAndOtherAccounts() {
        let valid = planned()
        var skipped = planned(); skipped.status = .skipped
        let completed = planned()
        var foreign = planned(); foreign.userId = other
        let tooSoon = planned(at: now.addingTimeInterval(5 * 60))
        let reminders = TrainingReminderPolicy.reminders(sessions: [valid, skipped, completed, foreign, tooSoon], userID: owner, completedIDs: [completed.id], leadMinutes: 30, now: now)
        XCTAssertEqual(reminders, [.init(sessionID: valid.id, fireAt: valid.scheduledAt.addingTimeInterval(-1_800))])
        XCTAssertEqual(TrainingReminderPolicy.reminders(sessions: [valid], userID: owner, completedIDs: [], leadMinutes: 0, now: now), [])
    }
    func testReminderReschedulingUsesNewTimeAndCapsNearestFirst() {
        let rows = (1...40).map { planned(at: now.addingTimeInterval(Double($0 * 3_600))) }.reversed()
        let planned = Array(rows)
        let reminders = TrainingReminderPolicy.reminders(sessions: planned, userID: owner, completedIDs: [], leadMinutes: 15, now: now)
        XCTAssertEqual(reminders.count, 24)
        XCTAssertEqual(reminders.first?.fireAt, now.addingTimeInterval(2_700))
        var moved = planned[0]; moved.scheduledAt = now.addingTimeInterval(600)
        XCTAssertEqual(TrainingReminderPolicy.reminders(sessions: [moved], userID: owner, completedIDs: [], leadMinutes: 15, now: now), [])
    }
    func testAchievementsIgnoreImportsRepeatedSyncStaleAndFutureEvents() {
        let fresh = activity()
        XCTAssertTrue(EnduranceAchievementPolicy.shouldCelebrate(fresh, previousIDs: [], now: now))
        XCTAssertFalse(EnduranceAchievementPolicy.shouldCelebrate(fresh, previousIDs: [fresh.id], now: now))
        var imported = fresh; imported.source = "healthkit"
        XCTAssertFalse(EnduranceAchievementPolicy.shouldCelebrate(imported, previousIDs: [], now: now))
        XCTAssertFalse(EnduranceAchievementPolicy.shouldCelebrate(fresh, previousIDs: [], now: now.addingTimeInterval(7 * 3_600)))
        XCTAssertFalse(EnduranceAchievementPolicy.shouldCelebrate(fresh, previousIDs: [], now: now.addingTimeInterval(-1)))
    }
    func testNewNotificationPreferencesAreOptInAndLegacyCompatible() throws {
        let legacy = try JSONDecoder().decode(NotificationSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.trainingReminders); XCTAssertFalse(legacy.enduranceAchievements); XCTAssertEqual(legacy.trainingReminderMinutes, 30)
        var settings = legacy; settings.trainingReminders = true; settings.enduranceAchievements = true; settings.trainingReminderMinutes = 60
        XCTAssertEqual(try JSONDecoder().decode(NotificationSettings.self, from: JSONEncoder().encode(settings)), settings)
        let invalid = try JSONDecoder().decode(NotificationSettings.self, from: Data("{\"training_reminder_minutes\":-1}".utf8))
        XCTAssertEqual(invalid.trainingReminderMinutes, 30)
    }
    func testWatchTransferCannotCrossAccountsAndAckCannotDeleteNewRevision() throws {
        let transfer = EnduranceWatchTransfer(userID: owner, activity: activity())
        XCTAssertTrue(transfer.canReceive(as: owner)); XCTAssertFalse(transfer.canReceive(as: other)); XCTAssertFalse(transfer.canReceive(as: nil))
        var updated = transfer; updated.revision = UUID().uuidString
        XCTAssertFalse(updated.matchesAcknowledgment(id: transfer.activity.id, owner: owner, revision: transfer.revision))
        XCTAssertTrue(transfer.matchesAcknowledgment(id: transfer.activity.id, owner: owner, revision: transfer.revision))
        XCTAssertFalse(transfer.matchesAcknowledgment(id: transfer.activity.id, owner: other, revision: transfer.revision))
        var spoofed = transfer; spoofed.activity.userId = other; XCTAssertFalse(spoofed.isValid)
        spoofed = transfer; spoofed.schemaVersion = 99; XCTAssertFalse(spoofed.isValid)
        let roundTrip = try JSONDecoder().decode(EnduranceWatchTransfer.self, from: JSONEncoder().encode(transfer))
        XCTAssertEqual(roundTrip.revision, transfer.revision); XCTAssertEqual(roundTrip.activity, transfer.activity)
    }
    func testRecordingKeepsCalendarAndRouteAssociationsThroughRecovery() throws {
        var draft = EnduranceDraft(userId: owner, sport: .walk, startedAt: now, resumedAt: now, checkpointAt: now)
        draft.trainingSessionID = UUID().uuidString; draft.savedRouteID = UUID().uuidString
        let recovered = try JSONDecoder().decode(EnduranceDraft.self, from: JSONEncoder().encode(draft))
        let done = recovered.finished(title: "Walk", notes: "", at: now.addingTimeInterval(600))
        XCTAssertTrue(done.isValid); XCTAssertEqual(done.trainingSessionID, draft.trainingSessionID); XCTAssertEqual(done.savedRouteID, draft.savedRouteID)
        let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(activity())) as! [String: Any]
        XCTAssertNil(try JSONDecoder().decode(EnduranceActivity.self, from: JSONSerialization.data(withJSONObject: legacy)).trainingSessionID)
    }
    func testWidgetRolloverDoesNotKeepOldWeekFreshWhenStepsRefresh() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        let data = EnduranceWidgetData(weekStart: start, distanceMeters: 8_000, activeSeconds: 3_000, activities: 2, distanceUnit: "km", distanceGoalMeters: 10_000, runMeters: 8_000, walkMeters: 0, cycleMeters: 0, nextSessions: [planned(at: start)])
        XCTAssertEqual(data.normalized(at: end.addingTimeInterval(-1), calendar: calendar).distanceMeters, 8_000)
        let next = data.normalized(at: end, calendar: calendar)
        XCTAssertEqual(next.distanceMeters, 0); XCTAssertEqual(next.activities, 0); XCTAssertTrue(next.nextSessions.isEmpty)
    }
    func testCalendarAndRoutesPersistPrivatelyAndProgramWritesRollBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EnduranceStore(database: try AppDatabase(databaseURL: folder.appendingPathComponent("db.sqlite")))
        let first = planned(); var invalid = planned(); invalid.targetSeconds = -1
        do { try await store.saveAll([first, invalid]); XCTFail("Invalid plan committed") } catch {}
        let empty = try await store.all(TrainingSession.self, userID: owner); XCTAssertTrue(empty.isEmpty)
        try await store.saveAll([first]); var edited = first; edited.title = "Updated"; try await store.save(edited)
        let owned = try await store.all(TrainingSession.self, userID: owner); XCTAssertEqual(owned.count, 1); XCTAssertEqual(owned.first?.title, "Updated")
        let foreign = try await store.all(TrainingSession.self, userID: other); XCTAssertTrue(foreign.isEmpty)
        var spoofed = first; spoofed.userId = other
        do { try await store.save(spoofed); XCTFail("Overwrote another owner") } catch {}
    }
    func testWatchRetryDoesNotResurrectDeletionOrEraseHealthIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EnduranceStore(database: try AppDatabase(databaseURL: folder.appendingPathComponent("db.sqlite")))
        let original = activity()
        try await store.receiveWatchActivity(original)
        var final = original; final.healthKitID = UUID().uuidString
        try await store.receiveWatchActivity(final)
        try await store.receiveWatchActivity(original)
        let rows = try await store.all(EnduranceActivity.self, userID: owner)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.healthKitID, final.healthKitID)
        try await store.delete(final)
        do { try await store.receiveWatchActivity(original); XCTFail("Deleted activity resurrected") }
        catch EnduranceError.deletedActivity {} catch { XCTFail("Unexpected error: \(error)") }
        let remaining = try await store.all(EnduranceActivity.self, userID: owner)
        XCTAssertTrue(remaining.isEmpty)
    }
    @MainActor func testWeeklyPreferencesNeverInventCalendarAppointments() async {
        var settings = UserSettings.default
        let planID = UUID().uuidString.lowercased()
        settings.trainingSchedule.weeklyPlanIDs = ["1": planID, "3": planID, "5": planID]
        settings.trainingSchedule.dateOverrides[TrainingScheduleSettings.dateKey(now)] = planID
        let empty = TrainingCalendarProjection.expanded(sessions: [], settings: settings, userID: owner, from: now, days: 14, planNames: [planID: "Upper body"], workouts: [])
        XCTAssertTrue(empty.isEmpty)
        let explicit = TrainingSession(userId: owner, title: "My appointment", scheduledAt: now, kind: .strength, strengthPlanID: planID)
        let foreign = TrainingSession(userId: other, title: "Other account", scheduledAt: now, kind: .strength)
        let actual = TrainingCalendarProjection.expanded(sessions: [explicit, foreign], settings: settings, userID: owner, from: now, days: 14, planNames: [:], workouts: [])
        XCTAssertEqual(actual.map(\.id), [explicit.id])
        XCTAssertNil(actual.first?.isAllDay)
    }
    @MainActor func testShareCardsRenderAndRouteShapeIsAnExplicitChoice() async throws {
        var record = activity()
        record.route = [EnduranceRoutePoint(latitude: 51.5, longitude: -0.1, altitude: 10, timestamp: now.timeIntervalSince1970 - 100, horizontalAccuracy: 5, verticalAccuracy: 5, activeSeconds: 0, segment: 0),
            EnduranceRoutePoint(latitude: 51.51, longitude: -0.11, altitude: 12, timestamp: now.timeIntervalSince1970, horizontalAccuracy: 5, verticalAccuracy: 5, activeSeconds: 100, segment: 0)]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shift-training-previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var images: [Data] = []
        for include in [false, true] {
            let renderer = ImageRenderer(content: EnduranceShareCard(activity: record, unit: "km", includeRoute: include))
            renderer.scale = 2
            let png = try XCTUnwrap(renderer.uiImage?.pngData()); images.append(png)
            try png.write(to: folder.appendingPathComponent(include ? "share-with-route.png" : "share-private.png"))
        }
        XCTAssertNotEqual(images[0], images[1])
        print("Training preview images: \(folder.path)")
    }
}
