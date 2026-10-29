import Foundation

enum TrainingSessionKind: String, Codable, CaseIterable, Sendable { case strength, endurance }
enum TrainingSessionStatus: String, Codable, CaseIterable, Sendable { case scheduled, skipped }

struct TrainingSession: EnduranceEntity, Hashable {
    static let table = "training_sessions"
    var id: String = UUID().uuidString.lowercased()
    var userId: String
    var title: String
    var scheduledAt: Date
    var kind: TrainingSessionKind
    var sport: EnduranceSport?
    var strengthPlanID: String?
    var targetMeters: Double?
    var targetSeconds: Double?
    var notes: String = ""
    var programID: String?
    var routeID: String?
    var status: TrainingSessionStatus = .scheduled
    var isAllDay: Bool?
    var sortDate: Date { scheduledAt }
    var isValid: Bool {
        UUID(uuidString: id) != nil && !userId.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (kind == .strength ? sport == nil : sport != nil)
        && (targetMeters.map { $0.isFinite && $0 > 0 } ?? true)
        && (targetSeconds.map { $0.isFinite && $0 > 0 } ?? true)
    }
    var symbol: String { kind == .strength ? "dumbbell.fill" : sport?.symbol ?? "figure.run" }
    func targetLabel(unit: String) -> String {
        [targetMeters.map { EnduranceFormat.distance($0, unit: unit) },
         targetSeconds.map { "\(Int($0 / 60)) min" }].compactMap { $0 }.joined(separator: " · ")
    }
}

struct SavedEnduranceRoute: EnduranceEntity, Hashable {
    static let table = "endurance_routes"
    var id: String = UUID().uuidString.lowercased()
    var userId: String
    var title: String
    var sport: EnduranceSport
    var distanceMeters: Double
    var points: [EnduranceRoutePoint]
    var sourceActivityID: String
    var createdAt: Date = Date()
    var sortDate: Date { createdAt }
    var isValid: Bool {
        UUID(uuidString: id) != nil && !userId.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && distanceMeters.isFinite && distanceMeters > 0 && points.count >= 2 && points.allSatisfy(\.isValid)
    }
}

struct EndurancePersonalBest: Identifiable, Hashable {
    var id: String
    var title: String
    var activityID: String
    var sport: EnduranceSport
    var value: Double
    var isTime: Bool
    var achievedAt: Date
}

struct EnduranceMonth: Identifiable {
    var start: Date
    var distance: Double
    var seconds: Double
    var count: Int
    var id: Date { start }
}

enum EnduranceInsights {
    static func records(_ activities: [EnduranceActivity], userID: String) -> [EndurancePersonalBest] {
        let owned = activities.filter { $0.userId == userID && $0.isValid && $0.endedAt <= Date() }
        var records: [EndurancePersonalBest] = []
        for sport in EnduranceSport.allCases {
            let matching = owned.filter { $0.sport == sport }
            if let longest = matching.filter({ $0.distanceMeters > 0 }).max(by: { $0.distanceMeters < $1.distanceMeters }) {
                records.append(.init(id: "longest-\(sport.rawValue)", title: "Longest \(sport.rawValue)", activityID: longest.id,
                    sport: sport, value: longest.distanceMeters, isTime: false, achievedAt: longest.startedAt))
            }
            if sport == .run {
                for kilometers in [1, 5, 10] {
                    let candidates: [(EnduranceActivity, Double)] = matching.compactMap { activity in
                        guard let time = bestBlock(activity.splits, kilometers: kilometers) else { return nil }
                        return (activity, time)
                    }
                    if let best = candidates.min(by: { $0.1 < $1.1 }) {
                        records.append(.init(id: "run-\(kilometers)k", title: "Best \(kilometers) km block", activityID: best.0.id,
                            sport: sport, value: best.1, isTime: true, achievedAt: best.0.startedAt))
                    }
                }
            }
        }
        return records
    }
    /// Only complete, consecutive kilometre splits qualify. Never extrapolate
    /// an imported workout's pace into a personal best it did not measure.
    static func bestBlock(_ splits: [EnduranceSplit], kilometers: Int) -> Double? {
        guard kilometers > 0, splits.count >= kilometers else { return nil }
        var best: Double?
        for offset in 0...(splits.count - kilometers) {
            let block = Array(splits[offset..<(offset + kilometers)])
            guard block.enumerated().allSatisfy({ index, split in
                abs(split.distanceMeters - 1_000) < 0.01 && split.activeSeconds.isFinite && split.activeSeconds > 0
                && split.number == block[0].number + index
            }) else { continue }
            let time = block.reduce(0) { $0 + $1.activeSeconds }
            best = min(best ?? time, time)
        }
        return best
    }
    static func months(_ activities: [EnduranceActivity], userID: String, now: Date = Date(), calendar: Calendar = .current) -> [EnduranceMonth] {
        guard let current = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (-5...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: offset, to: current),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let matching = activities.filter { $0.userId == userID && $0.startedAt >= start && $0.startedAt < end && $0.endedAt <= now }
            return .init(start: start, distance: matching.reduce(0) { $0 + $1.distanceMeters },
                seconds: matching.reduce(0) { $0 + $1.activeSeconds }, count: matching.count)
        }
    }
    static func milestones(_ activities: [EnduranceActivity], userID: String) -> [String] {
        awards(activities, userID: userID).map(\.title)
    }
    static func awards(_ activities: [EnduranceActivity], userID: String, now: Date = Date()) -> [EnduranceAward] {
        let owned = activities.filter { $0.userId == userID && $0.isValid && $0.endedAt <= now }
            .sorted { $0.endedAt == $1.endedAt ? $0.id < $1.id : $0.endedAt < $1.endedAt }
        var result: [EnduranceAward] = []
        func add(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ mark: String, _ activity: EnduranceActivity?) {
            guard let activity else { return }
            result.append(.init(id: id, title: title, detail: detail, symbol: symbol, mark: mark, earnedAt: activity.endedAt, activityID: activity.id))
        }
        add("first", "First adventure", "Your first completed run, walk or ride in Shift. Apple Health imports count too.", "figure.walk", "01", owned.first)
        add("5k", "First 5K run", "Complete a run of at least 5 kilometres in a single activity.", "figure.run", "5K", owned.first { $0.sport == .run && $0.distanceMeters >= 5_000 })
        add("ride20", "20 km ride", "Complete a ride of at least 20 kilometres in a single activity.", "figure.outdoor.cycle", "20", owned.first { $0.sport == .cycle && $0.distanceMeters >= 20_000 })
        for count in [10, 50] where owned.count >= count {
            add("count\(count)", "\(count) activities", "Complete \(count) runs, walks or rides. Every completed activity counts, including Apple Health imports.", "flame.fill", "\(count)", owned[count - 1])
        }
        var distance = 0.0
        if let crossing = owned.first(where: { distance += $0.distanceMeters; return distance >= 100_000 }) {
            add("distance100", "100 km explored", "Cover a total of 100 kilometres across your completed runs, walks and rides.", "mountain.2.fill", "100", crossing)
        }
        return result
    }
}

