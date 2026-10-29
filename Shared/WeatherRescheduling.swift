import Foundation

/// A rounded weather lookup point, not a recorded route or live location.
struct WeatherPlanLocation: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var place: String
    init(latitude: Double, longitude: Double, place: String) {
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
        self.place = place
    }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && !place.isEmpty }
}

struct WeatherSessionConditions: Codable, Hashable, Sendable {
    var rain: Double
    var wind: Double
    var gust: Double
    var low: Double
    var high: Double
    var uv: Int
    var dark: Bool
    var hazardous: Bool
    var isValid: Bool {
        rain.isFinite && (0...1).contains(rain) && wind.isFinite && wind >= 0 && gust.isFinite && gust >= 0
            && low.isFinite && high.isFinite && low <= high && uv >= 0
    }
    static func read(start: Date, seconds: Double, weather: OutdoorWeatherSnapshot, now: Date) -> Self? {
        guard weather.isFresh(at: now), seconds.isFinite, seconds > 0 else { return nil }
        let end = start.addingTimeInterval(seconds)
        let hours = weather.hours.filter { $0.date < end && $0.date.addingTimeInterval(3_600) > start }.sorted { $0.date < $1.date }
        guard !hours.isEmpty, hours.allSatisfy(\.isValid), hours.first!.date <= start,
              hours.last!.date.addingTimeInterval(3_600) >= end,
              zip(hours, hours.dropFirst()).allSatisfy({ abs($0.date.addingTimeInterval(3_600).timeIntervalSince($1.date)) < 1 }) else { return nil }
        return .init(rain: hours.map(\.rainChance).max()!, wind: hours.map(\.windKPH).max()!, gust: hours.map(\.gustKPH).max()!,
            low: hours.map(\.celsius).min()!, high: hours.map(\.celsius).max()!, uv: hours.map(\.uv).max()!,
            dark: hours.contains { !$0.daylight }, hazardous: hours.contains { $0.hazardous })
    }
    func concerns(sport: EnduranceSport, preferDry: Bool, daylightOnly: Bool) -> [String] {
        var result: [String] = []
        if hazardous { result.append("hazard") }
        if low <= -10 || high >= 38 || wind >= (sport == .cycle ? 40 : 55) || gust >= (sport == .cycle ? 60 : 75) { result.append("severe") }
        if low <= 0 { result.append("ice") }
        if high >= 30 { result.append("heat") }
        if wind >= (sport == .cycle ? 25 : 35) || gust >= (sport == .cycle ? 40 : 50) { result.append("wind") }
        if preferDry && rain >= 0.6 { result.append("rain") }
        if daylightOnly && dark { result.append("dark") }
        if uv >= 6 { result.append("uv") }
        return result
    }
    func score(sport: EnduranceSport, preferDry: Bool) -> Double {
        rain * (preferDry ? 110 : 20) + wind * (sport == .cycle ? 1.4 : 0.5)
            + max(abs(low - 15), abs(high - 15)) * 1.3 + Double(max(0, uv - 4)) * 8
    }
}

struct WeatherPlanContext: Codable, Hashable, Sendable {
    var enabled = true
    var location: WeatherPlanLocation
    var availability: [EnduranceAvailabilityWindow]
    var weekStart: Date
    var weekEnd: Date
    var timeZoneID: String
    var preferDry: Bool
    var daylightOnly: Bool
    var checkCalendar: Bool
    var baseline: WeatherSessionConditions
    var checkedAt: Date
    var dismissedChange: String?
    var isValid: Bool {
        location.isValid && !availability.isEmpty && availability.allSatisfy(\.isValid)
            && weekEnd > weekStart && weekEnd.timeIntervalSince(weekStart) <= 8 * 86_400
            && TimeZone(identifier: timeZoneID) != nil && baseline.isValid
    }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return value
    }
}

struct WeatherRescheduleSuggestion: Identifiable, Hashable, Sendable {
    var session: TrainingSession
    var conditions: WeatherSessionConditions
    var reason: String
    var changeKey: String
    var alternative: EndurancePlanSuggestion?
    var checkedAt: Date
    var id: String { session.id }
}

