import XCTest
@testable import Shift

final class EndurancePolishTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func activity(_ id: String, owner: String = "owner", sport: EnduranceSport = .walk, meters: Double = 1_000, end: Date) -> EnduranceActivity {
        EnduranceActivity(id: id, userId: owner, sport: sport, title: "Fixture", startedAt: end.addingTimeInterval(-1_800), endedAt: end, activeSeconds: 1_800, distanceMeters: meters)
    }
    func testAwardsUseOriginalThresholdDatesIncludingImports() throws {
        let first = date("2026-08-01T09:00:00Z")
        var activities = (0..<10).map { index in activity("activity-\(index)", end: first.addingTimeInterval(Double(index * 86_400))) }
        activities[0].source = "healthkit"
        activities.append(activity("other-owner", owner: "someone-else", meters: 200_000, end: first.addingTimeInterval(-86_400)))
        let awards = EnduranceInsights.awards(activities.reversed(), userID: "owner", now: date("2026-10-25T12:00:00Z"))
        XCTAssertEqual(awards.map(\.id), ["first", "count10"])
        XCTAssertEqual(awards[0].earnedAt, first)
        XCTAssertEqual(awards[1].activityID, "activity-9")
        XCTAssertEqual(awards[1].earnedAt, first.addingTimeInterval(9 * 86_400))
    }
    func testDistanceAwardCrossesCumulativeThresholdAndIgnoresFutureActivities() throws {
        let now = date("2026-10-25T12:00:00Z")
        let old = now.addingTimeInterval(-86_400)
        let activities = [activity("a", sport: .cycle, meters: 60_000, end: old), activity("b", meters: 40_000, end: now), activity("future", sport: .run, meters: 5_000, end: now.addingTimeInterval(86_400))]
        let awards = EnduranceInsights.awards(activities, userID: "owner", now: now)
        XCTAssertNil(awards.first { $0.id == "5k" })
        let distance = try XCTUnwrap(awards.first { $0.id == "distance100" })
        XCTAssertEqual(distance.earnedAt, now)
        XCTAssertEqual(distance.activityID, "b")
    }
    func testExplicitEveningAndWeekendRangesKeepAMPM() {
        let windows = PlannerTimePolicy.explicitWindows(in: "Walk 5 times for 30 minutes. Weekdays 6–8pm, weekends 9–11am.")
        XCTAssertEqual(windows.count, 7)
        XCTAssertTrue(windows.filter { $0.weekday <= 5 }.allSatisfy { $0.startMinute == 1_080 && $0.endMinute == 1_200 })
        XCTAssertTrue(windows.filter { $0.weekday >= 6 }.allSatisfy { $0.startMinute == 540 && $0.endMinute == 660 })
    }
    func testAmbiguousAndOpenEndedAvailabilityCannotInventThreeAM() {
        for text in ["3 walks for 30 minutes on Tuesday and Wednesday", "Monday after 6pm", "Tuesday 3–4", "I work shifts, pick times for me"] {
            XCTAssertTrue(PlannerTimePolicy.explicitWindows(in: text).isEmpty, text)
        }
        let explicit = PlannerTimePolicy.explicitWindows(in: "Tuesday 3am–4am")
        XCTAssertEqual(explicit.first?.startMinute, 180)
        XCTAssertEqual(explicit.first?.endMinute, 240)
    }
    func testTwentyFourHourRangesAndMultipleNamedDays() {
        let windows = PlannerTimePolicy.explicitWindows(in: "Monday and Wednesday 18:00–20:00. Friday 09:30 to 11:00")
        XCTAssertEqual(windows.map(\.weekday), [1, 3, 5])
        XCTAssertEqual(windows.last?.startMinute, 570)
        XCTAssertEqual(windows.last?.endMinute, 660)
        XCTAssertTrue(PlannerTimePolicy.explicitWindows(in: "Friday 8pm–6pm").isEmpty)
    }
    func testBusyTimesAreClippedMergedAndAllowAdjacentSessions() {
        let start = date("2026-10-25T00:00:00Z")
        let range = DateInterval(start: start, duration: 86_400)
        let intervals = [DateInterval(start: start.addingTimeInterval(-3_600), duration: 7_200), DateInterval(start: start.addingTimeInterval(1_800), duration: 5_400), DateInterval(start: range.end.addingTimeInterval(3_600), duration: 3_600)]
        let merged = PlannerTimePolicy.mergedBusyTimes(intervals, within: range)
        XCTAssertEqual(merged, [DateInterval(start: start, duration: 7_200)])
        let adjacent = EndurancePlanSuggestion(start: start.addingTimeInterval(7_200), minutes: 30, weatherSummary: "")
        XCTAssertFalse(PlannerTimePolicy.overlaps(adjacent, busy: merged))
        let overlap = EndurancePlanSuggestion(start: start.addingTimeInterval(7_199), minutes: 30, weatherSummary: "")
        XCTAssertTrue(PlannerTimePolicy.overlaps(overlap, busy: merged))
    }
    func testAllDayCalendarEventRespectsLondonFallBackDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let start = date("2026-10-24T23:00:00Z"), end = date("2026-10-26T00:00:00Z")
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3_600)
        let request = EndurancePlanningRequest(sport: .walk, sessions: 1, minutes: 30, starting: start, availability: [.init(weekday: 7, startMinute: 540, endMinute: 660)])
        let result = EndurancePlanningEngine.suggest(request, weather: nil, busy: [DateInterval(start: start, end: end)], now: start.addingTimeInterval(-3_600), calendar: calendar)
        XCTAssertTrue(result.suggestions.isEmpty)
    }
}
