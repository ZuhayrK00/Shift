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
    @State private var nextProgramPlan: WorkoutPlan?
    @State private var scheduledPlan: WorkoutPlan?
    @State private var showPlanPicker = false
    @State private var isLoading = false
    @State private var starting = false
    @State private var navigationPath = NavigationPath()
    @State private var activityData: ActivityData?
    @State private var showActivityDetail = false
    @State private var currentStreak: Int = 0
    @State private var workoutError: String?
    @State private var weeklySummary: WeeklyTrainingSummary?
    @State private var recoverySnapshot: RecoverySnapshot?
    @State private var showRecoveryCheckIn = false

    private var todayKey: String { toLocalDateKey(Date()) }
    private var selectedKey: String { toLocalDateKey(selectedDate) }
    private var isToday: Bool { selectedKey == todayKey }
    private var isPast: Bool { selectedKey < todayKey }
    private var isFuture: Bool { selectedDate > noonOfLocalDate(Date()) }
    private var preferredPlan: WorkoutPlan? { scheduledPlan ?? nextProgramPlan }

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

                        if isToday,
                           authManager.user?.settings.healthKit.recoveryGuidance == true,
                           let recoverySnapshot {
                            RecoveryGuidanceCard(snapshot: recoverySnapshot) {
                                showRecoveryCheckIn = true
                            }
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

                        if isToday, let weeklySummary, weeklySummary.workoutCount > 0 {
                            weeklyTrainingCard(weeklySummary)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
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
        .task {
            await loadData()
            if let sessionId = ShiftDeepLinkStore.consumeWorkoutSessionId() {
                openWorkout(sessionId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchDidUpdateWorkout)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftDeepLinkStartWorkout)) { _ in
            Task { await startWorkout(plan: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftShortcutStartNextWorkout)) { _ in
            Task {
                if preferredPlan == nil { await loadData() }
                if let preferredPlan {
                    await startWorkout(plan: preferredPlan)
                } else {
                    showPlanPicker = !plans.isEmpty
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftShortcutResumeWorkout)) { _ in
            Task {
                await loadSessionsForDate()
                if let active = inProgressSessions.first {
                    openWorkout(active.id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftDeepLinkOpenWorkout)) { notification in
            if let sessionId = notification.userInfo?["sessionId"] as? String {
                ShiftDeepLinkStore.storeWorkoutSessionId(sessionId)
                openWorkout(sessionId)
            }
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
        .onChange(of: authManager.user?.settings.trainingSchedule) {
            updateScheduledPlan()
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanPickerSheet(plans: plans) { plan in
                Task { await startWorkout(plan: plan) }
            }
        }
        .sheet(isPresented: $showRecoveryCheckIn) {
            RecoveryCheckInSheet(currentValue: recoverySnapshot?.checkIn) { value in
                RecoveryCheckInStore.save(value)
                Task { recoverySnapshot = await RecoveryGuidanceService.load() }
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

    private func openWorkout(_ sessionId: String) {
        _ = ShiftDeepLinkStore.consumeWorkoutSessionId()
        guard navigationPath.isEmpty else { return }
        navigationPath.append(sessionId)
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
        VStack(spacing: 10) {
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

                if let preferredPlan {
                    Button {
                        Task { await startWorkout(plan: preferredPlan) }
                    } label: {
                        VStack(spacing: 1) {
                            Text("Next workout")
                                .font(.system(size: 11, weight: .medium))
                            Text(preferredPlan.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(starting)
                    .opacity(starting ? 0.5 : 1)
                } else if !plans.isEmpty {
                    Button {
                        showPlanPicker = true
                    } label: {
                        Text("Select plan")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(starting)
                    .opacity(starting ? 0.5 : 1)
                }
            }

            if preferredPlan != nil && plans.count > 1 {
                Button("Choose another workout") {
                    showPlanPicker = true
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.muted)
            }
        }
    }

    // MARK: - Future state

    private var futureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundStyle(scheduledPlan == nil ? colors.muted : colors.accent)
            if let scheduledPlan {
                Text(scheduledPlan.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.text)
                Text("Scheduled workout")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
            } else if authManager.user?.settings.trainingSchedule
                .hasExplicitRestDay(for: selectedDate) == true {
                Text("Rest day")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.muted)
            } else {
                Text("Nothing scheduled")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.muted)
            }
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

    private func weeklyTrainingCard(_ summary: WeeklyTrainingSummary) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("This week")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.text)
                Spacer()
                if let change = summary.volumeChangePercent {
                    Text("\(change >= 0 ? "+" : "")\(change)% volume")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(change >= 0 ? colors.success : colors.muted)
                }
            }

            HStack(spacing: 0) {
                weeklyStat("\(summary.workoutCount)", "Workouts")
                weeklyStat("\(summary.workingSetCount)", "Working sets")
                weeklyStat(formattedWeeklyVolume(summary.volume), weightUnit)
            }

            if !summary.muscleNames.isEmpty {
                Text(summary.muscleNames.prefix(5).joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
                    .lineLimit(2)
            } else {
                Text("Your trained muscle groups will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.border, lineWidth: 1))
    }

    private func weeklyStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightUnit: String {
        authManager.user?.settings.weightUnit ?? "kg"
    }

    private func formattedWeeklyVolume(_ kg: Double) -> String {
        let converted = convertWeight(kg, to: weightUnit)
        return converted >= 1000
            ? String(format: "%.1fk", converted / 1000)
            : "\(Int(converted.rounded()))"
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
        updateScheduledPlan()
        completedDates = fetchedCompleted
        inProgressDates = fetchedInProgress
        isLoading = false

        if let userID = authManager.currentUserId {
            let completedSessions = (try? await SessionRepository.findCompleted(userId: userID)) ?? []
            let grouped = WorkoutProgramService.summaries(
                plans: fetchedPlans,
                completedSessions: completedSessions,
                userID: userID
            )
            nextProgramPlan = grouped.programs.first(where: \.isActive)?.nextWorkout?.plan
        } else {
            nextProgramPlan = nil
            weeklySummary = nil
        }

        await loadSessionsForDate()
        await loadStreak()
        if let userID = authManager.currentUserId {
            weeklySummary = try? await WeeklyTrainingSummaryService.load(
                userID: userID,
                weekStartsOn: authManager.user?.settings.weekStartsOn ?? "monday"
            )
        }

        // Load HealthKit activity in background
        if HealthKitService.isAvailable,
           let user = authManager.user,
           user.settings.healthKit.showDailyActivity {
            _ = try? await HealthKitService.requestAuthorization(
                settings: user.settings.healthKit,
                stepGoalTracking: user.settings.dailyStepGoal != nil
                    && user.settings.notifications.stepGoalAchievements
            )
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        } else {
            activityData = nil
        }
        if authManager.user?.settings.healthKit.recoveryGuidance == true {
            recoverySnapshot = await RecoveryGuidanceService.load()
        } else {
            recoverySnapshot = nil
        }
    }

    private func loadSessionsForDate() async {
        updateScheduledPlan()
        async let completed = WorkoutService.getCompletedSessions(for: selectedDate)
        async let inProgress = WorkoutService.getInProgressSessions(for: selectedDate)
        completedSessions = (try? await completed) ?? []
        inProgressSessions = (try? await inProgress) ?? []

        // Load activity for selected date
        if HealthKitService.isAvailable,
           authManager.user?.settings.healthKit.showDailyActivity == true {
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        } else {
            activityData = nil
        }
    }

    private func updateScheduledPlan() {
        let planID = authManager.user?.settings.trainingSchedule.planID(for: selectedDate)
        scheduledPlan = plans.first { $0.id == planID }
    }

    /// Lightweight refresh for when we return from a pushed view (e.g. after discarding a workout).
    private func refreshAfterNavigation() async {
        async let sessionsRefresh: () = loadSessionsForDate()
        async let completedDatesResult = WorkoutService.getCompletedSessionDates()
        async let inProgressDatesResult = WorkoutService.getInProgressSessionDates()

        _ = await sessionsRefresh
        completedDates = (try? await completedDatesResult) ?? []
        inProgressDates = (try? await inProgressDatesResult) ?? []

        if HealthKitService.isAvailable,
           authManager.user?.settings.healthKit.showDailyActivity == true {
            activityData = await HealthKitService.fetchActivity(for: selectedDate)
        } else {
            activityData = nil
        }

        await loadStreak()
        if let userID = authManager.currentUserId {
            weeklySummary = try? await WeeklyTrainingSummaryService.load(
                userID: userID,
                weekStartsOn: authManager.user?.settings.weekStartsOn ?? "monday"
            )
        }
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
            .foregroundStyle(colors.onAccent)
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
