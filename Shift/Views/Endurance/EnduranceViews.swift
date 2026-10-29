import SwiftUI
import MapKit

@MainActor @Observable
final class EnduranceDashboard {
    var activities: [EnduranceActivity] = []
    var goals: [EnduranceGoal] = []
    var error: String?
    var isLoading = false
    private var ownerID: String?
    func load() async {
        guard let userID = authManager.currentUserId else { activities = []; goals = []; return }
        if ownerID != userID { activities = []; goals = []; ownerID = userID }
        isLoading = true
        defer { isLoading = false }
        do {
            async let records = EnduranceStore.shared.all(EnduranceActivity.self, userID: userID)
            async let targets = EnduranceStore.shared.all(EnduranceGoal.self, userID: userID)
            let result = try await (records, targets)
            guard authManager.currentUserId == userID else { return }
            activities = result.0
            goals = result.1
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct EnduranceHomeView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = EnduranceDashboard()
    @State private var recorder = EnduranceRecorder.shared
    @State private var selectedSport: EnduranceSport = .run
    @State private var showImport = false
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    private var week: [EnduranceActivity] {
        let start = GoalService.startOfCurrentWeek(weekStartsOn: auth.user?.settings.weekStartsOn ?? "monday")
        return data.activities.filter { $0.startedAt >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrainingModeHeader()
                    homeContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .background(colors.bg).foregroundStyle(colors.text)
            .tint(colors.enduranceAccent)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showImport, onDismiss: { Task { await data.load() } }) { EnduranceImportView() }
            .task(id: auth.currentUserId) { await data.load(); await EnduranceWeatherService.shared.activate(owner: auth.currentUserId) }
            .refreshable { await data.load(); EnduranceWeatherService.shared.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await data.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await data.load() } }
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your next adventure").font(.system(size: 28, weight: .bold))
            Text("Head outside. Find your rhythm.").foregroundStyle(colors.muted)
            VStack(spacing: 18) {
                SegmentedControl(segments: EnduranceSport.allCases.map { .init(label: $0.title, value: $0) }, selection: $selectedSport, tint: colors.enduranceAccent)
                Image(systemName: selectedSport.symbol).font(.system(size: 54, weight: .light))
                    .foregroundStyle(colors.enduranceAccent).padding(.vertical, 10)
                Button {
                    recorder.prepare(sport: selectedSport)
                } label: {
                    Label(recorder.draft == nil ? "Start a \(selectedSport.rawValue)" : "Open recording", systemImage: recorder.draft == nil ? "play.fill" : "waveform.path")
                        .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(16)
                        .foregroundStyle(colors.onAccent).background(colors.enduranceAccent, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                Label("Private route · records with your screen locked", systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(colors.muted)
            }.enduranceCard()
            OutdoorWeatherPanel(sport: selectedSport).enduranceCard()

            VStack(alignment: .leading, spacing: 18) {
                Text("This week").font(.headline)
                HStack {
                    EnduranceStat(title: "Activities", value: "\(week.count)")
                    Spacer()
                    EnduranceStat(title: "Distance", value: EnduranceFormat.distance(week.reduce(0) { $0 + $1.distanceMeters }, unit: unit))
                    Spacer()
                    EnduranceStat(title: "Active time", value: EnduranceFormat.duration(week.reduce(0) { $0 + $1.activeSeconds }))
                }
            }.enduranceCard()

            VStack(alignment: .leading, spacing: 0) {
                Text("Your training").font(.title3.bold()).padding(.bottom, 10)
                trainingLink("Build my week", detail: "Your goal, your time, better weather", icon: "sparkles") { EnduranceCoachView() }
                Divider().overlay(colors.border)
                trainingLink("Progress", detail: "Trends, records and milestones", icon: "chart.xyaxis.line") { EnduranceProgressView() }
                Divider().overlay(colors.border)
                trainingLink("Saved routes", detail: "Find a favourite and head out again", icon: "map") { EnduranceRoutesView() }
                Divider().overlay(colors.border)
                trainingLink("Training plans", detail: "Your plans and flexible starting points", icon: "calendar") { EnduranceProgramsView() }
            }.enduranceCard()

            if !data.goals.isEmpty {
                HStack { Text("Your goals").font(.title3.bold()); Spacer(); NavigationLink("See all") { EnduranceGoalsView() } }
                ForEach(Array(data.goals.prefix(2))) { goal in EnduranceGoalCard(goal: goal, activities: data.activities) }
            }
            HStack { Text("Recent activity").font(.title3.bold()); Spacer(); NavigationLink("See all") { EnduranceHistoryView() } }
            if data.activities.isEmpty {
                ContentUnavailableView("Your journey starts here", systemImage: "figure.run",
                    description: Text("Record a run, walk or ride, or import your recent Apple Health workouts."))
            } else {
                ForEach(Array(data.activities.prefix(3))) { activity in
                    NavigationLink { EnduranceDetailView(activity: activity) } label: { EnduranceActivityRow(activity: activity) }.buttonStyle(.plain)
                }
            }
            Button { showImport = true } label: { Label("Import from Apple Health", systemImage: "heart.text.square") }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            NavigationLink { NotificationSettingsPage().toolbar(.visible, for: .navigationBar) } label: { Label("Training notifications", systemImage: "bell.badge") }.foregroundStyle(colors.enduranceAccent)
            if let error = data.error { Text(error).font(.footnote).foregroundStyle(colors.danger) }
        }
    }
    private func trainingLink<Destination: View>(_ title: String, detail: String, icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.title3).foregroundStyle(colors.enduranceAccent).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(colors.muted) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(colors.muted)
            }.padding(.vertical, 13)
        }.buttonStyle(.plain)
    }

}

