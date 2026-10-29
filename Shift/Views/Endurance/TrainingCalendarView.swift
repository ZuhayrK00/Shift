import SwiftUI

struct TrainingCalendarView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var initialDate: Date = Date()
    @State private var data = TrainingHub()
    @State private var date = Date()
    @State private var showNew = false
    @State private var editing: TrainingSession?
    @State private var workoutID: String?
    @State private var starting = false
    private var calendar: Calendar { .current }
    private var appointments: [TrainingSession] { TrainingCalendarProjection.expanded(sessions: data.sessions, settings: auth.user?.settings ?? .default, userID: auth.currentUserId ?? "", from: date, days: 1, planNames: Dictionary(uniqueKeysWithValues: data.plans.map { ($0.plan.id, $0.plan.name) }), workouts: data.workouts).filter { calendar.isDate($0.scheduledAt, inSameDayAs: date) }.sorted { $0.scheduledAt < $1.scheduledAt } }
    private var activities: [EnduranceActivity] { data.activities.filter { calendar.isDate($0.startedAt, inSameDayAs: date) } }
    private var workouts: [WorkoutSession] { data.workouts.filter { calendar.isDate($0.startedAt, inSameDayAs: date) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TrainingCalendarGrid(selected: $date, sessions: data.sessions, activities: data.activities,
                        workouts: data.workouts, weekStartsOn: auth.user?.settings.weekStartsOn ?? "monday", weeklySchedule: auth.user?.settings.trainingSchedule ?? .init())
                    NavigationLink { WeatherChangesView() } label: {
                        Label(WeatherReschedulingService.shared.suggestions.isEmpty ? "Forecast changes · Pro" : "Review forecast changes (\(WeatherReschedulingService.shared.suggestions.count))", systemImage: "cloud.sun")
                    }.font(.subheadline).foregroundStyle(colors.enduranceAccent)
                    Text(date.formatted(.dateTime.weekday(.wide).day().month())).font(.title3.bold())
                    ForEach(appointments) { item in appointment(item) }
                    if !workouts.isEmpty || !activities.isEmpty { Text("Completed").font(.headline) }
                    ForEach(workouts) { workout in
                        NavigationLink { WorkoutView(sessionId: workout.id) } label: {
                            HStack { Label(workout.name, systemImage: "dumbbell.fill"); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.success) }
                                .enduranceCard()
                        }.buttonStyle(.plain)
                    }
                    ForEach(activities) { activity in
                        NavigationLink { EnduranceDetailView(activity: activity) } label: { EnduranceActivityRow(activity: activity) }.buttonStyle(.plain)
                    }
                    if appointments.isEmpty && workouts.isEmpty && activities.isEmpty {
                        Text("Room for your next session. Add a gym workout, run, walk or ride.")
                            .foregroundStyle(colors.muted)
                    }
                    Button("Plan a session", systemImage: "plus") { showNew = true }
                        .buttonStyle(.borderedProminent).tint(colors.accent).foregroundStyle(colors.onAccent)
                    if let error = data.error { Text(error).font(.footnote).foregroundStyle(colors.danger) }
                }.padding(20)
            }.background(colors.bg).foregroundStyle(colors.text)
                .navigationTitle("Training calendar").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Add session", systemImage: "plus") { showNew = true } }
                }
                .navigationDestination(item: $workoutID) { id in WorkoutView(sessionId: id) }
                .sheet(isPresented: $showNew, onDismiss: { Task { await data.load() } }) { TrainingSessionEditor(session: nil, date: date) }
                .sheet(item: $editing, onDismiss: { Task { await data.load() } }) { item in TrainingSessionEditor(session: item, date: item.scheduledAt) }
                .task(id: auth.currentUserId) { date = initialDate; await data.load() }
                .refreshable { await data.load() }
                .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await data.load() } }
                .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await data.load() } }
        }
    }
    private func appointment(_ item: TrainingSession) -> some View {
        let complete = data.completion(for: item) != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(item.title, systemImage: item.symbol).font(.headline)
                    .foregroundStyle(item.kind == .strength ? colors.accent : colors.enduranceAccent)
                Spacer()
                Button("Edit", systemImage: "pencil") { editing = item }.labelStyle(.iconOnly)
            }
            if item.isAllDay == true { Text("Time not set").font(.subheadline).foregroundStyle(colors.muted) }
            else { Text(item.scheduledAt, format: .dateTime.hour().minute()).font(.subheadline).foregroundStyle(colors.muted) }
            let target = item.targetLabel(unit: auth.user?.settings.distanceUnit ?? "km")
            if !target.isEmpty { Text(target).font(.subheadline) }
            if !item.notes.isEmpty { Text(item.notes).font(.footnote).foregroundStyle(colors.muted) }
            if complete { Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(colors.success) }
            else if item.status == .skipped { Text("Skipped").foregroundStyle(colors.muted) }
            else {
                Button("Start session", systemImage: "play.fill") {
                    if item.kind == .endurance {
                        EnduranceRecorder.shared.pendingCalendarSession = item
                        dismiss()
                    } else { start(planID: item.strengthPlanID, sessionID: item.id, title: item.title) }
                }.buttonStyle(.borderedProminent)
                    .tint(item.kind == .strength ? colors.accent : colors.enduranceAccent)
                    .foregroundStyle(colors.onAccent).disabled(starting)
            }
        }.enduranceCard()
    }
    private func start(planID: String?, sessionID: String?, title: String = "Workout") {
        starting = true
        Task {
            defer { starting = false }
            do {
                let session: WorkoutSession
                if let planID { session = try await PlanService.createSessionFromPlan(planID, sessionId: sessionID) }
                else { session = try await WorkoutService.createSession(name: title, id: sessionID) }
                workoutID = session.id
            } catch { data.error = error.localizedDescription }
        }
    }
}

