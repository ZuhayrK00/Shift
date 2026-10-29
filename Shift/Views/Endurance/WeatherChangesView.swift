import SwiftUI

struct WeatherChangesView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(StoreService.self) private var store
    @State private var service = WeatherReschedulingService.shared
    @State private var showPro = false
    @State private var moving: WeatherRescheduleSuggestion?
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("A better time to head out", systemImage: "cloud.sun.fill").font(.title2.bold())
                Text("If the forecast gets worse, review another time that fits your plan. Your session stays put until you approve the change.")
                    .foregroundStyle(colors.muted)
                if store.isPro {
                    if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(colors.success) }
                    if service.checking { ProgressView("Checking your planned sessions…") }
                    if service.suggestions.isEmpty && !service.checking {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "calendar.badge.checkmark").font(.largeTitle).foregroundStyle(colors.enduranceAccent)
                            Text("No changes to review").font(.headline)
                            Text("Turn on Watch for forecast changes when building a week, or open a planned session's weather preferences. Only future sessions with a saved forecast and availability can be checked.")
                                .font(.subheadline).foregroundStyle(colors.muted)
                        }.enduranceCard()
                    }
                    ForEach(service.suggestions) { suggestion in card(suggestion) }
                    if let checked = service.checkedAt {
                        Text("Checked \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(colors.muted)
                    }
                    if let problem = error ?? service.error { Text(problem).font(.footnote).foregroundStyle(colors.warning) }
                    Button("Check forecasts again", systemImage: "arrow.clockwise") {
                        error = nil; Task { await service.refresh(force: true, notify: false) }
                    }.buttonStyle(.bordered).disabled(service.checking || busy)
                    WeatherAttributionView()
                    NavigationLink { NotificationSettingsPage() } label: { Label("Forecast notifications", systemImage: "bell") }
                } else {
                    EnduranceProCard(title: "Keep your plan in step with the weather", message: "Shift Pro can watch planned runs, walks and rides and suggest better times for you to approve.") { showPro = true }
                }
                Text("Background checks depend on iOS and your connection. Missing or stale forecasts don't trigger a move. Always check local conditions before heading out.")
                    .font(.caption).foregroundStyle(colors.muted)
            }.padding(20).disabled(busy)
        }.background(colors.bg).foregroundStyle(colors.text).tint(colors.enduranceAccent)
            .navigationTitle("Forecast changes").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task(id: auth.currentUserId) { await service.refresh(force: true, notify: false) }
            .onChange(of: store.isPro) { _, _ in Task { await service.refresh(force: true, notify: false) } }
            .refreshable { await service.refresh(force: true, notify: false) }
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .confirmationDialog("Move this session?", isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }), presenting: moving) { suggestion in
                Button("Confirm new time") { perform { try await service.confirm(suggestion); message = "Session moved. Your reminders, Watch and widgets will use the new time." } }
                Button("Cancel", role: .cancel) { moving = nil }
            } message: { suggestion in
                if let alternative = suggestion.alternative {
                    Text("\(suggestion.session.title)\n\(timeLabel(suggestion.session.scheduledAt, suggestion: suggestion)) → \(timeLabel(alternative.start, suggestion: suggestion))")
                }
            }
    }
    private func card(_ suggestion: WeatherRescheduleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(suggestion.session.title, systemImage: suggestion.session.symbol).font(.headline)
            Text(suggestion.reason).foregroundStyle(colors.warning)
            Text("Planned: \(timeLabel(suggestion.session.scheduledAt, suggestion: suggestion))").font(.subheadline)
            if let alternative = suggestion.alternative {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested time").font(.caption).foregroundStyle(colors.muted)
                    Text(timeLabel(alternative.start, suggestion: suggestion)).font(.headline)
                    Text(alternative.weatherSummary).font(.caption).foregroundStyle(colors.muted)
                    if let forecast = alternative.forecast {
                        Label("\(OutdoorWeatherPanel.temperature(forecast.celsius)) · \(forecast.condition)", systemImage: forecast.symbol).font(.subheadline)
                    }
                    Text(suggestion.session.weatherPlan?.location.place ?? "").font(.caption).foregroundStyle(colors.muted)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(colors.enduranceSoft, in: RoundedRectangle(cornerRadius: 14))
                Button("Move to this time", systemImage: "calendar.badge.clock") { moving = suggestion }
                    .buttonStyle(.borderedProminent).tint(colors.enduranceAccent).foregroundStyle(colors.onAccent)
            } else {
                Text("No better forecast-backed time fits your remaining availability this week. Keep this time, change your availability, or choose an indoor session.")
                    .font(.subheadline).foregroundStyle(colors.muted)
            }
            Button("Keep original time") { perform { try await service.keep(suggestion); message = "Original time kept. This forecast change is dismissed." } }
                .font(.subheadline)
        }.enduranceCard()
    }
    private func timeLabel(_ date: Date, suggestion: WeatherRescheduleSuggestion) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = suggestion.session.weatherPlan?.calendar.timeZone ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM jmm z")
        return formatter.string(from: date)
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true; error = nil; moving = nil
        Task {
            defer { busy = false }
            do { try await action() }
            catch { self.error = error.localizedDescription; await service.refresh(force: true, notify: false) }
        }
    }
}

