import Foundation

struct OutdoorWeatherHour: Codable, Hashable, Sendable {
    var date: Date
    var celsius: Double
    var rainChance: Double
    var windKPH: Double
    var gustKPH: Double
    var uv: Int
    var daylight: Bool
    var hazardous: Bool
    var condition: String
    var symbol: String
    var isValid: Bool { celsius.isFinite && rainChance.isFinite && (0...1).contains(rainChance) && windKPH.isFinite && windKPH >= 0 && gustKPH.isFinite && gustKPH >= 0 }
}

struct OutdoorWeatherSnapshot: Codable, Hashable, Sendable {
    var fetchedAt: Date
    var place: String
    var current: OutdoorWeatherHour
    var hours: [OutdoorWeatherHour]
    var location: WeatherPlanLocation?
    func isFresh(at now: Date) -> Bool { (-60...3_600).contains(now.timeIntervalSince(fetchedAt)) }
}

struct OutdoorWeatherBrief: Codable, Sendable {
    var fetchedAt: Date
    var place: String
    var celsius: Double
    var symbol: String
    var condition: String
    var legalURL: URL
    func isFresh(at now: Date) -> Bool { (-60...3_600).contains(now.timeIntervalSince(fetchedAt)) }
}

struct EnduranceAvailabilityWindow: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    /// ISO weekday, Monday = 1. Windows never cross midnight.
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var isValid: Bool { (1...7).contains(weekday) && (0..<1_440).contains(startMinute) && endMinute > startMinute && endMinute <= 1_440 }
}

struct EndurancePlanningRequest: Hashable, Sendable {
    var sport: EnduranceSport = .walk
    var sessions = 5
    var minutes = 30
    var starting = Date()
    var daylightOnly = true
    var preferDry = true
    var availability: [EnduranceAvailabilityWindow] = []
}

struct EndurancePlanSuggestion: Identifiable, Hashable, Sendable {
    var id = UUID()
    var start: Date
    var minutes: Int
    var forecast: OutdoorWeatherHour?
    var weatherSummary: String
    var caution: String?
}

struct EndurancePlanningResult: Sendable {
    var suggestions: [EndurancePlanSuggestion]
    var warnings: [String]
    var requested: Int
}

enum EnduranceWeatherPolicy {
    static func cautions(_ hour: OutdoorWeatherHour, sport: EnduranceSport) -> [String] {
        var values: [String] = []
        if hour.hazardous { values.append("Potentially hazardous weather") }
        if hour.celsius <= 0 { values.append("Freezing conditions; surfaces may be icy") }
        if hour.celsius >= 30 { values.append("High temperature") }
        if hour.windKPH >= (sport == .cycle ? 25 : 35) || hour.gustKPH >= (sport == .cycle ? 40 : 50) { values.append("Strong wind") }
        if hour.uv >= 6 { values.append("High UV") }
        if hour.rainChance >= 0.6 { values.append("Rain likely") }
        return values
    }
    static func excludes(_ hour: OutdoorWeatherHour, sport: EnduranceSport) -> Bool {
        hour.hazardous || hour.celsius <= -10 || hour.celsius >= 38
            || hour.windKPH >= (sport == .cycle ? 40 : 55) || hour.gustKPH >= (sport == .cycle ? 60 : 75)
    }
}

