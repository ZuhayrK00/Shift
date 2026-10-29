import SwiftUI

struct EnduranceGoalsView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    @State private var data = EnduranceDashboard()
    @State private var showNew = false
    @State private var editing: EnduranceGoal?
    @State private var deleting: EnduranceGoal?
    @State private var showSteps = false
    @State private var showFrequency = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Every goal, one place").font(.system(size: 27, weight: .bold))
                Text("Give your runs, walks and rides something to work towards.").foregroundStyle(colors.muted)
                if data.goals.isEmpty {
                    ContentUnavailableView("Set your first endurance goal", systemImage: "target",
                        description: Text("Choose distance, active time or activities. Set a weekly, monthly or personal deadline."))
                    Button("Add goal", systemImage: "plus") { showNew = true }.buttonStyle(.borderedProminent).tint(colors.enduranceAccent).foregroundStyle(colors.onAccent)
                }
                ForEach(data.goals) { goal in
                    VStack(alignment: .leading, spacing: 10) {
                        EnduranceGoalCard(goal: goal, activities: data.activities)
                        HStack {
                            Button("Edit") { editing = goal }
                            Spacer()
                            Button("Delete", role: .destructive) { deleting = goal }
                        }.font(.subheadline).padding(.horizontal, 8)
                    }
                }
                Text("Your everyday goals").font(.title3.bold()).padding(.top, 14)
                VStack(spacing: 18) {
                    Button { showSteps = true } label: {
                        HStack { Label("Daily steps", systemImage: "figure.walk"); Spacer(); Text(auth.user?.settings.dailyStepGoal.map { "\($0.formatted())" } ?? "Set goal").foregroundStyle(colors.muted) }
                    }
                    Divider()
                    Button { showFrequency = true } label: {
                        HStack { Label("Weekly training", systemImage: "calendar"); Spacer(); Text(auth.user?.settings.effectiveWeeklyFrequencyGoal.map { "\($0) sessions" } ?? "Set goal").foregroundStyle(colors.muted) }
                    }
                    Text("Your strength, body-weight and exercise goals are also available in Profile.").font(.footnote).foregroundStyle(colors.muted)
                }.enduranceCard()
                if let error = data.error { Text(error).font(.footnote).foregroundStyle(colors.danger) }
            }.padding(20)
        }.background(colors.bg).foregroundStyle(colors.text).navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add goal")
                }
            }
            .sheet(isPresented: $showNew, onDismiss: { Task { await data.load() } }) { EnduranceGoalEditor(goal: nil) }
            .sheet(item: $editing, onDismiss: { Task { await data.load() } }) { goal in EnduranceGoalEditor(goal: goal) }
            .sheet(isPresented: $showSteps) { StepGoalEditorSheet() }
            .sheet(isPresented: $showFrequency) { FrequencyGoalEditorSheet() }
            .confirmationDialog("Delete this goal?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete goal", role: .destructive) {
                    guard let goal = deleting else { return }
                    Task {
                        do { try await EnduranceService.delete(goal); deleting = nil; await data.load() }
                        catch { data.error = error.localizedDescription }
                    }
                }
            }
            .task(id: auth.currentUserId) { await data.load() }
            .refreshable { await data.load() }
            .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await data.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await data.load() } }
    }
}

struct EnduranceGoalCard: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    let goal: EnduranceGoal
    let activities: [EnduranceActivity]
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = auth.user?.settings.weekStartsOn == "sunday" ? 1 : 2
        return calendar
    }
    private func display(_ value: Double) -> String {
        switch goal.metric {
        case .distance: return EnduranceFormat.distance(value, unit: unit)
        case .duration: return String(format: "%.0f min", value / 60)
        case .activities: return String(format: "%.0f", value)
        }
    }
    var body: some View {
        let progress = goal.progress(in: activities, calendar: calendar)
        let complete = progress >= goal.target
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(goal.sport?.title ?? "All endurance") · \(goal.metric.title)", systemImage: goal.sport?.symbol ?? "target").font(.headline)
                Spacer()
                if complete { Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.success).accessibilityLabel("Goal reached") }
            }
            Text("\(display(progress)) / \(display(goal.target))").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            ProgressView(value: min(progress, goal.target), total: goal.target).tint(complete ? colors.success : colors.enduranceAccent)
                .accessibilityLabel("Goal progress").accessibilityValue("\(Int(min(1, progress / goal.target) * 100)) percent")
            if goal.period == .deadline, let date = goal.deadline {
                Text("By \(date.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(colors.muted)
            } else { Text(goal.period == .week ? "This week" : "This month").font(.caption).foregroundStyle(colors.muted) }
        }.enduranceCard()
    }
}

private struct EnduranceGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var auth
    let goal: EnduranceGoal?
    @State private var sport = "all"
    @State private var metric: EnduranceMetric = .distance
    @State private var period: EnduranceGoalPeriod = .week
    @State private var target = "5"
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var saving = false
    @State private var error: String?
    private var unit: String { auth.user?.settings.distanceUnit ?? "km" }
    private var targetUnit: String { switch metric { case .distance: return unit; case .duration: return "minutes"; case .activities: return "activities" } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    EnduranceGoalControls(sport: $sport, metric: $metric, period: $period, target: $target, deadline: $deadline, unit: unit)
                    if let error { Text(error).font(.footnote).foregroundStyle(colors.danger) }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(colors.bg).foregroundStyle(colors.text)
                .navigationTitle(goal == nil ? "New goal" : "Edit goal").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
                .safeAreaInset(edge: .bottom) {
                    Button { Task { await save() } } label: {
                        Text(saving ? "Saving…" : "Save goal").font(.headline).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(colors.onAccent).background(colors.enduranceAccent, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).disabled(saving || target.isEmpty).padding(.horizontal, 20).padding(.vertical, 12).background(colors.bg)
                }
                .onAppear {
                    guard let goal else { return }
                    sport = goal.sport?.rawValue ?? "all"; metric = goal.metric; period = goal.period
                    let divisor = goal.metric == .distance ? (unit == "mi" ? 1_609.344 : 1_000) : goal.metric == .duration ? 60.0 : 1.0
                    target = (goal.target / divisor).formatted(.number.precision(.fractionLength(0...2)))
                    deadline = goal.deadline?.addingTimeInterval(-1) ?? deadline
                }
        }.interactiveDismissDisabled(saving).tint(colors.enduranceAccent)
    }
    private func save() async {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current
        guard let value = formatter.number(from: target)?.doubleValue, let userID = auth.currentUserId else {
            error = EnduranceError.invalidGoal.localizedDescription; return
        }
        let multiplier = metric == .distance ? (unit == "mi" ? 1_609.344 : 1_000) : metric == .duration ? 60.0 : 1.0
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: deadline))
        let updated = EnduranceGoal(id: goal?.id ?? UUID().uuidString.lowercased(), userId: userID,
            sport: EnduranceSport(rawValue: sport), metric: metric, target: value * multiplier,
            period: period, createdAt: goal?.createdAt ?? Date(), deadline: period == .deadline ? end : nil)
        saving = true
        defer { saving = false }
        do { try await EnduranceService.save(updated); dismiss() } catch { self.error = error.localizedDescription }
    }
}
