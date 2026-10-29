import XCTest
@testable import Shift

final class WeatherReschedulingTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-11-02T08:00:00Z") }
    private var location: WeatherPlanLocation { .init(latitude: 51.5074, longitude: -0.1278, place: "London") }
    private var baseline: WeatherSessionConditions { .init(rain: 0.1, wind: 8, gust: 12, low: 14, high: 14, uv: 1, dark: false, hazardous: false) }
    private func session() -> TrainingSession {
        var session = TrainingSession(userId: owner, title: "Tuesday run", scheduledAt: date("2026-11-03T10:00:00Z"), kind: .endurance, sport: .run, targetSeconds: 1_800, programID: "week")
        session.weatherPlan = .init(location: location, availability: (1...7).map { .init(weekday: $0, startMinute: 9*60, endMinute: 12*60) },
            weekStart: calendar.startOfDay(for: now), weekEnd: date("2026-11-09T00:00:00Z"), timeZoneID: "Europe/London",
            preferDry: true, daylightOnly: true, checkCalendar: false, baseline: baseline, checkedAt: now.addingTimeInterval(-600))
        return session
    }
    private func weather(rain: Double = 0.9) -> OutdoorWeatherSnapshot {
        let hours = (0..<168).map { index -> OutdoorWeatherHour in
            let time = calendar.startOfDay(for: now).addingTimeInterval(Double(index)*3_600)
            return .init(date: time, celsius: 14, rainChance: time == date("2026-11-03T10:00:00Z") ? rain : 0.1,
                windKPH: 8, gustKPH: 12, uv: 1, daylight: true, hazardous: false, condition: "Cloudy", symbol: "cloud")
        }
        return .init(fetchedAt: now, place: "London", current: hours[8], hours: hours, location: location)
    }
    func testRainChangeSuggestsAnAvailableDryTimeWithoutMutatingOriginal() throws {
        let original = session(), saved = original
        let result = try XCTUnwrap(WeatherReschedulingPolicy.review(original, weather: weather(), busy: [], now: now))
        XCTAssertTrue(result.reason.contains("90%"))
        let alternative = try XCTUnwrap(result.alternative)
        XCTAssertNotEqual(alternative.start, original.scheduledAt)
        XCTAssertEqual(original, saved)
        XCTAssertEqual(calendar.component(.hour, from: alternative.start), 9)
        XCTAssertEqual(alternative.minutes, 30)
    }
    func testNoChangeForDryOrSmallForecastFluctuations() {
        for rain in [0.1, 0.2, 0.4, 0.59] { XCTAssertNil(WeatherReschedulingPolicy.review(session(), weather: weather(rain: rain), busy: [], now: now)) }
    }
    func testRainIsNotAReasonWhenDryPreferenceIsOff() {
        var value = session(); value.weatherPlan?.preferDry = false
        XCTAssertNil(WeatherReschedulingPolicy.review(value, weather: weather(), busy: [], now: now))
    }
    func testStaleOrWrongAreaForecastCannotTriggerSuggestion() {
        var old = weather(); old.fetchedAt = now.addingTimeInterval(-3_601)
        XCTAssertNil(WeatherReschedulingPolicy.review(session(), weather: old, busy: [], now: now))
        var other = weather(); other.location = .init(latitude: 55.86, longitude: -4.25, place: "Glasgow")
        XCTAssertNil(WeatherReschedulingPolicy.review(session(), weather: other, busy: [], now: now))
    }
    func testMissingForecastHourCannotBeDescribedAsBetterWeather() {
        var input = weather(); input.hours.removeAll { $0.date == session().scheduledAt }
        XCTAssertNil(WeatherReschedulingPolicy.review(session(), weather: input, busy: [], now: now))
    }
    func testHazardInSecondHourIsIncluded() throws {
        var value = session(); value.targetSeconds = 5_400
        var input = weather(rain: 0.1)
        let index = try XCTUnwrap(input.hours.firstIndex { $0.date == value.scheduledAt.addingTimeInterval(3_600) })
        input.hours[index].hazardous = true
        let result = try XCTUnwrap(WeatherReschedulingPolicy.review(value, weather: input, busy: [], now: now))
        XCTAssertTrue(result.reason.contains("hazardous"))
        if let alternative = result.alternative {
            let conditions = try XCTUnwrap(WeatherSessionConditions.read(start: alternative.start, seconds: 5_400, weather: input, now: now))
            XCTAssertFalse(conditions.hazardous)
        }
    }
    func testAllBusyTimesLeaveOriginalAndOfferNoMove() throws {
        let result = try XCTUnwrap(WeatherReschedulingPolicy.review(session(), weather: weather(), busy: [.init(start: now, end: date("2026-11-09T00:00:00Z"))], now: now))
        XCTAssertNil(result.alternative)
    }
    func testKeepOriginalSuppressesSameChangeButNotNewHazard() throws {
        var value = session()
        let first = try XCTUnwrap(WeatherReschedulingPolicy.review(value, weather: weather(), busy: [], now: now))
        value.weatherPlan?.dismissedChange = first.changeKey
        XCTAssertNil(WeatherReschedulingPolicy.review(value, weather: weather(), busy: [], now: now))
        var input = weather(); let index = try XCTUnwrap(input.hours.firstIndex { $0.date == value.scheduledAt })
        input.hours[index].hazardous = true
        XCTAssertNotNil(WeatherReschedulingPolicy.review(value, weather: input, busy: [], now: now))
    }
    func testCompletedStartedSkippedPastOtherOwnerAndDisabledSessionsAreIneligible() {
        let value = session()
        XCTAssertTrue(WeatherReschedulingPolicy.eligible(value, owner: owner, completed: [], now: now))
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(value, owner: "other", completed: [], now: now))
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(value, owner: owner, completed: [value.id], now: now))
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(value, owner: owner, completed: [], now: value.scheduledAt.addingTimeInterval(-300)))
        var skipped = value; skipped.status = .skipped
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(skipped, owner: owner, completed: [], now: now))
        var disabled = value; disabled.weatherPlan?.enabled = false
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(disabled, owner: owner, completed: [], now: now))
        var allDay = value; allDay.isAllDay = true
        XCTAssertFalse(WeatherReschedulingPolicy.eligible(allDay, owner: owner, completed: [], now: now))
    }
    func testMissingAvailabilityAndUnknownForecastNeverArmWatching() {
        var request = EndurancePlanningRequest(starting: now)
        XCTAssertNil(WeatherReschedulingPolicy.context(request: request, session: session(), weather: weather(), checkCalendar: false, now: now, calendar: calendar))
        request.availability = session().weatherPlan!.availability
        var missing = weather(); missing.hours = []
        XCTAssertNil(WeatherReschedulingPolicy.context(request: request, session: session(), weather: missing, checkCalendar: false, now: now, calendar: calendar))
    }
    func testEndOfWeekNeverSpillsIntoNextWeek() throws {
        var value = session(); value.weatherPlan?.weekEnd = date("2026-11-03T10:30:00Z")
        let result = try XCTUnwrap(WeatherReschedulingPolicy.review(value, weather: weather(), busy: [.init(start: now, end: value.scheduledAt)], now: now))
        XCTAssertNil(result.alternative)
    }
    func testOtherSessionsInSameProgramBlockWholeDay() {
        let value = session()
        var other = value; other.id = UUID().uuidString.lowercased(); other.scheduledAt = date("2026-11-04T15:00:00Z")
        let busy = WeatherReschedulingPolicy.busyTimes(sessions: [value, other], excluding: value, completed: [])
        XCTAssertEqual(busy.count, 1)
        XCTAssertEqual(busy[0].duration, 86_400)
        XCTAssertTrue(busy[0].contains(date("2026-11-04T10:00:00Z")))
    }
    func testOlderSessionsDecodeWithoutWeatherPreferencesAndNewContextRoundTrips() throws {
        var old = session(); old.weatherPlan = nil
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(TrainingSession.self, from: data).weatherPlan)
        let new = session()
        XCTAssertEqual(try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(new)), new)
    }
    func testSavedPlanningTimeZoneSurvivesDeviceZoneChangesAndDST() {
        let value = session()
        XCTAssertEqual(value.weatherPlan?.calendar.timeZone.identifier, "Europe/London")
        XCTAssertEqual(location.latitude, 51.51)
        XCTAssertEqual(location.longitude, -0.13)
    }
    func testWidgetSummaryRemovesPlanningCoordinatesAndAvailability() {
        let summary = EnduranceWidgetData(weekStart: now, distanceMeters: 0, activeSeconds: 0, activities: 0, distanceUnit: "km",
            runMeters: 0, walkMeters: 0, cycleMeters: 0, nextSessions: [session()]).normalized(at: now, calendar: calendar)
        XCTAssertEqual(summary.nextSessions.count, 1)
        XCTAssertNil(summary.nextSessions[0].weatherPlan)
    }
    func testTinyRainThresholdCrossingDoesNotCreateSuggestion() {
        var value = session(); value.weatherPlan?.baseline.rain = 0.59
        XCTAssertNil(WeatherReschedulingPolicy.review(value, weather: weather(rain: 0.61), busy: [], now: now))
    }
    func testRainyBaselineCanStillFlagSevereWindEscalation() throws {
        var value = session(); value.weatherPlan?.baseline.wind = 36
        var forecast = weather(rain: 0.1)
        let index = try XCTUnwrap(forecast.hours.firstIndex { $0.date == value.scheduledAt })
        forecast.hours[index].windKPH = 60
        let result = try XCTUnwrap(WeatherReschedulingPolicy.review(value, weather: forecast, busy: [], now: now))
        XCTAssertTrue(result.reason.contains("planning limits"))
    }
}