/// Gives older/manual sessions explicit availability; no availability is inferred.
struct WeatherPlanPreferencesView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession
    var onSaved: ((TrainingSession) -> Void)? = nil
    @State private var enabled = false
    @State private var windows: [EnduranceAvailabilityWindow] = []
    @State private var dry = true
    @State private var daylight = true
    @State private var calendarReader = PlannerCalendarService()
    @State private var weather = EnduranceWeatherService.shared
    @State private var showWeather = false
    @State private var showPro = false
    @State private var saving = false
    @State private var error: String?
    private let days = [(1,"Monday"),(2,"Tuesday"),(3,"Wednesday"),(4,"Thursday"),(5,"Friday"),(6,"Saturday"),(7,"Sunday")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your time, with a weather backup").font(.title2.bold())
                Text("Choose the times you'd be happy to move this session to. Shift will suggest a change if conditions worsen; you always confirm the move.").foregroundStyle(colors.muted)
                if store.isPro {
                    Toggle("Watch for forecast changes", isOn: $enabled)
                    if enabled {
                        Text("Suggestions stay within the seven-day plan and use its saved time zone. A new check starts from the forecast available when you save these preferences.").font(.caption).foregroundStyle(colors.muted)
                        ForEach(days, id: \.0) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(day.1).font(.headline); Spacer()
                                    Button("Add time", systemImage: "plus") { windows.append(.init(weekday: day.0, startMinute: day.0 <= 5 ? 18*60 : 9*60, endMinute: day.0 <= 5 ? 20*60 : 11*60)) }
                                        .font(.caption).disabled(windows.filter { $0.weekday == day.0 }.count >= 4)
                                }
                                if !windows.contains(where: { $0.weekday == day.0 }) { Text("Unavailable").font(.caption).foregroundStyle(colors.muted) }
                                ForEach(windows.filter { $0.weekday == day.0 }) { window in
                                    HStack {
                                        DatePicker("From", selection: time(window.id, start: true), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("\(day.1) start")
                                        Text("to").font(.caption)
                                        DatePicker("Until", selection: time(window.id, start: false), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("\(day.1) end")
                                        Spacer(minLength: 0)
                                        Button { windows.removeAll { $0.id == window.id } } label: { Image(systemName: "minus.circle.fill") }.accessibilityLabel("Remove \(day.1) time")
                                    }
                                }
                            }.enduranceCard()
                        }
                        Toggle("Prefer drier conditions", isOn: $dry)
                        Toggle("Daylight only", isOn: $daylight)
                        Toggle("Avoid Calendar clashes", isOn: Binding(get: { calendarReader.enabled }, set: { value in
                            if value { Task { await calendarReader.connect() } } else { calendarReader.disconnect() }
                        })).disabled(calendarReader.requesting)
                        if let calendarError = calendarReader.error { Text(calendarError).font(.caption).foregroundStyle(colors.warning) }
                        if let location = session.weatherPlan?.location { Label("Planning area: \(location.place)", systemImage: "location").font(.subheadline) }
                        else {
                            OutdoorWeatherPanel(sport: session.sport ?? .run)
                            Button("Choose weather area") { showWeather = true }
                        }
                        Text("The planning area is saved as a rounded weather lookup point. These preferences sync with your session. Apple Calendar events stay on this device.").font(.caption).foregroundStyle(colors.muted)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(colors.warning) }
                    Button(saving ? "Saving…" : "Save preferences") { Task { await save() } }
                        .buttonStyle(.borderedProminent).tint(colors.enduranceAccent).foregroundStyle(colors.onAccent)
                } else {
                    EnduranceProCard(title: "Forecast changes with Shift Pro", message: "Watch for changes and review better times for your planned runs, walks and rides.") { showPro = true }
                }
            }.padding(20).disabled(saving)
        }.background(colors.bg).foregroundStyle(colors.text).tint(colors.enduranceAccent)
            .navigationTitle("Weather preferences").navigationBarTitleDisplayMode(.inline)
            .task {
                enabled = session.weatherPlan?.enabled ?? false; windows = session.weatherPlan?.availability ?? []
                dry = session.weatherPlan?.preferDry ?? true; daylight = session.weatherPlan?.daylightOnly ?? true
                calendarReader.enabled = session.weatherPlan?.checkCalendar ?? false
                await weather.activate(owner: auth.currentUserId)
            }
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .sheet(isPresented: $showWeather) { OutdoorWeatherSettingsView() }
            .scrollDismissesKeyboard(.interactively)
    }
    private func time(_ id: UUID, start: Bool) -> Binding<Date> {
        Binding(get: {
            let window = windows.first { $0.id == id }
            let minute = (start ? window?.startMinute : window?.endMinute) ?? 0
            return Calendar.current.date(bySettingHour: minute / 60 % 24, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: { value in
            guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
            let minute = Calendar.current.component(.hour, from: value)*60 + Calendar.current.component(.minute, from: value)
            if start { windows[index].startMinute = minute } else { windows[index].endMinute = minute == 0 ? 1_440 : minute }
        })
    }
    private func save() async {
        saving = true; error = nil; defer { saving = false }
        do {
            guard await StoreService.verifyProEntitlement() else { throw WeatherReviewError.pro }
            guard auth.currentUserId == session.userId, session.status == .scheduled, session.scheduledAt > Date().addingTimeInterval(1_800) else { throw WeatherReviewError.changed }
            var replacement = session
            if enabled {
                guard !windows.isEmpty, windows.allSatisfy(\.isValid), let seconds = session.targetSeconds, (300...10_800).contains(seconds) else {
                    error = "Choose availability and set a session duration of 5–180 minutes before enabling forecast watching."; return
                }
                guard let location = session.weatherPlan?.location ?? weather.snapshot?.location else {
                    error = "Choose your weather area first."; return
                }
                let forecast = try await EnduranceWeatherService.forecast(for: location)
                var calendar = session.weatherPlan?.calendar ?? .current
                calendar.firstWeekday = 2
                let request = EndurancePlanningRequest(sport: session.sport ?? .run, sessions: 1, minutes: Int(ceil(seconds/60)),
                    starting: session.weatherPlan?.weekStart ?? session.scheduledAt, daylightOnly: daylight, preferDry: dry, availability: windows)
                guard let context = WeatherReschedulingPolicy.context(request: request, session: session, weather: forecast, checkCalendar: calendarReader.enabled, calendar: calendar) else {
                    error = "A complete forecast isn't available for this session yet. Try again closer to its date."; return
                }
                _ = try calendarReader.busyTimes(starting: context.weekStart, calendar: calendar)
                replacement.weatherPlan = context
            } else { replacement.weatherPlan = nil }
            guard auth.currentUserId == session.userId else { throw EnduranceError.wrongAccount }
            try await EnduranceStore.shared.updateWeatherPreferences(session, with: replacement)
            guard auth.currentUserId == session.userId else { return }
            onSaved?(replacement)
            SyncService.flushInBackground()
            NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
            await WeatherReschedulingService.shared.refresh(force: true, notify: false)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