struct EnduranceHistoryView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = EnduranceDashboard()
    @State private var filter = "All"
    @State private var showImport = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SegmentedControl(options: ["All", "Run", "Walk", "Cycle"], selection: $filter, tint: colors.enduranceAccent)
                if data.isLoading && data.activities.isEmpty { ProgressView().padding() }
                let activities = data.activities.filter { filter == "All" || $0.sport.title == filter }
                if activities.isEmpty && !data.isLoading {
                    ContentUnavailableView("No activities yet", systemImage: "map", description: Text("Your saved routes and imported workouts appear here."))
                }
                ForEach(activities) { activity in
                    NavigationLink { EnduranceDetailView(activity: activity) } label: { EnduranceActivityRow(activity: activity) }.buttonStyle(.plain)
                }
                if let error = data.error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "heart.text.square") }
                        .accessibilityLabel("Import from Apple Health")
                }
            }
            .sheet(isPresented: $showImport, onDismiss: { Task { await data.load() } }) { EnduranceImportView() }
            .task(id: auth.currentUserId) { await data.load() }.refreshable { await data.load() }
            .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await data.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await data.load() } }
    }
}

struct EnduranceActivityRow: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    let activity: EnduranceActivity
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: activity.sport.symbol).font(.title2)
                .foregroundStyle(colors.enduranceAccent)
                .frame(width: 44, height: 44)
                .background(colors.enduranceSoft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 7) {
                Text(activity.title).font(.headline).lineLimit(2)
                Text(activity.startedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(colors.muted)
                Text("\(EnduranceFormat.distance(activity.distanceMeters, unit: auth.user?.settings.distanceUnit ?? "km")) · \(EnduranceFormat.duration(activity.activeSeconds))")
                    .font(.subheadline).monospacedDigit()
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(colors.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).enduranceCard()
    }
}

