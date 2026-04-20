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
    @State private var activityData: ActivityData?
    @State private var showActivityDetail = false
    @State private var currentStreak: Int = 0
    @State private var workoutError: String?

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
                            inProgressDates: inProgressDates,
                            weekStartsOn: authManager.user?.settings.weekStartsOn ?? "monday"
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

                        // Streak card (only on today)
                        if isToday && currentStreak > 0 {
                            streakCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }

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

                        // HealthKit activity (below workouts)
                        if !isFuture, let activity = activityData {
                            Button {
                                showActivityDetail = true
                            } label: {
                                activityCard(activity)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: String.self) { sessionId in
                WorkoutView(sessionId: sessionId)
            }
            .navigationDestination(isPresented: $showActivityDetail) {
                ActivityDetailView(activityData: activityData ?? ActivityData())
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .watchDidUpdateWorkout)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftDeepLinkStartWorkout)) { _ in
            Task { await startWorkout(plan: nil) }
        }
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
        .alert("Error", isPresented: .init(
            get: { workoutError != nil },
            set: { if !$0 { workoutError = nil } }
        )) {
            Button("OK") { workoutError = nil }
        } message: {
            Text(workoutError ?? "")
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

            // Show start button only if no sessions at all for this day
            if inProgressSessions.isEmpty && completedSessions.isEmpty {
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

    // MARK: - Streak card

    private var streakCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(currentStreak) day streak")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.text)
                Text(currentStreak >= 7
                     ? "You're on fire! Keep it up."
                     : "Don't break the chain!")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
            }

            Spacer()
        }
        .padding(14)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Activity card

    private func activityCard(_ activity: ActivityData) -> some View {
        VStack(spacing: 16) {
            // Rings row
            HStack(spacing: 24) {
                // Activity rings
                ZStack {
                    // Move ring (outer)
                    Circle()
                        .stroke(colors.border, lineWidth: 6)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: min(1.0, activity.moveGoal > 0 ? activity.moveCalories / activity.moveGoal : 0))
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))

                    // Exercise ring (middle)
                    Circle()
                        .stroke(colors.border, lineWidth: 6)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: min(1.0, activity.exerciseGoal > 0 ? activity.exerciseMinutes / activity.exerciseGoal : 0))
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    // Stand ring (inner)
                    Circle()
                        .stroke(colors.border, lineWidth: 6)
                        .frame(width: 40, height: 40)
                    Circle()
                        .trim(from: 0, to: min(1.0, activity.standGoal > 0 ? activity.standHours / activity.standGoal : 0))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                }

                // Stats
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Move")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.red)
                        Spacer()
                        Text("\(Int(activity.moveCalories))/\(Int(activity.moveGoal)) kcal")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.text)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Exercise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.green)
                        Spacer()
                        Text("\(Int(activity.exerciseMinutes))/\(Int(activity.exerciseGoal)) min")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.text)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.cyan).frame(width: 8, height: 8)
                        Text("Stand")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.cyan)
                        Spacer()
                        Text("\(Int(activity.standHours))/\(Int(activity.standGoal)) hrs")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.text)
                    }
                }
            }

            // Steps
            HStack {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.accent)
                Text("Steps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.muted)
                Spacer()
                if let goal = authManager.user?.settings.dailyStepGoal {
                    Text("\(formatSteps(activity.steps))/\(formatSteps(goal))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.text)
                } else {
                    Text(formatSteps(activity.steps))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.text)
                }
            }
            .padding(.top, 4)

            // Distance
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.accent)
                Text("Distance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.muted)
                Spacer()
                Text(formatDistance(activity.distanceKm))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.text)
            }
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private func formatDistance(_ km: Double) -> String {
        let unit = authManager.user?.settings.distanceUnit ?? "km"
        let value = unit == "mi" ? km * 0.621371 : km
        return String(format: "%.2f %@", value, unit)
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
        await loadStreak()

        // Load HealthKit activity in background
        if HealthKitService.isAvailable {
            _ = try? await HealthKitService.requestAuthorization()
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        }
    }

    private func loadSessionsForDate() async {
        async let completed = WorkoutService.getCompletedSessions(for: selectedDate)
        async let inProgress = WorkoutService.getInProgressSessions(for: selectedDate)
        completedSessions = (try? await completed) ?? []
        inProgressSessions = (try? await inProgress) ?? []

        // Load activity for selected date
        if HealthKitService.isAvailable {
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        }
    }

    /// Lightweight refresh for when we return from a pushed view (e.g. after discarding a workout).
    private func refreshAfterNavigation() async {
        async let sessionsRefresh: () = loadSessionsForDate()
        async let completedDatesResult = WorkoutService.getCompletedSessionDates()
        async let inProgressDatesResult = WorkoutService.getInProgressSessionDates()

        _ = await sessionsRefresh
        completedDates = (try? await completedDatesResult) ?? []
        inProgressDates = (try? await inProgressDatesResult) ?? []

        if HealthKitService.isAvailable {
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        }

        await loadStreak()
    }

    private func loadStreak() async {
        guard let userId = authManager.currentUserId else { return }
        let allCompleted = (try? await SessionRepository.findCompleted(userId: userId)) ?? []
        let settings = authManager.user?.settings ?? .default
        let result = WidgetDataService.calculateStreak(
            sessions: allCompleted,
            weekStartsOn: settings.weekStartsOn
        )
        currentStreak = result.count
    }

    private func startWorkout(plan: WorkoutPlan?) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }

        // If there's already an in-progress session for this date, navigate to it
        if let existingId = try? await WorkoutService.getInProgressSessionId(for: selectedDate) {
            navigationPath.append(existingId)
            return
        }

        do {
            let startedAt = isToday ? Date() : noonOfLocalDate(selectedDate)
            let session: WorkoutSession
            if let plan {
                session = try await PlanService.createSessionFromPlan(plan.id, startedAt: startedAt)
            } else {
                session = try await WorkoutService.createSession(startedAt: startedAt)
            }
            navigationPath.append(session.id)
        } catch {
            workoutError = "Failed to start workout. Please try again."
        }
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

    private var timer: RestTimerManager { .shared }

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

            // Rest timer (visible when timer is running)
            if timer.isActive {
                CompactRestTimerView()
                    .padding(.top, 12)
            }

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
