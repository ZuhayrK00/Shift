import SwiftUI

struct TodayView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var selectedDate: Date = noonOfLocalDate(Date())
    @State private var completedSessions: [SessionSummary] = []
    @State private var inProgressSessions: [SessionSummary] = []
    @State private var completedDates: Set<String> = []
    @State private var inProgressDates: Set<String> = []
    @State private var plans: [WorkoutPlan] = []
    @State private var showPlanPicker = false
    @State private var isLoading = false
    @State private var starting = false
    @State private var navigationPath = NavigationPath()

    private var todayKey: String { toLocalDateKey(Date()) }
    private var selectedKey: String { toLocalDateKey(selectedDate) }
    private var isToday: Bool { selectedKey == todayKey }
    private var isPast: Bool { selectedKey < todayKey }
    private var isFuture: Bool { selectedDate > noonOfLocalDate(Date()) }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title
                        Text("Shift")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(colors.text)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        // Week calendar
                        WeekCalendar(
                            selected: $selectedDate,
                            completedDates: completedDates,
                            inProgressDates: inProgressDates
                        )
                        .padding(.bottom, 24)

                        // Date heading
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isToday ? "Today" : dateHeading)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(colors.text)
                                Text(formattedDate)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.muted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Content
                        if isLoading {
                            ProgressView()
                                .tint(colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if isFuture {
                            futureState
                        } else if completedSessions.isEmpty && inProgressSessions.isEmpty {
                            emptyState
                        } else {
                            sessionList
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: String.self) { sessionId in
                WorkoutView(sessionId: sessionId)
            }
        }
        .task { await loadData() }
        .onChange(of: navigationPath) {
            // Fires when popping back from a workout — refresh sessions + calendar
            if navigationPath.isEmpty {
                Task { await refreshAfterNavigation() }
            }
        }
        .onChange(of: selectedDate) {
            Task { await loadSessionsForDate() }
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanPickerSheet(plans: plans) { plan in
                Task { await startWorkout(plan: plan) }
            }
        }
    }

    // MARK: - Session list

    @ViewBuilder
    private var sessionList: some View {
        VStack(spacing: 12) {
            // In-progress sessions first
            ForEach(inProgressSessions, id: \.id) { summary in
                Button {
                    navigationPath.append(summary.id)
                } label: {
                    InProgressSessionCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            // Completed sessions
            ForEach(completedSessions, id: \.id) { summary in
                Button {
                    navigationPath.append(summary.id)
                } label: {
                    CompletedSessionCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            // Still show start button if there are only completed sessions (allow multiple workouts per day)
            if inProgressSessions.isEmpty {
                startButtons
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Empty state (today/past)

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isPast ? "Backfill" : "Quick start")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .textCase(.uppercase)
                    .tracking(1)
                Text(isPast ? "Add a missed workout" : "Start a workout")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.text)
                Text(isPast
                     ? "Forgot to log a session on this day? Add it now and it'll show on the calendar."
                     : "Jump in without a plan and add exercises as you go.")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            startButtons
        }
        .padding(20)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Start buttons (from scratch + select plan)

    @ViewBuilder
    private var startButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await startWorkout(plan: nil) }
            } label: {
                Text("From scratch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colors.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(starting)
            .opacity(starting ? 0.5 : 1)

            if !plans.isEmpty {
                Button {
                    showPlanPicker = true
                } label: {
                    Text("Select plan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(starting)
                .opacity(starting ? 0.5 : 1)
            }
        }
    }

    // MARK: - Future state

    private var futureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundStyle(colors.muted)
            Text("No workout scheduled")
                .font(.system(size: 16))
                .foregroundStyle(colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Data loading

    private func loadData() async {
        isLoading = true
        async let plansResult = PlanService.listPlans()
        async let completedDatesResult = WorkoutService.getCompletedSessionDates()
        async let inProgressDatesResult = WorkoutService.getInProgressSessionDates()

        let fetchedPlans = (try? await plansResult) ?? []
        let fetchedCompleted = (try? await completedDatesResult) ?? []
        let fetchedInProgress = (try? await inProgressDatesResult) ?? []

        plans = fetchedPlans.map { $0.plan }
        completedDates = fetchedCompleted
        inProgressDates = fetchedInProgress
        isLoading = false

        await loadSessionsForDate()
    }

    private func loadSessionsForDate() async {
        async let completed = WorkoutService.getCompletedSessions(for: selectedDate)
        async let inProgress = WorkoutService.getInProgressSessions(for: selectedDate)
        completedSessions = (try? await completed) ?? []
        inProgressSessions = (try? await inProgress) ?? []
    }

    /// Lightweight refresh for when we return from a pushed view (e.g. after discarding a workout).
    private func refreshAfterNavigation() async {
        async let sessionsRefresh: () = loadSessionsForDate()
        async let completedDatesResult = WorkoutService.getCompletedSessionDates()
        async let inProgressDatesResult = WorkoutService.getInProgressSessionDates()

        _ = await sessionsRefresh
        completedDates = (try? await completedDatesResult) ?? []
        inProgressDates = (try? await inProgressDatesResult) ?? []
    }

    private func startWorkout(plan: WorkoutPlan?) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }

        do {
            let startedAt = isToday ? Date() : noonOfLocalDate(selectedDate)
            let session: WorkoutSession
            if let plan {
                session = try await PlanService.createSessionFromPlan(plan.id, startedAt: startedAt)
            } else {
                session = try await WorkoutService.createSession(startedAt: startedAt)
            }
            navigationPath.append(session.id)
        } catch {}
    }

    // MARK: - Helpers

    private var dateHeading: String {
        let cal = Calendar.current
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: selectedDate)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - InProgressSessionCard

private struct InProgressSessionCard: View {
    @Environment(\.shiftColors) private var colors
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .stroke(colors.accent, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                Text("In progress")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text(summary.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colors.text)
                .padding(.top, 4)

            let totalSets = summary.exercises.reduce(0) { $0 + $1.setCount }
            Text("\(pluralise(summary.exercises.count, "exercise", "exercises"))"
                 + (totalSets > 0 ? " · \(pluralise(totalSets, "set"))" : ""))
                .font(.system(size: 12))
                .foregroundStyle(colors.muted)
                .padding(.top, 2)

            // Exercise list
            if !summary.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.exercises, id: \.id) { ex in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colors.muted)
                                .frame(width: 4, height: 4)
                            Text(ex.name)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.muted)
                            Spacer()
                            Text(pluralise(ex.setCount, "set"))
                                .font(.system(size: 11))
                                .foregroundStyle(colors.muted)
                        }
                    }
                }
                .padding(.top, 12)
            } else {
                Text("No exercises added yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
                    .padding(.top, 8)
            }

            // Resume button
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                Text("Resume")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 16)
        }
        .padding(20)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.accent, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - CompletedSessionCard

private struct CompletedSessionCard: View {
    @Environment(\.shiftColors) private var colors
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(colors.success)
                    .frame(width: 8, height: 8)
                Text("Completed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }

            Text(summary.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colors.text)
                .padding(.top, 4)

            // Exercise list
            if !summary.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.exercises, id: \.id) { ex in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colors.muted)
                                .frame(width: 4, height: 4)
                            Text(ex.name)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.muted)
                            Spacer()
                            Text(pluralise(ex.setCount, "set"))
                                .font(.system(size: 11))
                                .foregroundStyle(colors.muted)
                        }
                    }
                }
                .padding(.top, 12)
            } else {
                Text("No exercises logged.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
                    .padding(.top, 8)
            }

            Text("Tap to view")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, 12)
        }
        .padding(20)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - PlanPickerSheet

private struct PlanPickerSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let plans: [WorkoutPlan]
    let onSelect: (WorkoutPlan) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                List(plans) { plan in
                    Button {
                        dismiss()
                        onSelect(plan)
                    } label: {
                        HStack {
                            Text(plan.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(colors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.muted)
                        }
                    }
                    .listRowBackground(colors.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
        }
    }
}