struct EnduranceRouteMap: View {
    @Environment(\.shiftColors) private var colors
    let points: [EnduranceRoutePoint]
    var current: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    private var segments: [Int] { Array(Set(points.map(\.segment))).sorted() }
    var body: some View {
        Map(position: $position) {
            ForEach(segments, id: \.self) { segment in
                MapPolyline(coordinates: points.filter { $0.segment == segment }.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(colors.enduranceAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation("Start", coordinate: .init(latitude: first.latitude, longitude: first.longitude)) {
                    Circle().fill(colors.success).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let current {
                Annotation("Current location", coordinate: current) { Circle().fill(.blue).frame(width: 15, height: 15).overlay(Circle().stroke(.white, lineWidth: 3)) }.annotationTitles(.hidden)
            } else if let last = points.last, points.count > 1 {
                Marker("Finish", coordinate: .init(latitude: last.latitude, longitude: last.longitude)).tint(colors.enduranceAccent)
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .topTrailing) {
            Button { fit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(10).background(.regularMaterial, in: Circle()) }
                .accessibilityLabel("Fit route on map").padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear { if points.count < 2 { fit() } }
        .onChange(of: current?.latitude) { old, _ in if old == nil && points.count < 2 { fit() } }
        .accessibilityLabel("Private activity route, \(points.count) GPS points")
    }
    private func fit() {
        if points.count < 2, let current {
            position = .region(MKCoordinateRegion(center: current, latitudinalMeters: 1_200, longitudinalMeters: 1_200))
        } else { position = .automatic }
    }

}

struct EnduranceRecordingView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = EnduranceRecorder.shared
    @State private var showSave = false
    @State private var confirmDiscard = false
    let sport: EnduranceSport
    private var actualSport: EnduranceSport { recorder.draft?.sport ?? sport }
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if recorder.draft == nil {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Ready for your \(sport.rawValue)?").font(.system(.title, design: .rounded, weight: .bold))
                            Text("Your route, distance and \(sport == .cycle ? "speed" : "pace"), all in one place.").font(.subheadline).foregroundStyle(colors.muted)
                        }.padding(.top, 6)
                    }
                    EnduranceRouteMap(points: recorder.draft?.route ?? [], current: recorder.location?.coordinate)
                        .frame(height: recorder.draft == nil ? 250 : 280)
                        .overlay(alignment: .topLeading) {
                            Label(recorder.hasAccurateLocation ? "GPS ready" : "Finding GPS…", systemImage: recorder.hasAccurateLocation ? "location.fill" : "location")
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(recorder.hasAccurateLocation ? colors.success : colors.text)
                                .background(.regularMaterial, in: Capsule()).padding(12)
                        }
                    if let draft = recorder.draft {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = draft.activeSeconds(at: context.date)
                            let distance = draft.distanceMeters
                            VStack(alignment: .leading, spacing: 20) {
                                HStack {
                                    Label(draft.isPaused ? "Paused" : "Recording", systemImage: draft.isPaused ? "pause.fill" : "record.circle")
                                        .font(.caption.weight(.semibold)).foregroundStyle(draft.isPaused ? colors.warning : colors.enduranceAccent)
                                    Spacer(); Image(systemName: actualSport.symbol).foregroundStyle(colors.enduranceAccent)
                                }
                                Text(EnduranceFormat.distance(distance, unit: unit)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                                HStack {
                                    EnduranceStat(title: "Active time", value: EnduranceFormat.duration(seconds))
                                    Spacer()
                                    EnduranceStat(title: actualSport == .cycle ? "Average speed" : "Average pace", value: EnduranceFormat.pace(distance: distance, seconds: seconds, sport: actualSport, unit: unit))
                                }
                            }.enduranceCard()
                        }
                        if !draft.isPaused && !recorder.hasAccurateLocation {
                            Label("GPS signal is weak. Time keeps recording while it recovers.", systemImage: "location.slash").font(.footnote).foregroundStyle(colors.warning)
                        }
                        Button("Discard recording", role: .destructive) { confirmDiscard = true }.font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else {
                        OutdoorWeatherPanel(sport: sport).enduranceCard()
                        Label("Your route stays private. Recording continues with your screen locked.", systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    if let error = recorder.errorMessage { Text(error).font(.footnote).foregroundStyle(colors.warning) }
                    if recorder.authorization == .denied || recorder.authorization == .restricted {
                        Link("Open Shift settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }.padding(20)
            }.background(colors.bg).foregroundStyle(colors.text)
                .navigationTitle(actualSport.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(recorder.draft == nil ? "Cancel" : "Minimise") { dismiss() } } }
                .safeAreaInset(edge: .bottom) { recordingControls.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10).background(colors.bg) }
                .sheet(isPresented: $showSave) { EnduranceSaveView(sport: actualSport) }
                .confirmationDialog("Discard this recording? This cannot be undone.", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard recording", role: .destructive) {
                        Task { do { try await recorder.discard(); dismiss() } catch { recorder.errorMessage = error.localizedDescription } }
                    }
                }
                .onDisappear { recorder.stopPreview() }
        }.tint(colors.enduranceAccent)
    }
    @ViewBuilder private var recordingControls: some View {
        if let draft = recorder.draft {
            HStack(spacing: 12) {
                Button {
                    do { if draft.isPaused { try recorder.resume() } else { recorder.pause() } }
                    catch { recorder.errorMessage = error.localizedDescription }
                } label: {
                    Label(draft.isPaused ? "Resume" : "Pause", systemImage: draft.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(18).background(colors.surface2, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                Button { recorder.pause(); showSave = true } label: {
                    Text("Finish").font(.headline).frame(maxWidth: .infinity).padding(18).foregroundStyle(colors.onAccent)
                        .background(colors.enduranceAccent, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }.disabled(recorder.isSaving)
        } else {
            VStack(spacing: 9) {
                Button {
                    Task { do { try await recorder.start(sport: sport) } catch { recorder.errorMessage = error.localizedDescription } }
                } label: {
                    Label("Start \(sport.title)", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(18)
                        .foregroundStyle(colors.onAccent).background(colors.enduranceAccent, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).disabled(!recorder.hasAccurateLocation || recorder.isSaving).opacity(recorder.hasAccurateLocation ? 1 : 0.5)
                Text(recorder.hasAccurateLocation ? "Pause the recording whenever you stop." : "Waiting for an accurate location before starting.").font(.caption).foregroundStyle(colors.muted)
            }
        }
    }
}

private struct EnduranceSaveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    @State private var title = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var saving = false
    let sport: EnduranceSport
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") { TextField("Title", text: $title); TextField("Notes (optional)", text: $notes, axis: .vertical) }
                Section { Label("Only you can see this activity and its route.", systemImage: "lock.fill").font(.footnote) }
                if let error { Section { Text(error).foregroundStyle(colors.danger) } }
            }.scrollContentBackground(.hidden).background(colors.bg).navigationTitle("Save activity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { _ = try await EnduranceRecorder.shared.finish(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.onAppear { title = "\(sport.title) · \(Date().formatted(.dateTime.day().month()))" }
        }.interactiveDismissDisabled(saving)
    }
}

struct EnduranceDetailView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let activity: EnduranceActivity
    @State private var confirmDelete = false
    @State private var showShare = false
    @State private var showSaveRoute = false
    @State private var records: [EndurancePersonalBest] = []
    @State private var error: String?
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(activity.startedAt, format: .dateTime.day().month().year().hour().minute()).foregroundStyle(colors.muted)
                if activity.route.isEmpty {
                    ContentUnavailableView("No route recorded", systemImage: "map", description: Text(activity.source == "healthkit" ? "This import has no route. You can import again with routes enabled if Apple Health has one." : "GPS distance and time are saved even when a route is unavailable."))
                } else { EnduranceRouteMap(points: activity.route).frame(height: 300) }
                HStack {
                    EnduranceStat(title: "Distance", value: EnduranceFormat.distance(activity.distanceMeters, unit: unit)); Spacer()
                    EnduranceStat(title: "Active time", value: EnduranceFormat.duration(activity.activeSeconds))
                }.enduranceCard()
                HStack {
                    EnduranceStat(title: activity.sport == .cycle ? "Average speed" : "Average pace", value: EnduranceFormat.pace(distance: activity.distanceMeters, seconds: activity.activeSeconds, sport: activity.sport, unit: unit)); Spacer()
                    EnduranceStat(title: "Elevation gain", value: unit == "mi" ? String(format: "%.0f ft", activity.elevationGainMeters * 3.28084) : String(format: "%.0f m", activity.elevationGainMeters))
                }.enduranceCard()
                HStack {
                    Button("Share", systemImage: "square.and.arrow.up") { showShare = true }
                    Spacer()
                    if activity.route.count >= 2 && activity.distanceMeters > 0 {
                        Button("Save route", systemImage: "bookmark") { showSaveRoute = true }
                    }
                }.buttonStyle(.bordered).tint(colors.enduranceAccent)
                ForEach(records) { record in
                    Label(record.title, systemImage: "trophy.fill").font(.headline).foregroundStyle(colors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading).enduranceCard()
                }
                EndurancePerformanceCharts(activity: activity)
                Label(activity.source == "healthkit" ? "Imported from Apple Health" : "Recorded with Shift", systemImage: activity.source == "healthkit" ? "heart.fill" : activity.sport.symbol)
                    .font(.footnote).foregroundStyle(colors.muted)
                if !activity.splits.isEmpty {
                    Text("Kilometre splits").font(.title3.bold())
                    ForEach(activity.splits, id: \.number) { split in
                        HStack {
                            Text("\(split.number)")
                            if split.distanceMeters < 999 { Text(String(format: "%.2f km", split.distanceMeters / 1_000)).foregroundStyle(colors.muted) }
                            Spacer()
                            Text(EnduranceFormat.pace(distance: split.distanceMeters, seconds: split.activeSeconds, sport: activity.sport, unit: "km")).monospacedDigit()
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
                if !activity.notes.isEmpty { Text("Notes").font(.headline); Text(activity.notes) }
                Text("Elapsed time: \(EnduranceFormat.duration(activity.elapsedSeconds)). Paused time is excluded from active time.")
                    .font(.footnote).foregroundStyle(colors.muted)
                if let error { Text(error).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle(activity.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { Button(role: .destructive) { confirmDelete = true } label: { Label("Delete activity", systemImage: "trash") } }
            .sheet(isPresented: $showShare) { EnduranceShareView(activity: activity, unit: unit) }
            .sheet(isPresented: $showSaveRoute) { SaveEnduranceRouteView(activity: activity) }
            .task(id: auth.currentUserId) {
                guard let id = auth.currentUserId, id == activity.userId else { records = []; return }
                if let all = try? await EnduranceStore.shared.all(EnduranceActivity.self, userID: id) {
                    records = EnduranceInsights.records(all, userID: id).filter { $0.activityID == activity.id }
                }
            }
            .confirmationDialog("Delete this activity from Shift? Apple Health will keep its original workout.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete activity", role: .destructive) {
                    Task { do { try await EnduranceService.delete(activity); dismiss() } catch { self.error = error.localizedDescription } }
                }
            }
    }
}

struct EnduranceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var includeRoutes = false
    @State private var savedImportCount = 0
    @State private var busy = false
    @State private var status = ""
    @State private var report: EnduranceImportReport?
    @State private var error: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importRange: EnduranceImportRange = .allHistory
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bring all your recorded walks, hikes, runs and rides into Shift, including older sessions. Repeated imports do not create duplicates.")
                    Picker("History", selection: $importRange) { ForEach(EnduranceImportRange.allCases) { Text($0.rawValue).tag($0) } }.disabled(busy)
                    Text("Imports recorded Apple Health workouts. Everyday steps and walking-distance totals without a saved workout aren't individual sessions.").font(.footnote).foregroundStyle(colors.muted)
                    Text("Imported workouts sync to your private Shift account. Workout routes are included only if you enable them below.").font(.footnote).foregroundStyle(colors.muted)
                    if savedImportCount > 0 {
                        Label("\(savedImportCount) \(savedImportCount == 1 ? "activity already saved" : "activities already saved") in Shift", systemImage: "checkmark.circle")
                            .font(.footnote).foregroundStyle(colors.success)
                        Text("Find your imports in Activities. Import again to check for new workouts or add missing maps.").font(.footnote).foregroundStyle(colors.muted)
                    }
                }
                Section {
                    Toggle("Include workout maps", isOn: Binding(get: { includeRoutes }, set: { enabled in
                        includeRoutes = enabled
                        if let userID = auth.currentUserId {
                            EnduranceHealthPreferences.setIncludesRoutes(enabled, userID: userID)
                        }
                    }))
                    .tint(colors.controlTint).disabled(busy)
                } footer: {
                    Text("Remembered for your Shift account. Applies when you tap Import; this does not enable automatic imports.")
                }
                Section {
                    Button(busy ? "Importing…" : "Import from Apple Health") {
                        busy = true; error = nil; report = nil; status = "Connecting to Apple Health…"
                        importTask = Task {
                            defer { busy = false }
                            do {
                                report = try await EnduranceHealthService.importActivities(includeRoutes: includeRoutes, range: importRange) { done, total in status = "Checking \(done) of \(total)…" }
                                status = ""
                                await loadSavedImports()
                            } catch is CancellationError { status = "Import stopped. Activities already saved are kept."; await EnduranceService.refreshSummaries(); SyncService.flushInBackground(); await loadSavedImports() }
                            catch { status = ""; self.error = "\(error.localizedDescription) Activities already saved are kept; import again to continue."; SyncService.flushInBackground(); await loadSavedImports() }
                        }
                    }.disabled(busy)
                    if busy { ProgressView() }
                    if !status.isEmpty { Text(status).font(.footnote) }
                    if let error { Text(error).foregroundStyle(colors.danger) }
                }
                if let report {
                    Section {
                        Label(report.title, systemImage: report.importedCount > 0 || report.updatedRouteCount > 0 || report.alreadyImportedCount > 0 ? "checkmark.circle.fill" : "info.circle")
                            .font(.headline)
                        Text(report.message).font(.footnote)
                    }
                }
            }.scrollContentBackground(.hidden).background(colors.bg).navigationTitle("Apple Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(busy ? "Stop" : "Done") { importTask?.cancel(); if !busy { dismiss() } }
                    }
                }
                .task(id: auth.currentUserId) {
                    if let userID = auth.currentUserId { includeRoutes = EnduranceHealthPreferences.includesRoutes(userID: userID) }
                    await loadSavedImports()
                }
                .onDisappear { importTask?.cancel() }
        }
    }

    private func loadSavedImports() async {
        guard let userID = auth.currentUserId else { savedImportCount = 0; return }
        let activities = (try? await EnduranceStore.shared.all(EnduranceActivity.self, userID: userID)) ?? []
        guard auth.currentUserId == userID else { return }
        savedImportCount = activities.filter { $0.source == "healthkit" }.count
    }
}