struct TrainingSessionEditor: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession?
    let date: Date
    @State private var title = ""
    @State private var scheduledAt = Date()
    @State private var kind: TrainingSessionKind = .endurance
    @State private var sport: EnduranceSport = .run
    @State private var planID = ""
    @State private var routeID = ""
    @State private var meters = ""
    @State private var minutes = ""
    @State private var notes = ""
    @State private var plans: [WorkoutPlanWithCount] = []
    @State private var routes: [SavedEnduranceRoute] = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var latestSession: TrainingSession?
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    DatePicker("When", selection: $scheduledAt)
                    Picker("Training", selection: $kind) { Text("Strength").tag(TrainingSessionKind.strength); Text("Endurance").tag(TrainingSessionKind.endurance) }
                    if kind == .strength {
                        Picker("Workout plan", selection: $planID) {
                            Text("Freestyle workout").tag("")
                            ForEach(plans, id: \.plan.id) { Text($0.plan.name).tag($0.plan.id) }
                        }
                    } else {
                        Picker("Sport", selection: $sport) { ForEach(EnduranceSport.allCases) { Text($0.title).tag($0) } }
                        TextField("Distance (\(unit), optional)", text: $meters).keyboardType(.decimalPad)
                        TextField("Minutes (optional)", text: $minutes).keyboardType(.decimalPad)
                        Picker("Saved route", selection: $routeID) {
                            Text("No route").tag("")
                            ForEach(routes.filter { $0.sport == sport }) { Text($0.title).tag($0.id) }
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let session {
                    if session.kind == .endurance && session.status == .scheduled && session.scheduledAt > Date() {
                        Section("Weather") {
                            NavigationLink { WeatherPlanPreferencesView(session: latestSession ?? session, onSaved: { latestSession = $0 }) } label: {
                                Label("Forecast change preferences · Pro", systemImage: "cloud.sun")
                            }
                            Text("Save any edits before changing weather preferences. Changing a session's time, sport or duration resets forecast watching.").font(.caption).foregroundStyle(colors.muted)
                        }
                    }
                    Section {
                        Button(session.status == .skipped ? "Restore session" : "Skip session") {
                            var copy = session; copy.status = session.status == .skipped ? .scheduled : .skipped
                            perform { try await EnduranceService.save(copy) }
                        }
                        Button("Delete session", role: .destructive) { confirmDelete = true }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(colors.danger) } }
            }.scrollContentBackground(.hidden).background(colors.bg)
                .navigationTitle(session == nil ? "Plan a session" : "Edit session").navigationBarTitleDisplayMode(.inline)
                .disabled(busy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(busy ? "Saving…" : "Save") { save() }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .task {
                    scheduledAt = session?.scheduledAt ?? date; title = session?.title ?? ""
                    kind = session?.kind ?? .endurance; sport = session?.sport ?? .run
                    planID = session?.strengthPlanID ?? ""; routeID = session?.routeID ?? ""; notes = session?.notes ?? ""
                    meters = session?.targetMeters.map { String(format: "%g", $0 / (unit == "mi" ? 1_609.344 : 1_000)) } ?? ""
                    minutes = session?.targetSeconds.map { String(format: "%g", $0 / 60) } ?? ""
                    plans = (try? await PlanService.listPlans()) ?? []
                    if let id = auth.currentUserId { routes = (try? await EnduranceStore.shared.all(SavedEnduranceRoute.self, userID: id)) ?? [] }
                }
                .onChange(of: sport) { _, value in if let route = routes.first(where: { $0.id == routeID }), route.sport != value { routeID = "" } }
                .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in
                    guard let session else { return }
                    Task { latestSession = try? await EnduranceStore.shared.all(TrainingSession.self, userID: session.userId).first { $0.id == session.id } }
                }
                .confirmationDialog("Delete this planned session?", isPresented: $confirmDelete) {
                    Button("Delete session", role: .destructive) { if let session { perform { try await EnduranceService.delete(session) } } }
                }
        }.interactiveDismissDisabled(busy)
    }
    private func save() {
        guard let owner = auth.currentUserId else { return }
        let distance = Double(meters.replacingOccurrences(of: ",", with: "."))
        let duration = Double(minutes.replacingOccurrences(of: ",", with: "."))
        if kind == .endurance && ((!meters.isEmpty && !(distance.map { $0.isFinite && $0 > 0 } ?? false)) || (!minutes.isEmpty && !(duration.map { $0.isFinite && $0 > 0 } ?? false))) {
            error = "Enter a positive distance or duration, or leave the target blank."; return
        }
        let original = latestSession ?? session
        var item = original ?? TrainingSession(userId: owner, title: title, scheduledAt: scheduledAt, kind: kind)
        item.isAllDay = nil
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines); item.scheduledAt = scheduledAt
        item.kind = kind; item.sport = kind == .endurance ? sport : nil; item.notes = notes
        item.strengthPlanID = kind == .strength && !planID.isEmpty ? planID : nil
        item.routeID = kind == .endurance && routes.contains(where: { $0.id == routeID && $0.sport == sport }) ? routeID : nil
        item.targetMeters = kind == .endurance ? distance.map { $0 * (unit == "mi" ? 1_609.344 : 1_000) } : nil
        item.targetSeconds = kind == .endurance ? duration.map { $0 * 60 } : nil
        if item.scheduledAt != original?.scheduledAt || item.kind != original?.kind || item.sport != original?.sport || item.targetSeconds != original?.targetSeconds { item.weatherPlan = nil }
        perform { try await EnduranceService.save(item) }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true
        Task { defer { busy = false }; do { try await action(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}