struct EnduranceAward: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var mark: String
    var earnedAt: Date
    /// The activity that crossed the threshold, using its original completion date.
    var activityID: String
}

struct EnduranceProgramTemplate: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var sport: EnduranceSport
    var weeks: Int
    var sessionsPerWeek: Int
    var initialMinutes: Int
    var weeklyMinutes: Int
    static let all: [Self] = [
        .init(id: "walk", title: "Build a walking habit", subtitle: "4 weeks · 3 walks a week", sport: .walk, weeks: 4, sessionsPerWeek: 3, initialMinutes: 15, weeklyMinutes: 5),
        .init(id: "run", title: "Consistent running", subtitle: "6 weeks · 3 easy runs a week", sport: .run, weeks: 6, sessionsPerWeek: 3, initialMinutes: 15, weeklyMinutes: 3),
        .init(id: "ride", title: "Weekend rider", subtitle: "6 weeks · 2 rides a week", sport: .cycle, weeks: 6, sessionsPerWeek: 2, initialMinutes: 25, weeklyMinutes: 5)
    ]
    func sessions(userID: String, starting: Date, calendar: Calendar = .current) -> [TrainingSession] {
        let programID = UUID().uuidString.lowercased()
        let days = sessionsPerWeek == 3 ? [0, 2, 5] : [0, 4]
        return (0..<weeks).flatMap { week in days.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: starting) else { return nil }
            return TrainingSession(userId: userID, title: "\(title) · Week \(week + 1)", scheduledAt: date, kind: .endurance,
                sport: sport, targetSeconds: Double((initialMinutes + weeklyMinutes * week) * 60),
                notes: "Easy, conversational effort. Adjust the duration or move the session to fit your week.", programID: programID)
        } }
    }
}

struct EnduranceWidgetData: Codable {
    var weekStart: Date
    var distanceMeters: Double
    var activeSeconds: Double
    var activities: Int
    var distanceUnit: String
    var distanceGoalMeters: Double?
    var runMeters: Double
    var walkMeters: Double
    var cycleMeters: Double
    var nextSessions: [TrainingSession]
    var weather: OutdoorWeatherBrief? = nil
    func normalized(at date: Date, calendar: Calendar = .current) -> Self {
        var copy = self
        if copy.weather?.isFresh(at: date) != true { copy.weather = nil }
        if let end = calendar.date(byAdding: .day, value: 7, to: weekStart), date >= end {
            copy.distanceMeters = 0; copy.activeSeconds = 0; copy.activities = 0
            copy.runMeters = 0; copy.walkMeters = 0; copy.cycleMeters = 0
        }
        copy.nextSessions = nextSessions.filter { $0.status == .scheduled && $0.scheduledAt >= calendar.startOfDay(for: date) }
        return copy
    }
}

struct WatchEnduranceContext: Codable {
    var summary: EnduranceWidgetData
    var goals: [WatchEnduranceGoal]
    var routes: [WatchRouteSummary]
    var phoneRecording: Bool
}
struct WatchEnduranceGoal: Codable, Identifiable {
    var id: String
    var title: String
    var progress: Double
    var target: Double
    var unit: String
}
struct WatchRouteSummary: Codable, Identifiable {
    var id: String
    var title: String
    var sport: EnduranceSport
    var distanceMeters: Double
}

enum EnduranceAchievementPolicy {
    static func shouldCelebrate(_ activity: EnduranceActivity, previousIDs: Set<String>, now: Date = Date()) -> Bool {
        activity.isValid && activity.source == "shift" && !previousIDs.contains(activity.id)
            && activity.endedAt <= now && activity.endedAt >= now.addingTimeInterval(-6 * 3_600)
    }
}

/// Link an unscheduled start only when one matching planned session exists.
/// Multiple sessions on the same day always need an explicit choice.
enum TrainingLinkPolicy {
    static func candidate(sessions: [TrainingSession], userID: String, kind: TrainingSessionKind,
        sport: EnduranceSport? = nil, planID: String? = nil, date: Date, excluding: Set<String>, calendar: Calendar = .current) -> String? {
        let matching = sessions.filter { $0.userId == userID && $0.kind == kind && $0.status == .scheduled
            && $0.sport == sport && $0.strengthPlanID == planID && !excluding.contains($0.id)
            && calendar.isDate($0.scheduledAt, inSameDayAs: date) }
        return matching.count == 1 ? matching.first?.id : nil
    }
}
