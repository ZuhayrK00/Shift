import XCTest
@testable import Shift

final class EndurancePlanningTests: XCTestCase {
    private var calendar: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/London")!; return cal }
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private var now: Date { date("2026-10-25T00:00:00Z") }
    private func hour(_ date: Date, rain: Double = 0, wind: Double = 5, daylight: Bool = true, hazard: Bool = false) -> OutdoorWeatherHour {
        .init(date: date, celsius: 14, rainChance: rain, windKPH: wind, gustKPH: wind, uv: 2, daylight: daylight, hazardous: hazard, condition: "Cloudy", symbol: "cloud")
    }
    private func request(sessions: Int = 1, minutes: Int = 30) -> EndurancePlanningRequest {
        .init(sport: .walk, sessions: sessions, minutes: minutes, starting: now, daylightOnly: true, preferDry: true,
            availability: (1...7).map { .init(weekday: $0, startMinute: 9 * 60, endMinute: 12 * 60) })
    }
    private func weather(_ hours: [OutdoorWeatherHour], fetchedAt: Date? = nil) -> OutdoorWeatherSnapshot {
        .init(fetchedAt: fetchedAt ?? now, place: "Demo city", current: hour(now), hours: hours)
    }
    func testAllHistoryHasNoStartDateAndOldDatesAreNotExcluded() {
        XCTAssertNil(EnduranceImportRange.allHistory.startDate(at: now, calendar: calendar))
        XCTAssertNotNil(EnduranceImportRange.last90Days.startDate(at: now, calendar: calendar))
        let oneYear = EnduranceImportRange.lastYear.startDate(at: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.year, from: oneYear), 2025)
        let report = EnduranceImportReport(foundCount: 8, importedCount: 8, walkCount: 6, runCount: 1, cycleCount: 1, routeFailureCount: 1)
        XCTAssertTrue(report.message.contains("all available history"))
        XCTAssertTrue(report.message.contains("6 walks/hikes"))
        XCTAssertTrue(report.message.contains("still imported or kept"))
        XCTAssertFalse(report.message.contains("last 90 days"))
    }
    func testPrefersDrierForecastWithinAvailability() {
        let rainy = hour(date("2026-10-25T09:00:00Z"), rain: 0.9)
        let dry = hour(date("2026-10-25T10:00:00Z"))
        let result = EndurancePlanningEngine.suggest(request(), weather: weather([rainy, dry]), busy: [], now: now, calendar: calendar)
        XCTAssertEqual(result.suggestions.first?.start, dry.date)
        XCTAssertNotNil(result.suggestions.first?.forecast)
    }
    func testNeverMovesOutsideAvailabilityOrOverlapsAppointments() {
        var input = request()
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 10 * 60)]
        let busy = DateInterval(start: date("2026-10-25T09:00:00Z"), duration: 1_800)
        let result = EndurancePlanningEngine.suggest(input, weather: weather([hour(busy.start)]), busy: [busy], now: now, calendar: calendar)
        XCTAssertEqual(result.suggestions.first?.start, date("2026-10-25T09:30:00Z"))
        XCTAssertEqual(result.suggestions.count, 1)
    }
    func testWholeSessionMustHaveContiguousForecastCoverage() {
        var input = request(minutes: 90)
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 10 * 60 + 30)]
        let nine = hour(date("2026-10-25T09:00:00Z"))
        let result = EndurancePlanningEngine.suggest(input, weather: weather([nine]), busy: [], now: now, calendar: calendar)
        XCTAssertNil(result.suggestions.first?.forecast)
        XCTAssertTrue(result.warnings.contains { $0.contains("no current forecast") })
    }
    func testHazardInSecondHourExcludesTheEntireSession() {
        var input = request(minutes: 90)
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 10 * 60 + 30)]
        let result = EndurancePlanningEngine.suggest(input, weather: weather([hour(date("2026-10-25T09:00:00Z")), hour(date("2026-10-25T10:00:00Z"), hazard: true)]), busy: [], now: now, calendar: calendar)
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("hazardous") })
    }
    func testUnknownAndStaleForecastsAreExplicitlyUnverified() {
        let old = weather([hour(date("2026-10-25T09:00:00Z"))], fetchedAt: now.addingTimeInterval(-3_601))
        for value in [nil, old] as [OutdoorWeatherSnapshot?] {
            let result = EndurancePlanningEngine.suggest(request(), weather: value, busy: [], now: now, calendar: calendar)
            XCTAssertNil(result.suggestions.first?.forecast)
            XCTAssertTrue(result.suggestions.first?.weatherSummary.contains("unverified") == true)
        }
    }
    func testPartialForecastCannotHideAKnownHazard() {
        var input = request(minutes: 90)
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 10 * 60 + 30)]
        let result = EndurancePlanningEngine.suggest(input, weather: weather([hour(date("2026-10-25T10:00:00Z"), hazard: true)]), busy: [], now: now, calendar: calendar)
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("hazardous") })
    }
    func testNeverInventsExtraDaysWhenAvailabilityIsInsufficient() {
        var input = request(sessions: 5)
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 12 * 60)]
        let result = EndurancePlanningEngine.suggest(input, weather: nil, busy: [], now: now, calendar: calendar)
        XCTAssertEqual(result.suggestions.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("1 of 5") })
    }
    func testOverlappingWindowsDoNotDuplicateSessions() {
        var input = request(sessions: 7)
        input.availability += input.availability
        let result = EndurancePlanningEngine.suggest(input, weather: nil, busy: [], now: now, calendar: calendar)
        XCTAssertEqual(result.suggestions.count, 7)
        XCTAssertEqual(Set(result.suggestions.map { calendar.startOfDay(for: $0.start) }).count, 7)
    }
    func testInvalidAndOvernightWindowsAreRejected() {
        var input = request()
        input.availability[0].endMinute = 30
        XCTAssertTrue(EndurancePlanningEngine.suggest(input, weather: nil, busy: [], now: now, calendar: calendar).suggestions.isEmpty)
        input = request(minutes: 181)
        XCTAssertTrue(EndurancePlanningEngine.suggest(input, weather: nil, busy: [], now: now, calendar: calendar).suggestions.isEmpty)
    }
    func testDaylightPreferenceExcludesKnownNightTimes() {
        var input = request()
        input.availability = [.init(weekday: 7, startMinute: 9 * 60, endMinute: 10 * 60)]
        let result = EndurancePlanningEngine.suggest(input, weather: weather([hour(date("2026-10-25T09:00:00Z"), daylight: false)]), busy: [], now: now, calendar: calendar)
        XCTAssertTrue(result.suggestions.isEmpty)
        input.daylightOnly = false
        XCTAssertFalse(EndurancePlanningEngine.suggest(input, weather: weather([hour(date("2026-10-25T09:00:00Z"), daylight: false)]), busy: [], now: now, calendar: calendar).suggestions.isEmpty)
    }
    func testDSTSpringGapDoesNotMoveSessionsToAnotherDay() {
        let before = date("2027-03-27T20:00:00Z")
        var input = request(); input.starting = date("2027-03-28T00:00:00Z")
        input.availability = [.init(weekday: 7, startMinute: 60, endMinute: 120)]
        let result = EndurancePlanningEngine.suggest(input, weather: nil, busy: [], now: before, calendar: calendar)
        XCTAssertTrue(result.suggestions.isEmpty)
    }
    func testSavedPlanIsOwnerScopedAndContainsForecastProvenance() {
        let result = EndurancePlanningEngine.suggest(request(), weather: weather([hour(date("2026-10-25T09:00:00Z"))]), busy: [], now: now, calendar: calendar)
        let sessions = EndurancePlanningEngine.sessions(from: result.suggestions, sport: .walk, owner: "owner", programID: "program", place: "Demo city", forecastFetchedAt: now)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.userId, "owner")
        XCTAssertEqual(sessions.first?.programID, "program")
        XCTAssertEqual(sessions.first?.targetSeconds, 1_800)
        XCTAssertTrue(sessions.first?.notes.contains("Demo city") == true)
        XCTAssertTrue(sessions.allSatisfy(\.isValid))
    }
    func testWeatherBriefExpiresIndependentlyOfWeeklyTotals() throws {
        let brief = OutdoorWeatherBrief(fetchedAt: now, place: "Demo city", celsius: 14, symbol: "cloud", condition: "Cloudy", legalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
        let summary = EnduranceWidgetData(weekStart: now, distanceMeters: 1_000, activeSeconds: 600, activities: 1, distanceUnit: "km", runMeters: 0, walkMeters: 1_000, cycleMeters: 0, nextSessions: [], weather: brief)
        XCTAssertNil(summary.normalized(at: now.addingTimeInterval(3_601)).weather)
        XCTAssertEqual(summary.normalized(at: now.addingTimeInterval(3_601)).distanceMeters, 1_000)
        let restored = try JSONDecoder().decode(EnduranceWidgetData.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(restored.weather?.place, "Demo city")
    }
}