enum EndurancePlanningEngine {
    private struct Candidate {
        var suggestion: EndurancePlanSuggestion
        var score: Double
        var day: Date
    }
    /// Validated scheduling is deterministic. AI can interpret the goal, but
    /// cannot invent availability, forecast values, or calendar appointments.
    static func suggest(_ request: EndurancePlanningRequest, weather: OutdoorWeatherSnapshot?,
        busy: [DateInterval], now: Date = Date(), calendar: Calendar = .current) -> EndurancePlanningResult {
        guard (1...7).contains(request.sessions), (5...180).contains(request.minutes),
              !request.availability.isEmpty, request.availability.allSatisfy(\.isValid) else {
            return .init(suggestions: [], warnings: ["Choose valid availability, 1–7 sessions and a duration of 5–180 minutes."], requested: request.sessions)
        }
        let fresh = weather.flatMap { $0.isFresh(at: now) ? $0 : nil }
        let hours = (fresh?.hours ?? []).filter(\.isValid).sorted { $0.date < $1.date }
        var warnings: [String] = []
        var candidates: [Candidate] = []
        var seen = Set<Date>()
        var excluded = 0
        let first = calendar.startOfDay(for: request.starting)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let appleDay = calendar.component(.weekday, from: day)
            let weekday = appleDay == 1 ? 7 : appleDay - 1
            for window in request.availability where window.weekday == weekday {
                guard window.endMinute - window.startMinute >= request.minutes else { continue }
                for minute in stride(from: window.startMinute, through: window.endMinute - request.minutes, by: 30) {
                    guard let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                        matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward),
                        calendar.isDate(start, inSameDayAs: day), start > now, seen.insert(start).inserted else { continue }
                    let end = start.addingTimeInterval(Double(request.minutes * 60))
                    // Elapsed duration and wall-clock availability both matter at DST boundaries.
                    let endDay = calendar.startOfDay(for: end.addingTimeInterval(-1))
                    let endMinute = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
                    guard endDay == day, (endMinute <= window.endMinute || endMinute == 0 && window.endMinute == 1_440),
                          !busy.contains(where: { $0.start < end && $0.end > start }) else { continue }
                    let coverage = hours.filter { $0.date < end && $0.date.addingTimeInterval(3_600) > start }
                    let fullyCovered = coverage.first.map { $0.date <= start } == true && coverage.last.map { $0.date.addingTimeInterval(3_600) >= end } == true
                        && zip(coverage, coverage.dropFirst()).allSatisfy { abs($0.date.addingTimeInterval(3_600).timeIntervalSince($1.date)) < 1 }
                    let forecast = fullyCovered ? coverage : []
                    // Missing hours must never erase a hazard or darkness that
                    // is known in another part of this same session.
                    if coverage.contains(where: { EnduranceWeatherPolicy.excludes($0, sport: request.sport) }) { excluded += 1; continue }
                    if request.daylightOnly && coverage.contains(where: { !$0.daylight }) { continue }
                    // Unknown weather is never described as clear or safe.
                    let score: Double = forecast.map { weatherScore($0, request: request) }.max() ?? 500
                    let caution = forecast.isEmpty ? "Forecast unavailable for this time; daylight and conditions are unverified."
                        : Array(Set(forecast.flatMap { EnduranceWeatherPolicy.cautions($0, sport: request.sport) })).sorted().joined(separator: ". ")
                    let summary = forecast.isEmpty ? "Time fits your availability · weather unverified"
                        : "\(Int((forecast.map(\.rainChance).max() ?? 0) * 100))% rain chance · wind up to \(Int((forecast.map(\.windKPH).max() ?? 0).rounded())) km/h"
                    candidates.append(.init(suggestion: .init(start: start, minutes: request.minutes,
                        forecast: forecast.first, weatherSummary: summary, caution: caution.isEmpty ? nil : caution), score: score, day: day))
                }
            }
        }
        var chosen: [Candidate] = []
        // One session per day; keep the best available slot on each day, then
        // select the best days across the week. Exact ties favour earlier slots.
        for candidate in candidates.sorted(by: { $0.score == $1.score ? $0.suggestion.start < $1.suggestion.start : $0.score < $1.score }) {
            guard chosen.count < request.sessions, !chosen.contains(where: { $0.day == candidate.day }) else { continue }
            chosen.append(candidate)
        }
        if chosen.count < request.sessions { warnings.append("Found \(chosen.count) of \(request.sessions) sessions. Add availability or reduce the target; existing sessions and your time limits are respected.") }
        if excluded > 0 { warnings.append("Some times were excluded for potentially hazardous weather. Check local alerts before heading out.") }
        if chosen.contains(where: { $0.suggestion.forecast == nil }) { warnings.append("Some times have no current forecast. They fit your availability, but weather and daylight have not been verified.") }
        if !chosen.isEmpty && chosen.allSatisfy({ $0.suggestion.caution != nil && $0.suggestion.forecast != nil }) { warnings.append("Conditions look less favourable across your available times. Consider changing days or choosing an indoor alternative.") }
        return .init(suggestions: chosen.map(\.suggestion).sorted { $0.start < $1.start }, warnings: warnings, requested: request.sessions)
    }
    private static func weatherScore(_ hour: OutdoorWeatherHour, request: EndurancePlanningRequest) -> Double {
        let rain = hour.rainChance * (request.preferDry ? 110.0 : 20.0)
        let wind = hour.windKPH * (request.sport == .cycle ? 1.4 : 0.5)
        let temperature = abs(hour.celsius - 15.0) * 1.3
        let uv = Double(max(0, hour.uv - 4)) * 8.0
        return rain + wind + temperature + uv + (hour.daylight ? 0.0 : 12.0)
    }
    static func sessions(from suggestions: [EndurancePlanSuggestion], sport: EnduranceSport, owner: String,
        programID: String, place: String, forecastFetchedAt: Date?) -> [TrainingSession] {
        suggestions.map { item in
            let provenance = forecastFetchedAt.map { "Forecast checked \($0.formatted(date: .abbreviated, time: .shortened)) for \(place). Forecasts can change; check again before starting." } ?? "Scheduled from your availability. Weather has not been verified."
            return TrainingSession(userId: owner, title: "\(sport.title) · My weekly plan", scheduledAt: item.start,
                kind: .endurance, sport: sport, targetSeconds: Double(item.minutes * 60),
                notes: [item.weatherSummary, item.caution, provenance].compactMap { $0 }.joined(separator: "\n"), programID: programID)
        }
    }
}
