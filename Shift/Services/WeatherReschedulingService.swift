import Foundation
import Observation
import BackgroundTasks
import UserNotifications

enum WeatherReviewError: LocalizedError {
    case changed, unavailable, calendar, pro
    var errorDescription: String? {
        switch self {
        case .changed: return "This session or its forecast has changed. Check again before moving it. Your original time is unchanged."
        case .unavailable: return "Couldn't check the forecast. Your session is unchanged. Try again when you're connected."
        case .calendar: return "Reconnect Apple Calendar before moving this session, or edit its weather preferences to turn off Calendar checking."
        case .pro: return "Weather rescheduling suggestions are included with Shift Pro."
        }
    }
}

@MainActor @Observable
final class WeatherReschedulingService {
    static let shared = WeatherReschedulingService()
    static let backgroundID = "com.zuhayrk.shift.weather-review"
    private(set) var suggestions: [WeatherRescheduleSuggestion] = []
    private(set) var checking = false
    private(set) var error: String?
    private(set) var checkedAt: Date?
    private var owner: String?
    private var generation = UUID()
    private var lastAttempt: Date?
    private var hasWatchedSessions = false

    func clear() {
        generation = UUID(); suggestions = []; checking = false; error = nil; checkedAt = nil; lastAttempt = nil; owner = nil; hasWatchedSessions = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
    }
    func scheduleBackgroundCheck() {
        guard authManager.currentUserId != nil, StoreService.shared.isPro, hasWatchedSessions else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
        request.earliestBeginDate = Date().addingTimeInterval(3 * 3_600)
        // iOS chooses when to run this. A rejected request leaves foreground checks available.
        try? BGTaskScheduler.shared.submit(request)
    }
    func backgroundRefresh() async {
        // A cold launch may still be restoring the account. Do not read a
        // different user's cached ID or trigger sign-in/permission UI here.
        for _ in 0..<20 where authManager.isLoading {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
        guard !Task.isCancelled, !authManager.isLoading else { return }
        await refresh(force: true)
    }
    func refresh(force: Bool = false, notify: Bool = true) async {
        #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
        if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen == "weather-changes" { capturePreview(); return }
        #endif
        guard let user = authManager.currentUserId else { clear(); return }
        if owner != user { clear(); owner = user }
        guard !checking else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 900 { return }
        let pass = generation
        checking = true; error = nil; lastAttempt = Date()
        defer { if pass == generation { checking = false } }
        guard await StoreService.verifyProEntitlement(), authManager.currentUserId == user, pass == generation else {
            if pass == generation {
                suggestions = []; BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
                await NotificationManager.removeNotifications(withPrefixes: ["shift.weather.change.\(user)."])
            }
            return
        }
        do {
            let data = try await records(owner: user)
            try Task.checkCancellation()
            let eligible = data.sessions.filter { WeatherReschedulingPolicy.eligible($0, owner: user, completed: data.completed, now: Date()) }
            guard pass == generation, authManager.currentUserId == user else { return }
            hasWatchedSessions = !eligible.isEmpty
            guard !eligible.isEmpty else {
                guard pass == generation, authManager.currentUserId == user else { return }
                suggestions = []; checkedAt = Date()
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
                await pruneNotifications(owner: user, activeIDs: [])
                return
            }
            var snapshots: [WeatherPlanLocation: OutdoorWeatherSnapshot] = [:]
            var attempted = Set<WeatherPlanLocation>()
            var results: [WeatherRescheduleSuggestion] = []
            var failed = false
            // A generated week shares one lookup area. Limit work in an iOS refresh slot.
            for session in eligible.sorted(by: { $0.scheduledAt < $1.scheduledAt }).prefix(14) {
                try Task.checkCancellation()
                guard pass == generation, authManager.currentUserId == user else { return }
                let plan = session.weatherPlan!
                do {
                    let forecast: OutdoorWeatherSnapshot
                    if let cached = snapshots[plan.location] { forecast = cached }
                    else {
                        guard attempted.count < 3, attempted.insert(plan.location).inserted else { failed = true; continue }
                        forecast = try await EnduranceWeatherService.forecast(for: plan.location)
                        snapshots[plan.location] = forecast
                    }
                    let busy = try busyTimes(session: session, sessions: data.sessions, completed: data.completed)
                    if let result = WeatherReschedulingPolicy.review(session, weather: forecast, busy: busy) { results.append(result) }
                } catch is CancellationError { throw CancellationError() }
                catch { failed = true }
            }
            guard pass == generation, authManager.currentUserId == user, !Task.isCancelled else { return }
            suggestions = results.sorted { $0.session.scheduledAt < $1.session.scheduledAt }
            checkedAt = Date()
            error = failed ? "Some sessions couldn't be checked. Reconnect Calendar or try again when you're online. No sessions have moved." : nil
            scheduleBackgroundCheck()
            await pruneNotifications(owner: user, activeIDs: Set(results.map(\.id)))
            if notify {
                for result in results { if await notifyChange(result, owner: user) { break } }
            }
        } catch is CancellationError { }
        catch { if pass == generation { suggestions = []; self.error = WeatherReviewError.unavailable.localizedDescription } }
    }
    func confirm(_ suggestion: WeatherRescheduleSuggestion) async throws {
        let user = try authManager.requireUserId()
        guard user == suggestion.session.userId, let selected = suggestion.alternative else { throw WeatherReviewError.changed }
        guard await StoreService.verifyProEntitlement() else { throw WeatherReviewError.pro }
        guard authManager.currentUserId == user else { throw EnduranceError.wrongAccount }
        let data = try await records(owner: user)
        guard let session = data.sessions.first(where: { $0.id == suggestion.id }), session == suggestion.session,
              WeatherReschedulingPolicy.eligible(session, owner: user, completed: data.completed, now: Date()), let plan = session.weatherPlan else { throw WeatherReviewError.changed }
        let forecast = try await EnduranceWeatherService.forecast(for: plan.location)
        let busy = try busyTimes(session: session, sessions: data.sessions, completed: data.completed)
        // Recompute using the current forecast and Calendar. Never silently select a different time.
        guard let latest = WeatherReschedulingPolicy.review(session, weather: forecast, busy: busy),
              latest.alternative?.start == selected.start, let seconds = session.targetSeconds,
              let conditions = WeatherSessionConditions.read(start: selected.start, seconds: seconds, weather: forecast, now: Date()),
              authManager.currentUserId == user, !Task.isCancelled else { throw WeatherReviewError.changed }
        var replacement = session
        replacement.scheduledAt = selected.start
        replacement.weatherPlan?.baseline = conditions
        replacement.weatherPlan?.checkedAt = forecast.fetchedAt
        replacement.weatherPlan?.dismissedChange = nil
        // Replace old weather notes instead of leaving a dry forecast for the old time.
        replacement.notes += "\nMoved with your approval after a forecast change. \(selected.weatherSummary) · \(plan.location.place)."
        // Calendar permission/events may have changed while WeatherKit was loading.
        let finalBusy = try busyTimes(session: session, sessions: data.sessions, completed: data.completed)
        guard !finalBusy.contains(where: { $0.start < selected.start.addingTimeInterval(seconds) && $0.end > selected.start }) else { throw WeatherReviewError.changed }
        try await EnduranceStore.shared.replaceWeatherSession(session, with: replacement)
        guard authManager.currentUserId == user else { return }
        await didChange(owner: user, sessionID: session.id)
        await refresh(force: true, notify: false)
    }
    func keep(_ suggestion: WeatherRescheduleSuggestion) async throws {
        let user = try authManager.requireUserId()
        guard suggestion.session.userId == user else { throw EnduranceError.wrongAccount }
        guard await StoreService.verifyProEntitlement() else { throw WeatherReviewError.pro }
        guard authManager.currentUserId == user else { throw EnduranceError.wrongAccount }
        var replacement = suggestion.session
        replacement.weatherPlan?.dismissedChange = suggestion.changeKey
        try await EnduranceStore.shared.replaceWeatherSession(suggestion.session, with: replacement)
        guard authManager.currentUserId == user else { return }
        await didChange(owner: user, sessionID: suggestion.id)
    }
    private func didChange(owner: String, sessionID: String) async {
        suggestions.removeAll { $0.id == sessionID }
        await NotificationManager.removeNotifications(withPrefixes: ["shift.weather.change.\(owner).\(sessionID)"])
        SyncService.flushInBackground()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await TrainingNotificationService.reconcile()
        await EnduranceService.refreshSummaries()
    }
    private func records(owner: String) async throws -> (sessions: [TrainingSession], completed: Set<String>) {
        async let sessions = EnduranceStore.shared.all(TrainingSession.self, userID: owner)
        async let activities = EnduranceStore.shared.all(EnduranceActivity.self, userID: owner)
        async let draft = EnduranceStore.shared.draft(userID: owner)
        let values = try await (sessions, activities, draft)
        return (values.0, Set(values.1.compactMap(\.trainingSessionID)).union([values.2?.trainingSessionID].compactMap { $0 }))
    }
    private func busyTimes(session: TrainingSession, sessions: [TrainingSession], completed: Set<String>) throws -> [DateInterval] {
        var busy = WeatherReschedulingPolicy.busyTimes(sessions: sessions, excluding: session, completed: completed)
        if session.weatherPlan?.checkCalendar == true, let plan = session.weatherPlan {
            let reader = PlannerCalendarService(); reader.enabled = true
            do { busy += try reader.busyTimes(starting: plan.weekStart, calendar: plan.calendar) }
            catch { throw WeatherReviewError.calendar }
        }
        return busy
    }
    private func pruneNotifications(owner: String, activeIDs: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "shift.weather.change.\(owner)."
        let delivered = await center.deliveredNotifications()
        let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) && !activeIDs.contains(String($0.dropFirst(prefix.count))) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    private func notifyChange(_ suggestion: WeatherRescheduleSuggestion, owner: String) async -> Bool {
        guard authManager.currentUserId == owner,
              (try? await ProfileRepository.findById(owner))?.settings.notifications.weatherChanges == true,
              await StoreService.verifyProEntitlement(), !Task.isCancelled else { return false }
        guard let current = try? await records(owner: owner), current.sessions.first(where: { $0.id == suggestion.id }) == suggestion.session,
              WeatherReschedulingPolicy.eligible(suggestion.session, owner: owner, completed: current.completed, now: Date()) else { return false }
        let cooldownKey = "shift.weather.lastAlert.\(owner)"
        if let last = UserDefaults.standard.object(forKey: cooldownKey) as? Date, Date().timeIntervalSince(last) < 24 * 3_600 { return false }
        let event = owner + ".weather." + suggestion.id + "." + suggestion.changeKey
        let sent = await NotificationEventLedger.shared.deliverOnce(eventKey: event,
            identifier: "shift.weather.change.\(owner).\(suggestion.id)", title: "Your training forecast changed",
            body: "Check the updated weather for \(suggestion.session.title). Your session hasn't moved.", kind: "weather",
            userInfo: ["ownerId": owner, "trainingSessionId": suggestion.id, "trainingDate": TrainingScheduleSettings.dateKey(suggestion.session.scheduledAt)])
        if sent { UserDefaults.standard.set(Date(), forKey: cooldownKey) }
        return sent
    }
    func clearDeletedAccount(_ owner: String) {
        UserDefaults.standard.removeObject(forKey: "shift.weather.lastAlert.\(owner)")
        clear()
    }
    func reconcileSavedSessions() async {
        guard let owner = authManager.currentUserId else { clear(); return }
        generation = UUID(); let pass = generation; checking = false
        do {
            let data = try await records(owner: owner)
            guard authManager.currentUserId == owner, pass == generation else { return }
            hasWatchedSessions = data.sessions.contains { WeatherReschedulingPolicy.eligible($0, owner: owner, completed: data.completed, now: Date()) }
            if hasWatchedSessions { scheduleBackgroundCheck() }
            else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID) }
            suggestions.removeAll { item in
                data.sessions.first(where: { $0.id == item.id }) != item.session
                    || !WeatherReschedulingPolicy.eligible(item.session, owner: owner, completed: data.completed, now: Date())
            }
            await pruneNotifications(owner: owner, activeIDs: Set(suggestions.map(\.id)))
            lastAttempt = nil
        } catch { if pass == generation { suggestions = [] } }
    }
    #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
    private func capturePreview() {
        let now = Date(), calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let scheduled = calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(10 * 3_600)
        let location = WeatherPlanLocation(latitude: 51.51, longitude: -0.13, place: "London")
        var session = TrainingSession(userId: StoreCaptureConfiguration.owner, title: "Easy park run", scheduledAt: scheduled, kind: .endurance, sport: .run, targetSeconds: 1_800)
        session.weatherPlan = .init(location: location, availability: (1...7).map { .init(weekday: $0, startMinute: 9*60, endMinute: 12*60) },
            weekStart: start, weekEnd: calendar.date(byAdding: .day, value: 7, to: start)!, timeZoneID: calendar.timeZone.identifier,
            preferDry: true, daylightOnly: true, checkCalendar: false,
            baseline: .init(rain: 0.1, wind: 8, gust: 12, low: 14, high: 14, uv: 1, dark: false, hazardous: false), checkedAt: now.addingTimeInterval(-600))
        let hours: [OutdoorWeatherHour] = (0..<192).map { index in
            let date = start.addingTimeInterval(Double(index)*3_600)
            return .init(date: date, celsius: 14, rainChance: date == scheduled ? 0.85 : 0.1, windKPH: 8, gustKPH: 12, uv: 1,
                daylight: true, hazardous: false, condition: date == scheduled ? "Rain" : "Partly cloudy", symbol: date == scheduled ? "cloud.rain" : "cloud.sun")
        }
        let forecast = OutdoorWeatherSnapshot(fetchedAt: now, place: "London", current: hours[0], hours: hours, location: location)
        suggestions = WeatherReschedulingPolicy.review(session, weather: forecast, busy: [], now: now).map { [$0] } ?? []
        checkedAt = now; checking = false; error = nil
    }
    #endif
}
