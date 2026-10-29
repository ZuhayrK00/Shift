import SwiftUI
import Charts

struct EnduranceProgressView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = TrainingHub()
    @State private var filter = "All"
    @State private var store = StoreService.shared
    @State private var showPro = false
    @Namespace private var awardTransition
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    private var owner: String { auth.currentUserId ?? "" }
    private var filtered: [EnduranceActivity] { data.activities.filter { filter == "All" || $0.sport.title == filter } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SegmentedControl(options: ["All", "Run", "Walk", "Cycle"], selection: $filter, tint: colors.enduranceAccent)
                let months = EnduranceInsights.months(filtered, userID: owner)
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.isPro ? "Distance over time" : "This month").font(.headline)
                    if store.isPro { Chart(months) { month in
                        BarMark(x: .value("Month", month.start, unit: .month), y: .value(unit, month.distance / (unit == "mi" ? 1_609.344 : 1_000)))
                            .foregroundStyle(colors.enduranceAccent.gradient).cornerRadius(5)
                    }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                        .frame(height: 190) }
                    if let current = months.last {
                        HStack { EnduranceStat(title: "This month", value: EnduranceFormat.distance(current.distance, unit: unit)); Spacer(); EnduranceStat(title: "Activities", value: "\(current.count)") }
                        Text("\(EnduranceFormat.duration(current.seconds)) active time this month").font(.footnote).foregroundStyle(colors.muted)
                    }
                }.enduranceCard()
                if !store.isPro && !store.isCheckingEntitlement {
                    EnduranceProCard(title: "See the bigger picture", message: "Explore six months of endurance trends with Shift Pro. Your activity history, current-month totals, personal bests and milestones stay free.") { showPro = true }
                }
                Text("Personal bests").font(.title3.bold())
                let records = EnduranceInsights.records(filtered, userID: owner)
                if records.isEmpty { Text("Your first recorded activity starts your personal bests.").foregroundStyle(colors.muted) }
                ForEach(records) { record in
                    if let activity = data.activities.first(where: { $0.id == record.activityID }) {
                        NavigationLink { EnduranceDetailView(activity: activity) } label: {
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(colors.warning)
                                VStack(alignment: .leading, spacing: 6) { Text(record.title).font(.headline); Text(record.achievedAt, style: .date).font(.caption).foregroundStyle(colors.muted) }
                                Spacer()
                                Text(record.isTime ? EnduranceFormat.duration(record.value) : EnduranceFormat.distance(record.value, unit: unit)).font(.headline).foregroundStyle(colors.enduranceAccent)
                            }.enduranceCard()
                        }.buttonStyle(.plain)
                    }
                }
                Text("Timed bests use complete, consecutive kilometre splits and active time. Imports without measured splits do not produce timed records.")
                    .font(.footnote).foregroundStyle(colors.muted)
                Text("Milestones").font(.title3.bold())
                let awards = EnduranceInsights.awards(data.activities, userID: owner)
                if awards.isEmpty { Text("Complete an activity to earn your first badge.").foregroundStyle(colors.muted) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(awards) { award in
                        if #available(iOS 18, *) {
                            NavigationLink {
                                EnduranceAwardDetailView(award: award, activity: data.activities.first { $0.id == award.activityID })
                                    .navigationTransition(.zoom(sourceID: award.id, in: awardTransition))
                            } label: { awardCard(award).matchedTransitionSource(id: award.id, in: awardTransition) }.buttonStyle(.plain)
                        } else {
                            NavigationLink { EnduranceAwardDetailView(award: award, activity: data.activities.first { $0.id == award.activityID }) }
                                label: { awardCard(award) }.buttonStyle(.plain)
                        }
                    }
                }
                if let error = data.error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle("Your progress").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .task(id: auth.currentUserId) { await data.load() }.refreshable { await data.load() }
            .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await data.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await data.load() } }
    }
    private func awardCard(_ award: EnduranceAward) -> some View {
        VStack(spacing: 8) {
            EnduranceAwardBadge(award: award).frame(height: 112)
            Text(award.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            Text(award.earnedAt, format: .dateTime.day().month(.abbreviated).year()).font(.caption2).foregroundStyle(colors.muted)
        }.frame(maxWidth: .infinity).padding(14).background(colors.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
            .accessibilityElement(children: .combine).accessibilityHint("View milestone and rotate its badge")
    }

}

struct EnduranceProgramsView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = TrainingHub()
    @State private var store = StoreService.shared
    @State private var showPro = false
    @State private var start = Date()
    @State private var selected: EnduranceProgramTemplate?
    @State private var busy = false
    @State private var showCalendar = false
    @State private var confirmRemove: String?
    private var programs: [(String, [TrainingSession])] {
        Dictionary(grouping: data.sessions.filter { $0.programID != nil }, by: { $0.programID! })
            .map { ($0.key, $0.value.sorted { $0.scheduledAt < $1.scheduledAt }) }.sorted { ($0.1.first?.scheduledAt ?? .distantPast) > ($1.1.first?.scheduledAt ?? .distantPast) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NavigationLink { EnduranceCoachView() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Build my week", systemImage: "sparkles").font(.headline)
                        Text("A personal plan around your goal, availability and local weather.").font(.subheadline).foregroundStyle(colors.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).enduranceCard()
                }.buttonStyle(.plain)
                HStack { Text("Training plan library").font(.title2.bold()); Spacer(); Label("Pro", systemImage: "crown.fill").font(.caption.weight(.semibold)).foregroundStyle(colors.accent) }
                Text("Choose a starting point, then move, edit or skip any session in your calendar. These are flexible templates; choose durations that suit you.").foregroundStyle(colors.muted)
                DatePicker("First session", selection: $start, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                ForEach(EnduranceProgramTemplate.all) { program in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(program.title, systemImage: program.sport.symbol).font(.headline).foregroundStyle(colors.enduranceAccent)
                        Text(program.subtitle).foregroundStyle(colors.muted)
                        Text("Starts at \(program.initialMinutes) minutes per session. Easy effort, with flexible weekly targets.").font(.subheadline)
                        Button(store.isPro ? "Add to calendar" : "Unlock with Pro") { if store.isPro { selected = program } else { showPro = true } }.buttonStyle(.borderedProminent).tint(colors.enduranceAccent).foregroundStyle(colors.onAccent).disabled(busy)
                    }.frame(maxWidth: .infinity, alignment: .leading).enduranceCard()
                }
                ForEach(programs, id: \.0) { id, sessions in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sessions.first?.title.components(separatedBy: " · Week").first ?? "Training plan").font(.headline)
                        let complete = sessions.filter { data.completion(for: $0) != nil }.count
                        Text("\(complete) of \(sessions.count) completed").foregroundStyle(colors.muted)
                        ProgressView(value: Double(complete), total: Double(max(1, sessions.count))).tint(colors.enduranceAccent)
                        Button("View calendar") { showCalendar = true }
                        Button("Remove remaining sessions", role: .destructive) { confirmRemove = id }.disabled(busy)
                    }.enduranceCard()
                }
                if let error = data.error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle("Endurance plans").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task(id: auth.currentUserId) { await data.load() }
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .sheet(isPresented: $showCalendar, onDismiss: { EnduranceRecorder.shared.openPendingCalendarSession(); Task { await data.load() } }) { TrainingCalendarView() }
            .confirmationDialog("Add this plan to your calendar?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                if let selected { Button("Add \(selected.weeks * selected.sessionsPerWeek) sessions") { add(selected) } }
            }
            .confirmationDialog("Remove all uncompleted sessions in this plan? Completed activities are kept.", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
                Button("Remove sessions", role: .destructive) {
                    guard let id = confirmRemove else { return }; busy = true
                    Task { defer { busy = false }; do {
                        for item in data.sessions where item.programID == id && data.completion(for: item) == nil { try await EnduranceService.delete(item) }
                        await data.load()
                    } catch { data.error = error.localizedDescription } }
                }
            }
    }
    private func add(_ program: EnduranceProgramTemplate) {
        guard let owner = auth.currentUserId else { return }; busy = true; selected = nil
        Task { defer { busy = false }; do {
            try await EnduranceProService.requirePro()
            try await EnduranceService.schedule(program.sessions(userID: owner, starting: start))
            await data.load(); showCalendar = true
        } catch EnduranceProService.AccessError.proRequired { showPro = true }
        catch { data.error = error.localizedDescription } }
    }
}