enum WeatherReschedulingPolicy {
    static func context(request: EndurancePlanningRequest, session: TrainingSession, weather: OutdoorWeatherSnapshot,
        checkCalendar: Bool, now: Date = Date(), calendar: Calendar = .current) -> WeatherPlanContext? {
        guard let location = weather.location, location.isValid, let seconds = session.targetSeconds,
              let conditions = WeatherSessionConditions.read(start: session.scheduledAt, seconds: seconds, weather: weather, now: now),
              let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: request.starting)) else { return nil }
        let value = WeatherPlanContext(location: location, availability: request.availability,
            weekStart: calendar.startOfDay(for: request.starting), weekEnd: end, timeZoneID: calendar.timeZone.identifier,
            preferDry: request.preferDry, daylightOnly: request.daylightOnly, checkCalendar: checkCalendar,
            baseline: conditions, checkedAt: weather.fetchedAt)
        return value.isValid ? value : nil
    }
    static func eligible(_ session: TrainingSession, owner: String, completed: Set<String>, now: Date) -> Bool {
        session.userId == owner && session.isValid && session.kind == .endurance && session.status == .scheduled
            && session.isAllDay != true && session.scheduledAt > now.addingTimeInterval(30 * 60)
            && !completed.contains(session.id) && session.weatherPlan?.enabled == true && session.weatherPlan?.isValid == true
            && session.scheduledAt < session.weatherPlan!.weekEnd && session.scheduledAt >= session.weatherPlan!.weekStart
            && (300...10_800).contains(session.targetSeconds ?? 0)
    }
    static func review(_ session: TrainingSession, weather: OutdoorWeatherSnapshot, busy: [DateInterval], now: Date = Date()) -> WeatherRescheduleSuggestion? {
        guard let plan = session.weatherPlan, plan.isValid, plan.enabled, let sport = session.sport,
              weather.location == plan.location, let seconds = session.targetSeconds,
              let current = WeatherSessionConditions.read(start: session.scheduledAt, seconds: seconds, weather: weather, now: now),
              weather.fetchedAt > plan.checkedAt else { return nil }
        let previous = Set(plan.baseline.concerns(sport: sport, preferDry: plan.preferDry, daylightOnly: plan.daylightOnly))
        var changes = current.concerns(sport: sport, preferDry: plan.preferDry, daylightOnly: plan.daylightOnly).filter {
            !previous.contains($0) && ($0 != "rain" || current.rain - plan.baseline.rain >= 0.25)
        }
        if plan.preferDry && previous.contains("rain") && current.rain >= plan.baseline.rain + 0.25 { changes.append("heavierRain") }
        guard !changes.isEmpty else { return nil }
        let key = "\(session.scheduledAt.timeIntervalSince1970):" + changes.sorted().joined(separator: ",")
        guard plan.dismissedChange != key else { return nil }
        let reasons = changes.map { change -> String in
            switch change {
            case "hazard": return "The forecast now includes potentially hazardous weather."
            case "severe": return "Conditions have worsened beyond Shift's outdoor planning limits."
            case "ice": return "Freezing conditions are now forecast."
            case "heat": return "High temperatures are now forecast."
            case "wind": return "Stronger wind is now forecast."
            case "rain", "heavierRain": return "Rain is now more likely at your planned time (\(Int((current.rain * 100).rounded()))%)."
            case "dark": return "Your session is now forecast to fall outside daylight."
            default: return "Higher UV is now forecast."
            }
        }
        let request = EndurancePlanningRequest(sport: sport, sessions: 7, minutes: Int(ceil(seconds / 60)), starting: plan.weekStart,
            daylightOnly: plan.daylightOnly, preferDry: plan.preferDry, availability: plan.availability)
        let alternatives = EndurancePlanningEngine.suggest(request, weather: weather, busy: busy, now: now, calendar: plan.calendar).suggestions
            .filter { item in
                guard item.start != session.scheduledAt, item.start > now.addingTimeInterval(30 * 60),
                      item.start.addingTimeInterval(seconds) <= plan.weekEnd,
                      let conditions = WeatherSessionConditions.read(start: item.start, seconds: seconds, weather: weather, now: now),
                      conditions.concerns(sport: sport, preferDry: plan.preferDry, daylightOnly: plan.daylightOnly).isEmpty else { return false }
                return conditions.score(sport: sport, preferDry: plan.preferDry) + 15 < current.score(sport: sport, preferDry: plan.preferDry)
                    || current.hazardous || current.dark && plan.daylightOnly
            }.sorted {
                let a = abs($0.start.timeIntervalSince(session.scheduledAt)), b = abs($1.start.timeIntervalSince(session.scheduledAt))
                return a == b ? $0.start < $1.start : a < b
            }
        return .init(session: session, conditions: current, reason: reasons.joined(separator: " "), changeKey: key,
            alternative: alternatives.first, checkedAt: weather.fetchedAt)
    }
    static func busyTimes(sessions: [TrainingSession], excluding session: TrainingSession, completed: Set<String>) -> [DateInterval] {
        sessions.filter { $0.userId == session.userId && $0.id != session.id && $0.status == .scheduled && !completed.contains($0.id) }.map {
            // Preserve the plan's one-session-per-day structure as well as clock conflicts.
            if let program = session.programID, $0.programID == program, let plan = session.weatherPlan,
               let day = plan.calendar.dateInterval(of: .day, for: $0.scheduledAt) { return day }
            if $0.isAllDay == true, let day = (session.weatherPlan?.calendar ?? .current).dateInterval(of: .day, for: $0.scheduledAt) { return day }
            return DateInterval(start: $0.scheduledAt, duration: $0.targetSeconds ?? 2_700)
        }
    }
}
