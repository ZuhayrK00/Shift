import Foundation
import Observation

@MainActor @Observable
final class TrainingHub {
    var sessions: [TrainingSession] = []
    var activities: [EnduranceActivity] = []
    var routes: [SavedEnduranceRoute] = []
    var workouts: [WorkoutSession] = []
    var plans: [WorkoutPlanWithCount] = []
    var error: String?
    var loading = false
    private var ownerID: String?
    private var loadID = UUID()
    func load() async {
        guard let owner = authManager.currentUserId else { clear(); return }
        if ownerID != owner { clear(); ownerID = owner }
        let pass = UUID(); loadID = pass
        loading = true
        defer { if loadID == pass { loading = false } }
        do {
            async let sessions = EnduranceStore.shared.all(TrainingSession.self, userID: owner)
            async let activities = EnduranceStore.shared.all(EnduranceActivity.self, userID: owner)
            async let routes = EnduranceStore.shared.all(SavedEnduranceRoute.self, userID: owner)
            async let workouts = SessionRepository.findCompleted(userId: owner)
            async let plans = PlanRepository.findPlansWithCount(userId: owner)
            let result = try await (sessions, activities, routes, workouts, plans)
            guard loadID == pass else { return }
            guard authManager.currentUserId == owner else { clear(); return }
            self.sessions = result.0; self.activities = result.1; self.routes = result.2
            self.workouts = result.3; self.plans = result.4; error = nil
        } catch { if loadID == pass { self.error = error.localizedDescription } }
    }
    func clear() { sessions = []; activities = []; routes = []; workouts = []; plans = []; ownerID = nil; error = nil }
    func completion(for session: TrainingSession) -> String? {
        if session.kind == .endurance { return activities.first { $0.trainingSessionID == session.id }?.id }
        return workouts.first { $0.id == session.id }?.id
    }
}

@MainActor
enum TrainingSummaryService {
    static func summary(userID: String, settings: UserSettings, activities: [EnduranceActivity], sessions: [TrainingSession], goals: [EnduranceGoal], completedStrengthIDs: Set<String> = [], workouts: [WorkoutSession] = [], planNames: [String: String] = [:], now: Date = Date()) -> EnduranceWidgetData {
        let start = GoalService.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let current = activities.filter { $0.userId == userID && $0.startedAt >= start && $0.endedAt <= now }
        let completed = Set(activities.compactMap(\.trainingSessionID)).union(completedStrengthIDs)
        let calendarSessions = TrainingCalendarProjection.expanded(sessions: sessions, settings: settings, userID: userID, from: now, days: 14, planNames: planNames, workouts: workouts)
        return EnduranceWidgetData(weekStart: start, distanceMeters: current.reduce(0) { $0 + $1.distanceMeters },
            activeSeconds: current.reduce(0) { $0 + $1.activeSeconds }, activities: current.count,
            distanceUnit: settings.distanceUnit,
            distanceGoalMeters: goals.first { $0.userId == userID && $0.period == .week && $0.metric == .distance && $0.sport == nil }?.target,
            runMeters: current.filter { $0.sport == .run }.reduce(0) { $0 + $1.distanceMeters },
            walkMeters: current.filter { $0.sport == .walk }.reduce(0) { $0 + $1.distanceMeters },
            cycleMeters: current.filter { $0.sport == .cycle }.reduce(0) { $0 + $1.distanceMeters },
            nextSessions: Array(calendarSessions.filter { $0.userId == userID && $0.status == .scheduled
                && $0.scheduledAt >= Calendar.current.startOfDay(for: now) && !completed.contains($0.id) }.sorted { $0.scheduledAt < $1.scheduledAt }.prefix(8)).map {
                    var summary = $0; summary.weatherPlan = nil; return summary
                },
            weather: EnduranceWeatherService.shared.brief(for: userID))
    }
}

@MainActor
enum TrainingCalendarProjection {
    static func expanded(sessions: [TrainingSession], settings: UserSettings, userID: String, from date: Date,
        days: Int, planNames: [String: String], workouts: [WorkoutSession], calendar: Calendar = .current) -> [TrainingSession] {
        // A weekly workout preference is not a calendar appointment. Only
        // explicitly saved sessions belong here; never invent dated sessions.
        sessions.filter { $0.userId == userID }.sorted { $0.scheduledAt < $1.scheduledAt }
    }
}
