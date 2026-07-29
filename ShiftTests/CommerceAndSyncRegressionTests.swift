import XCTest
@testable import Shift

final class CommerceAndSyncRegressionTests: XCTestCase {

    func testFreePlanLimitAllowsOnlyFirstThreePlans() {
        XCTAssertTrue(ProFeaturePolicy.canCreatePlan(existingPlanCount: 0, isPro: false))
        XCTAssertTrue(ProFeaturePolicy.canCreatePlan(existingPlanCount: 2, isPro: false))
        XCTAssertFalse(ProFeaturePolicy.canCreatePlan(existingPlanCount: 3, isPro: false))
        XCTAssertFalse(ProFeaturePolicy.canCreatePlan(existingPlanCount: 100, isPro: false))
        XCTAssertTrue(ProFeaturePolicy.canCreatePlan(existingPlanCount: 100, isPro: true))
    }

    func testQueuedAndDuplicateWatchActionsAreAccepted() {
        XCTAssertTrue(WatchDeliveryPolicy.isAccepted(success: true, queued: false, duplicate: false))
        XCTAssertTrue(WatchDeliveryPolicy.isAccepted(success: false, queued: true, duplicate: false))
        XCTAssertTrue(WatchDeliveryPolicy.isAccepted(success: false, queued: false, duplicate: true))
        XCTAssertFalse(WatchDeliveryPolicy.isAccepted(success: false, queued: false, duplicate: false))
    }

    func testWidgetSnapshotDropsStaleDailyValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oldDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 12))!
        let newDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))!

        let normalized = makeSnapshot(updatedAt: oldDate, weekStart: oldDate)
            .normalized(for: newDate, calendar: calendar)

        XCTAssertEqual(normalized.stepsToday, 0)
        XCTAssertFalse(normalized.workedOutToday)
        XCTAssertEqual(normalized.workoutsThisWeek, 3)
    }

    func testWidgetSnapshotDropsStaleWeeklyValue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let followingWeek = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!

        let normalized = makeSnapshot(updatedAt: followingWeek, weekStart: weekStart)
            .normalized(for: followingWeek, calendar: calendar)

        XCTAssertEqual(normalized.workoutsThisWeek, 0)
    }

    func testEntitlementSnapshotRoundTripsVerificationTimestamp() throws {
        let original = StoreEntitlementSnapshot(
            isPro: true,
            activeProductIDs: [StoreProduct.yearlyPro.rawValue],
            verifiedAt: Date(timeIntervalSince1970: 1_785_283_200)
        )

        let decoded = try JSONDecoder().decode(
            StoreEntitlementSnapshot.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }

    private func makeSnapshot(updatedAt: Date, weekStart: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            workoutsThisWeek: 3,
            weeklyGoal: 4,
            stepsToday: 8_500,
            stepGoal: 10_000,
            workedOutToday: true,
            latestWeight: 80,
            latestWeightUnit: "kg",
            weightTrend: [],
            currentStreak: 5,
            streakUnit: "days",
            updatedAt: updatedAt,
            ownerUserId: "user-a",
            weekStart: weekStart,
            schemaVersion: 2
        )
    }
}
