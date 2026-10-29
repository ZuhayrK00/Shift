import SwiftUI

struct EndurancePlannerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreService.shared
    @State private var access = EnduranceProAccess.shared
    @State private var showPro = false
    @State private var request = EndurancePlanningRequest()
    @State private var goalText = ""
    @State private var explanation: String?
    @State private var error: String?
    @State private var aiBusy = false
    @State private var saving = false
    @State private var generating = false
    @State private var calendarReader = PlannerCalendarService()
    @State private var calendarTask: Task<Void, Never>?
    @State private var calendarWasChecked = false
    @FocusState private var goalFocused: Bool
    @State private var step = 0
    @State private var result: EndurancePlanningResult?
    @State private var excluded = Set<UUID>()
    @State private var hub = TrainingHub()
    @State private var weather = EnduranceWeatherService.shared
    @State private var reviewedWeather: OutdoorWeatherSnapshot?
    @State private var showWeather = false
    @State private var showCalendar = false
    @State private var aiTask: Task<Void, Never>?
    @State private var ownerAtOpen: String?
    @State private var programID = UUID().uuidString.lowercased()
    @State private var watchForecast = false
    private let days = [(1,"Monday"),(2,"Tuesday"),(3,"Wednesday"),(4,"Thursday"),(5,"Friday"),(6,"Saturday"),(7,"Sunday")]
    private var selected: [EndurancePlanSuggestion] { result?.suggestions.filter { !excluded.contains($0.id) } ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if access.decision.canPlan || saving || showCalendar {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in Capsule().fill(index <= step ? colors.enduranceAccent : colors.border).frame(height: 3) }
                }.accessibilityLabel("Step \(step + 1) of 3")
                if step == 0 { goalStep }
                else if step == 1 { availabilityStep }
                else { reviewStep }
                } else { planningGate }
                if let error { Text(error).font(.footnote).foregroundStyle(colors.danger) }
            }.padding(20).disabled(saving || generating)
        }.scrollDismissesKeyboard(.interactively).id(step).background(colors.bg).foregroundStyle(colors.text).tint(colors.enduranceAccent)
            .navigationTitle("Build my week").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .interactiveDismissDisabled(saving)
            .toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(step > 0)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { goalFocused = false; step -= 1; error = nil } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous step").disabled(saving || generating)
                    }
                }
            }
            .task(id: auth.currentUserId) {
                if ownerAtOpen != nil && ownerAtOpen != auth.currentUserId {
                    aiTask?.cancel(); calendarTask?.cancel(); calendarReader.disconnect()
                    request = .init(); goalText = ""; explanation = nil; result = nil; reviewedWeather = nil; step = 0
                }
                ownerAtOpen = auth.currentUserId; await store.updatePurchasedProducts(); await access.load(); await hub.load(); await weather.activate(owner: auth.currentUserId)
                #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
                if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen == "planner" {
                    request.sport = .walk; request.sessions = 5; request.minutes = 30
                    request.starting = StoreCapture.date(1)
                    request.availability = (1...7).map { .init(weekday: $0,startMinute: 12*60,endMinute: 14*60) }
                    reviewedWeather = weather.snapshot
                    result = EndurancePlanningEngine.suggest(request, weather: reviewedWeather, busy: existingBusyTimes)
                    calendarWasChecked = false; step = 2
                }
                #endif
            }
            .onChange(of: store.isPro) { _, _ in Task { await access.load() } }
            .onDisappear { aiTask?.cancel(); calendarTask?.cancel() }
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .sheet(isPresented: $showWeather) { OutdoorWeatherSettingsView() }
            .sheet(isPresented: $showCalendar, onDismiss: { EnduranceRecorder.shared.openPendingCalendarSession(); dismiss() }) { TrainingCalendarView(initialDate: request.starting) }
    }
    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if access.decision == .freeWeek { EnduranceFreeWeekNote() }
            Label("What’s the plan?", systemImage: "figure.walk").font(.title2.bold())
            Text("Set your goal. Pick your free time. Shift will find a place for each session.").foregroundStyle(colors.muted)
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell Shift what you're aiming for").font(.headline)
                TextField("Walk 5 times for 30 minutes. Weekdays 6–8pm, weekends 9–11am…", text: $goalText, axis: .vertical)
                    .lineLimit(3...6).focused($goalFocused).submitLabel(.done).onSubmit { goalFocused = false }
                    .padding(14).background(colors.surface2, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: goalText) { _, value in if value.count > 1_500 { goalText = String(value.prefix(1_500)) } }
                if let unavailable = EnduranceCoachService.unavailableReason { Text(unavailable).font(.footnote).foregroundStyle(colors.muted) }
                else {
                    Button(aiBusy ? "Filling in your plan…" : "Fill in my plan", systemImage: "text.badge.checkmark") { interpret() }
                        .buttonStyle(.bordered).disabled(aiBusy || goalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if aiBusy { CoachThinkingView(title: "Reading your goal") }
                    Text("Turns your description into the settings below. Runs privately on your device.").font(.caption).foregroundStyle(colors.muted)
                }
                if let explanation { Text(explanation).font(.subheadline).foregroundStyle(colors.enduranceAccent) }
            }.enduranceCard()
            VStack(alignment: .leading, spacing: 16) {
                Picker("Activity", selection: $request.sport) { ForEach(EnduranceSport.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }.pickerStyle(.segmented)
                Stepper("\(request.sessions) sessions this week", value: $request.sessions, in: 1...7)
                Stepper("\(request.minutes) minutes per session", value: $request.minutes, in: 5...180, step: 5)
                DatePicker("First day of your week", selection: $request.starting, in: Date()..., displayedComponents: .date)
                Text("Suggestions cover seven days. One session per day; nothing is saved until you approve it.").font(.footnote).foregroundStyle(colors.muted)
            }.enduranceCard()
            nextButton("Choose my availability") { goalFocused = false; aiTask?.cancel(); aiBusy = false; step = 1; error = nil }
        }
    }
    private var availabilityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When works for you?").font(.title2.bold())
            Text("Choose the days and windows you can actually make. Add more than one window if mornings and evenings both work.").foregroundStyle(colors.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { availabilityPresets }
                VStack(alignment: .leading, spacing: 8) { availabilityPresets }
            }
            ForEach(days, id: \.0) { day in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(day.1).font(.headline); Spacer(); Button("Add time", systemImage: "plus") { request.availability.append(.init(weekday: day.0, startMinute: day.0 <= 5 ? 18 * 60 : 9 * 60, endMinute: day.0 <= 5 ? 20 * 60 : 11 * 60)) }.font(.caption).disabled(request.availability.filter { $0.weekday == day.0 }.count >= 4) }
                    let windows = request.availability.filter { $0.weekday == day.0 }
                    if windows.isEmpty { Text("Unavailable").font(.caption).foregroundStyle(colors.muted) }
                    ForEach(windows) { window in
                        HStack {
                            DatePicker("From", selection: timeBinding(window.id, start: true), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("\(day.1) start time")
                            Text("to").font(.caption).foregroundStyle(colors.muted)
                            DatePicker("Until", selection: timeBinding(window.id, start: false), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("\(day.1) end time")
                            Spacer(minLength: 0)
                            Button { request.availability.removeAll { $0.id == window.id } } label: { Image(systemName: "minus.circle.fill").frame(width: 32, height: 36) }.foregroundStyle(colors.muted).accessibilityLabel("Remove \(day.1) window")
                        }
                    }
                }.enduranceCard()
            }
            calendarConnection
            VStack(alignment: .leading, spacing: 10) {
                if store.isPro {
                    Toggle("Watch for forecast changes", isOn: $watchForecast)
                } else {
                    Button { showPro = true } label: { Label("Forecast change suggestions · Pro", systemImage: "cloud.rain") }
                }
                Text("If conditions worsen, Shift can suggest a better time within this week's availability. Nothing moves until you confirm. Checks run when you open Shift and when iOS allows background refresh.")
                    .font(.caption).foregroundStyle(colors.muted)
            }.enduranceCard()
            VStack(alignment: .leading, spacing: 15) {
                Toggle("Prefer drier conditions", isOn: $request.preferDry)
                Toggle("Daylight only where forecast is available", isOn: $request.daylightOnly)
                OutdoorWeatherPanel(sport: request.sport)
                Button("Weather location and settings") { showWeather = true }.font(.subheadline)
                Text("Your chosen city applies to the whole week. If you'll be elsewhere, update it before generating suggestions.").font(.caption).foregroundStyle(colors.muted)
            }.enduranceCard()
            nextButton(generating ? "Finding your times…" : "Find my times") { Task { await generate() } }
                .disabled(request.availability.isEmpty || hub.loading || saving || generating || calendarReader.requesting)
        }
    }
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your week").font(.title2.bold())
            Text("\(selected.count) of \(request.sessions) sessions · \(request.minutes) minutes each").foregroundStyle(colors.muted)
            if calendarWasChecked {
                Label("Apple Calendar checked · busy times kept clear", systemImage: "calendar.badge.checkmark")
                    .font(.caption).foregroundStyle(colors.enduranceAccent)
            }
            if let reviewedWeather, reviewedWeather.isFresh(at: Date()) {
                Text("Forecast for \(reviewedWeather.place), checked \(reviewedWeather.fetchedAt.formatted(date: .omitted, time: .shortened)).").font(.footnote).foregroundStyle(colors.muted)
                WeatherAttributionView()
            }
            ForEach(result?.warnings ?? [], id: \.self) { warning in Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(colors.warning) }
            ForEach(result?.suggestions ?? []) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { !excluded.contains(item.id) }, set: { value in if value { excluded.remove(item.id) } else { excluded.insert(item.id) } })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.start, format: .dateTime.weekday(.wide).day().month()).font(.headline)
                            Text("\(item.start.formatted(date: .omitted, time: .shortened)) · \(request.minutes) min \(request.sport.rawValue)").font(.subheadline)
                        }
                    }
                    if let forecast = item.forecast { Label("\(OutdoorWeatherPanel.temperature(forecast.celsius)) · \(forecast.condition)", systemImage: forecast.symbol).font(.subheadline) }
                    Text(item.weatherSummary).font(.caption).foregroundStyle(colors.muted)
                    if let caution = item.caution { Text(caution).font(.caption).foregroundStyle(colors.warning) }
                }.enduranceCard()
            }
            Text(watchForecast ? "Shift will watch the forecast for this plan and suggest changes for you to approve. Your times stay fixed until you confirm a move." : "Times stay fixed after saving. You can turn on forecast change suggestions in a session's weather preferences with Shift Pro.").font(.footnote).foregroundStyle(colors.muted)
            nextButton(saving ? "Saving…" : "Save \(selected.count) sessions to Shift") { Task { await save() } }.disabled(saving || selected.isEmpty)
        }
    }
    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(16) }.buttonStyle(.plain)
            .foregroundStyle(colors.onAccent).background(colors.enduranceAccent, in: RoundedRectangle(cornerRadius: 16))
    }
    private func timeBinding(_ id: UUID, start: Bool) -> Binding<Date> {
        Binding(get: {
            guard let index = request.availability.firstIndex(where: { $0.id == id }) else { return Date() }
            let value = start ? request.availability[index].startMinute : request.availability[index].endMinute
            return Calendar.current.date(bySettingHour: (value / 60) % 24, minute: value % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            guard let index = request.availability.firstIndex(where: { $0.id == id }) else { return }
            let value = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if start { request.availability[index].startMinute = value } else { request.availability[index].endMinute = value == 0 ? 1_440 : value }
        })
    }
    private func interpret() {
        goalFocused = false; aiBusy = true; error = nil
        let owner = auth.currentUserId; let text = goalText
        aiTask?.cancel()
        aiTask = Task {
            defer { aiBusy = false }
            do {
                let intent = try await EnduranceCoachService.interpret(text)
                guard !Task.isCancelled, auth.currentUserId == owner, text == goalText else { return }
                request.sport = intent.sport; request.sessions = intent.sessions; request.minutes = intent.minutes
                if !intent.windows.isEmpty { request.availability = intent.windows }
                explanation = intent.explanation
            } catch let error as EnduranceProService.AccessError {
                if !Task.isCancelled { await handleAccessError(error) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func generate() async {
        guard !generating, !saving, let owner = auth.currentUserId, owner == ownerAtOpen else { return }
        guard request.availability.allSatisfy(\.isValid) else { error = "Each time window must end after it starts. Use separate windows for different days."; return }
        generating = true; error = nil; goalFocused = false
        defer { generating = false }
        do { try await EnduranceProService.requirePlanningAccess() }
        catch let error as EnduranceProService.AccessError { await handleAccessError(error); return }
        catch { self.error = error.localizedDescription; return }
        guard auth.currentUserId == owner else { return }
        await hub.load()
        guard auth.currentUserId == owner else { return }
        guard hub.error == nil else { error = "Couldn't check your Shift sessions. Please try again before scheduling."; return }
        do {
            let calendarBusy = try calendarReader.busyTimes(starting: request.starting)
            let busy = existingBusyTimes + calendarBusy
            reviewedWeather = weather.snapshot.flatMap { $0.isFresh(at: Date()) ? $0 : nil }
            result = EndurancePlanningEngine.suggest(request, weather: reviewedWeather, busy: busy)
            calendarWasChecked = calendarReader.enabled
            excluded = []; step = 2
        } catch { self.error = error.localizedDescription }
    }
    private var existingBusyTimes: [DateInterval] {
        hub.sessions.filter { $0.status == .scheduled && hub.completion(for: $0) == nil }
            .map { DateInterval(start: $0.scheduledAt, duration: $0.targetSeconds ?? 2_700) }
    }
    private var calendarConnection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { calendarReader.enabled }, set: { enabled in
                if enabled {
                    let owner = auth.currentUserId
                    calendarTask = Task {
                        await calendarReader.connect()
                        if Task.isCancelled || auth.currentUserId != owner { calendarReader.disconnect() }
                    }
                } else { calendarReader.disconnect() }
            })) {
                Label("Avoid Calendar clashes", systemImage: "calendar.badge.clock").font(.subheadline.weight(.semibold))
            }.disabled(calendarReader.requesting)
            Text("Fit sessions around busy events in Apple Calendar. Only busy times are checked, on this device. Your events aren't changed.")
                .font(.caption).foregroundStyle(colors.muted)
            if calendarReader.requesting { ProgressView("Connecting to Calendar…").font(.caption) }
            if let message = calendarReader.error { Text(message).font(.caption).foregroundStyle(colors.warning) }
        }.enduranceCard()
    }
    @ViewBuilder private var availabilityPresets: some View {
        preset("Weekday evenings", weekdays: Array(1...5), start: 18 * 60, end: 20 * 60)
        preset("Weekend mornings", weekdays: [6, 7], start: 9 * 60, end: 11 * 60)
    }
    private func preset(_ title: String, weekdays: [Int], start: Int, end: Int) -> some View {
        Button {
            request.availability.removeAll { weekdays.contains($0.weekday) }
            request.availability += weekdays.map { .init(weekday: $0, startMinute: start, endMinute: end) }
        } label: {
            Label(title, systemImage: "plus").font(.caption.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 11)
                .background(colors.enduranceSoft, in: Capsule()).foregroundStyle(colors.enduranceAccent)
        }.buttonStyle(.plain)
    }
    private func save() async {
        guard let owner = auth.currentUserId, owner == ownerAtOpen, !selected.isEmpty, !saving else { return }
        let approved = selected
        saving = true; error = nil; defer { saving = false }
        await hub.load()
        guard hub.error == nil, auth.currentUserId == owner else { error = "Couldn't recheck your calendar. Please try again."; return }
        do {
            let busy = existingBusyTimes + (try calendarReader.busyTimes(starting: request.starting))
            if approved.contains(where: { PlannerTimePolicy.overlaps($0, busy: busy) }) {
                error = "Your calendar changed and a time now overlaps. Go back one step to find new times."; return
            }
        } catch { self.error = error.localizedDescription; return }
        guard approved.allSatisfy({ $0.start > Date() }) else { error = "A suggested time has passed. Go back and find times again."; return }
        do {
            var records = EndurancePlanningEngine.sessions(from: approved, sport: request.sport, owner: owner, programID: programID,
                place: reviewedWeather?.place ?? "", forecastFetchedAt: reviewedWeather?.fetchedAt)
            if watchForecast {
                try await EnduranceProService.requirePro()
                guard let reviewedWeather, reviewedWeather.isFresh(at: Date()) else {
                    error = "Refresh the weather and find times again before watching this plan's forecast."; return
                }
                for index in records.indices {
                    guard let context = WeatherReschedulingPolicy.context(request: request, session: records[index], weather: reviewedWeather, checkCalendar: calendarWasChecked) else {
                        error = "A complete forecast is needed for every session. Find times again, or turn off forecast change suggestions."; return
                    }
                    records[index].weatherPlan = context
                }
            }
            try await EnduranceProService.saveGeneratedWeek(records, programID: programID)
            WeatherReschedulingService.shared.scheduleBackgroundCheck()
            showCalendar = true
        } catch let error as EnduranceProService.AccessError { await handleAccessError(error) }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private var planningGate: some View {
        switch access.decision {
        case .checking:
            ProgressView("Checking your planning access…").frame(maxWidth: .infinity).padding(.vertical, 40)
        case .upgradeRequired:
            EnduranceProCard(title: "Keep your training moving", message: "You've used your free week. Plan your next one with Shift Pro, including weather and Calendar checks. Your saved sessions stay available.") { showPro = true }
            NavigationLink("Open my training calendar") { TrainingCalendarView() }.font(.subheadline)
        case .unavailable:
            Text(access.error ?? "Sign in and connect to check your free week.").foregroundStyle(colors.muted)
            Button("Try again") { Task { await store.updatePurchasedProducts(); await access.load() } }.buttonStyle(.bordered)
            NavigationLink("Open my training calendar") { TrainingCalendarView() }
        case .pro, .freeWeek: EmptyView()
        }
    }
    private func handleAccessError(_ error: EnduranceProService.AccessError) async {
        if error == .proRequired { showPro = true; await access.load() }
        else { self.error = error.localizedDescription }
    }
}