struct EnduranceRoutesView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = TrainingHub()
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if data.routes.isEmpty {
                    ContentUnavailableView("Keep your favourite routes", systemImage: "map", description: Text("Open an activity with a recorded map and tap Save route. Repeat it later and see your efforts together."))
                }
                ForEach(data.routes) { route in
                    NavigationLink { SavedRouteDetailView(route: route) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            EnduranceRouteMap(points: route.points).frame(height: 140).allowsHitTesting(false)
                            HStack { Label(route.title, systemImage: route.sport.symbol).font(.headline); Spacer(); Text(EnduranceFormat.distance(route.distanceMeters, unit: auth.user?.settings.distanceUnit ?? "km")).foregroundStyle(colors.enduranceAccent) }
                        }.enduranceCard()
                    }.buttonStyle(.plain)
                }
                if let error = data.error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle("Saved routes").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).task(id: auth.currentUserId) { await data.load() }
            .refreshable { await data.load() }
    }
}

struct SavedRouteDetailView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let route: SavedEnduranceRoute
    @State private var data = TrainingHub()
    @State private var confirmDelete = false
    private var efforts: [EnduranceActivity] { data.activities.filter { $0.savedRouteID == route.id || $0.id == route.sourceActivityID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnduranceRouteMap(points: route.points).frame(height: 300)
                Text(EnduranceFormat.distance(route.distanceMeters, unit: auth.user?.settings.distanceUnit ?? "km")).font(.largeTitle.bold()).foregroundStyle(colors.enduranceAccent)
                Button(EnduranceRecorder.shared.draft == nil ? "Repeat this route" : "Open recording", systemImage: "play.fill") { EnduranceRecorder.shared.prepare(sport: route.sport, savedRouteID: route.id) }
                    .buttonStyle(.borderedProminent).tint(colors.enduranceAccent).foregroundStyle(colors.onAccent)
                Text("The saved map is a reference, not turn-by-turn navigation. Your new GPS recording is saved separately.").font(.footnote).foregroundStyle(colors.muted)
                Text("Your efforts").font(.title3.bold())
                Text("Activities started from this saved route. Compare distance as well as time when reviewing efforts.").font(.footnote).foregroundStyle(colors.muted)
                ForEach(efforts) { activity in
                    NavigationLink { EnduranceDetailView(activity: activity) } label: { EnduranceActivityRow(activity: activity) }.buttonStyle(.plain)
                }
                if let error = data.error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { Button("Delete route", systemImage: "trash", role: .destructive) { confirmDelete = true } }
            .confirmationDialog("Delete this saved route? Your completed activities are kept.", isPresented: $confirmDelete) {
                Button("Delete route", role: .destructive) { Task { do { try await EnduranceService.delete(route); dismiss() } catch { data.error = error.localizedDescription } } }
            }.task(id: auth.currentUserId) { await data.load() }
    }
}

struct SaveEnduranceRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    let activity: EnduranceActivity
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Route name", text: $title)
                Text("This route stays private to your Shift account.").font(.footnote).foregroundStyle(colors.muted)
                if let error { Text(error).foregroundStyle(colors.danger) }
            }.scrollContentBackground(.hidden).background(colors.bg).navigationTitle("Save route").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button(busy ? "Saving…" : "Save") {
                        busy = true
                        Task { defer { busy = false }; do {
                            let route = SavedEnduranceRoute(userId: activity.userId, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                sport: activity.sport, distanceMeters: activity.distanceMeters, points: activity.route, sourceActivityID: activity.id)
                            try await EnduranceService.save(route); dismiss()
                        } catch { self.error = error.localizedDescription } }
                    }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { title = activity.title }
        }.interactiveDismissDisabled(busy)
    }
}
