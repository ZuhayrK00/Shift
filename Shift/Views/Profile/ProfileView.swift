import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var personalBests: [PersonalBest] = []
    @State private var isLoadingPBs = false
    @State private var showAllPBs = false
    @State private var showSettings = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var frequencyProgress: FrequencyProgress?
    @State private var showFrequencyEditor = false
    @State private var activeExerciseGoals: [(goal: ExerciseGoal, exercise: Exercise)] = []
    @State private var exerciseCurrentMaxes: [String: Double] = [:]  // exerciseId -> current max weight
    @State private var isLoadingGoals = false
    @State private var showProgress = false
    @State private var latestWeight: WeightEntry?
    @State private var latestMeasurements: [BodyMeasurement] = []
    @State private var latestProgressPhoto: ProgressPhoto?
    @State private var showStepGoalEditor = false
    @State private var showWeightGoalEditor = false
    @State private var todaySteps: Int = 0

    @State private var training = TrainingHub()
    @State private var enduranceGoals: [EnduranceGoal] = []
    @State private var showEnduranceGoals = false
    @State private var showEnduranceRecords = false
    @State private var showCalendar = false
    @State private var goalExercise: Exercise?
    private var user: User? { authManager.user }

    var body: some View {
        ScrollView {
            ProfileOverviewLayout(data: overview, avatar: {
                AvatarView(url: user?.profilePictureUrl, initials: user?.initials ?? "?", size: 66)
                    .overlay(Circle().stroke(colors.accent.opacity(0.5), lineWidth: 2))
            }, action: open)
        }.background(colors.bg).foregroundStyle(colors.text)
            .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(colors.muted) }.accessibilityLabel("Settings")
            } }
            .navigationDestination(isPresented: $showProgress) { ProgressTrackingView() }
            .navigationDestination(isPresented: $showSettings) { SettingsView(onSaved: { toastMessage = "Settings saved"; showToast = true; Task { await loadOverview() } }) }
            .navigationDestination(isPresented: $showAllPBs) { PersonalBestsView() }
            .navigationDestination(isPresented: $showEnduranceGoals) { EnduranceGoalsView() }
            .navigationDestination(isPresented: $showEnduranceRecords) { EnduranceProgressView() }
            .navigationDestination(item: $goalExercise) { ExerciseDetailView(exercise: $0, initialTab: .goals) }
            .sheet(isPresented: $showWeightGoalEditor, onDismiss: { Task { await loadOverview() } }) { WeightGoalEditorSheet { Task { await loadProgressData() } } }
            .sheet(isPresented: $showStepGoalEditor, onDismiss: { Task { await loadOverview() } }) { StepGoalEditorSheet { Task { await GoalNotificationService.refreshConfiguration(); await GoalNotificationService.handleStepCountChange() } } }
            .sheet(isPresented: $showFrequencyEditor, onDismiss: { Task { await loadOverview() } }) { FrequencyGoalEditorSheet { Task { frequencyProgress = try? await GoalService.getFrequencyProgress() } } }
            .sheet(isPresented: $showCalendar, onDismiss: { EnduranceRecorder.shared.openPendingCalendarSession() }) { TrainingCalendarView() }
            .task(id: authManager.currentUserId) { await loadOverview() }
            .refreshable { await loadOverview() }
            .onReceive(NotificationCenter.default.publisher(for: .shiftUserDataDidSync)) { _ in Task { await loadOverview() } }
            .onReceive(NotificationCenter.default.publisher(for: .shiftEnduranceDidChange)) { _ in Task { await training.load(); await loadEnduranceGoals() } }
            .overlay(alignment: .bottom) {
                if showToast { Text(toastMessage).font(.subheadline.weight(.semibold)).padding(14).foregroundStyle(colors.onSuccess).background(colors.success, in: Capsule()).padding(.bottom, 20).onAppear { Task { try? await Task.sleep(for: .seconds(2)); showToast = false } } }
            }
    }
    private var overview: ProfileOverviewData {
        let settings = user?.settings ?? .default
        let start = GoalService.startOfCurrentWeek(weekStartsOn: settings.weekStartsOn)
        let strength = training.workouts.filter { $0.startedAt >= start && ($0.endedAt ?? .distantFuture) <= Date() }
        let endurance = training.activities.filter { $0.startedAt >= start && $0.endedAt <= Date() }
        var rows: [ProfileOverviewRow] = []
        let frequency = frequencyProgress
        rows.append(.init(id: "frequency", title: "Weekly consistency", subtitle: frequency.map { "\($0.completed) of \($0.target) sessions this week" } ?? "Choose your training days", symbol: "figure.mixed.cardio", progress: frequency.map { Double($0.completed) / Double(max(1, $0.target)) }, action: .frequency))
        rows.append(.init(id: "steps", title: "Daily movement", subtitle: settings.dailyStepGoal.map { "\(todaySteps.formatted()) of \($0.formatted()) steps today" } ?? "Set a daily step goal", symbol: "figure.walk", progress: settings.dailyStepGoal.map { Double(todaySteps) / Double(max(1, $0)) }, endurance: true, action: .steps))
        if let target = settings.targetWeight {
            rows.append(.init(id: "weight", title: "Weight goal", subtitle: "Target \(formatWeight(target, unit: settings.weightUnit))", symbol: "scalemass", value: "Edit", action: .weight))
        } else { rows.append(.init(id: "weight", title: "Weight goal", subtitle: "Choose a target when you're ready", symbol: "scalemass", action: .weight)) }
        var goalCalendar = Calendar.current; goalCalendar.firstWeekday = settings.weekStartsOn == "sunday" ? 1 : 2
        if enduranceGoals.isEmpty { rows.append(.init(id: "endurance", title: "Endurance goals", subtitle: "Distance, time or weekly activities", symbol: "figure.run", endurance: true, action: .enduranceGoals)) }
        for goal in enduranceGoals {
            let progress = goal.progress(in: training.activities, calendar: goalCalendar)
            let target: String
            switch goal.metric {
            case .distance: target = EnduranceFormat.distance(goal.target, unit: settings.distanceUnit)
            case .duration: target = "\(Int(goal.target / 60)) minutes"
            case .activities: target = "\(Int(goal.target)) activities"
            }
            rows.append(.init(id: goal.id, title: "\(goal.sport?.title ?? "Endurance") · \(goal.period.title.lowercased())", subtitle: "\(goal.metric.title) goal · \(target)", symbol: goal.sport?.symbol ?? "figure.mixed.cardio", progress: progress / max(1, goal.target), endurance: true, action: .enduranceGoals))
        }
        for (goal, exercise) in activeExerciseGoals {
            let current = exerciseCurrentMaxes[exercise.id] ?? goal.baselineWeight
            let denominator = goal.targetWeight - goal.baselineWeight
            rows.append(.init(id: goal.id, title: exercise.name, subtitle: "Target \(formatWeight(goal.targetWeight, unit: settings.weightUnit))", symbol: "target", progress: denominator > 0 ? (current - goal.baselineWeight) / denominator : nil, action: .exercise(exercise.id)))
        }
        let records = EnduranceInsights.records(training.activities, userID: authManager.currentUserId ?? "")
        return .init(name: user?.displayName ?? "Your profile", strengthCount: strength.count, enduranceCount: endurance.count,
            distance: EnduranceFormat.distance(endurance.reduce(0) { $0 + $1.distanceMeters }, unit: settings.distanceUnit),
            enduranceTime: EnduranceFormat.duration(endurance.reduce(0) { $0 + $1.activeSeconds }), goals: rows,
            weight: latestWeight.map { formatWeight($0.weight, unit: settings.weightUnit) } ?? "Not logged",
            body: latestMeasurements.isEmpty ? "Not logged" : "\(latestMeasurements.count) logged",
            photos: settings.lockPhotos ? "Locked" : latestProgressPhoto == nil ? "Not logged" : "Logged",
            strengthRecords: personalBests.map { "\($0.displayName) · \(formatWeight($0.maxWeight, unit: settings.weightUnit))" },
            enduranceRecords: records.map { "\($0.title) · \($0.isTime ? EnduranceFormat.duration($0.value) : EnduranceFormat.distance($0.value, unit: settings.distanceUnit))" },
            loading: training.loading || isLoadingPBs, error: training.error)
    }
    private func open(_ action: ProfileOverviewAction) {
        switch action {
        case .frequency: showFrequencyEditor = true
        case .steps: showStepGoalEditor = true
        case .weight: showWeightGoalEditor = true
        case .body: showProgress = true
        case .strengthRecords: showAllPBs = true
        case .enduranceRecords: showEnduranceRecords = true
        case .enduranceGoals: showEnduranceGoals = true
        case .calendar: showCalendar = true
        case .exercise(let id): goalExercise = activeExerciseGoals.first { $0.exercise.id == id }?.exercise
        }
    }
    private func loadOverview() async {
        await training.load()
        await loadPersonalBests(); await loadExerciseGoals(); await loadProgressData(); await loadTodaySteps(); await loadEnduranceGoals()
        frequencyProgress = try? await GoalService.getFrequencyProgress()
    }
    private func loadEnduranceGoals() async {
        guard let owner = authManager.currentUserId else { enduranceGoals = []; return }
        let result = (try? await EnduranceStore.shared.all(EnduranceGoal.self, userID: owner)) ?? []
        guard authManager.currentUserId == owner else { return }; enduranceGoals = result
    }
    private func loadPersonalBests() async {
        isLoadingPBs = true
        personalBests = (try? await ExerciseService.getPersonalBests(limit: 5)) ?? []
        isLoadingPBs = false
    }

    private func loadTodaySteps() async {
        let settings = user?.settings ?? .default
        let stepTrackingEnabled = settings.dailyStepGoal != nil
            && settings.notifications.stepGoalAchievements
        if HealthKitService.isAvailable,
           settings.healthKit.showDailyActivity || stepTrackingEnabled {
            let activity = await HealthKitService.fetchTodayActivity()
            todaySteps = activity?.steps ?? 0
        } else {
            todaySteps = 0
        }
    }

    private func loadProgressData() async {
        latestMeasurements = (try? await ProgressService.getLatestPerType()) ?? []
        if user?.settings.lockPhotos != true {
            latestProgressPhoto = try? await ProgressService.getLatestPhoto()
        } else {
            latestProgressPhoto = nil
        }
        if let userId = try? authManager.requireUserId() {
            let entries = (try? await WeightEntryRepository.findAll(userId: userId)) ?? []
            latestWeight = entries.first
        }
    }

    private func loadExerciseGoals() async {
        guard let userId = try? authManager.requireUserId() else { return }
        isLoadingGoals = true
        let goals = (try? await ExerciseGoalRepository.findActiveForUser(userId)) ?? []
        let exerciseIds = goals.map(\.exerciseId)
        let exerciseMap = (try? await ExerciseRepository.findByIds(exerciseIds)) ?? [:]

        // Fetch current max weight for each exercise to show accurate progress rings
        var maxes: [String: Double] = [:]
        for exerciseId in Set(exerciseIds) {
            if let max = try? await ExerciseGoalRepository.findCurrentMaxWeight(exerciseId: exerciseId) {
                maxes[exerciseId] = max
            }
        }
        exerciseCurrentMaxes = maxes

        activeExerciseGoals = goals.compactMap { goal in
            guard let exercise = exerciseMap[goal.exerciseId] else { return nil }
            return (goal: goal, exercise: exercise)
        }
        isLoadingGoals = false
    }
}

// MARK: - ProfilePBRow

private struct ProfilePBRow: View {
    @Environment(\.shiftColors) private var colors
    let pb: PersonalBest
    let rank: Int
    var weightUnit: String = "kg"

    private var rankColor: Color {
        switch rank {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 1: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 2: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return colors.muted
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(rank + 1)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rankColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pb.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Text(pb.achievedAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            Text(formattedWeight)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var formattedWeight: String {
        formatWeight(pb.maxWeight, unit: weightUnit)
    }
}

// MARK: - FrequencyGoalEditorSheet

struct FrequencyGoalEditorSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var selectedDays: Set<Int> = []
    @State private var isSaving = false
    @State private var saveError: String?

    private let weekdays: [(isoDay: Int, short: String, name: String)] = [
        (1, "M", "Monday"),
        (2, "T", "Tuesday"),
        (3, "W", "Wednesday"),
        (4, "T", "Thursday"),
        (5, "F", "Friday"),
        (6, "S", "Saturday"),
        (7, "S", "Sunday")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .fill(colors.accentSoft)
                            .frame(width: 80, height: 80)
                        Image(systemName: "calendar")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }

                    // Value display
                    VStack(spacing: 6) {
                        Text("\(selectedDays.count)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.text)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: selectedDays.count)

                        Text(selectedDays.count == 1
                             ? "training day selected"
                             : "training days selected")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(colors.muted)
                    }

                    Text("Choose the days you normally plan to train. You can change them whenever your routine changes.")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    HStack(spacing: 10) {
                        ForEach(weekdays, id: \.isoDay) { weekday in
                            let isSelected = selectedDays.contains(weekday.isoDay)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if isSelected {
                                        selectedDays.remove(weekday.isoDay)
                                    } else {
                                        selectedDays.insert(weekday.isoDay)
                                    }
                                }
                            } label: {
                                Text(weekday.short)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isSelected ? colors.onAccent : colors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        isSelected ? colors.accent : colors.surface,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                isSelected ? colors.accent : colors.border,
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(weekday.name)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }

                    Spacer()

                    // Error
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }

                    // Remove goal
                    Button {
                        Task { await clearGoal() }
                    } label: {
                        Text("Remove Goal")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(colors.danger.opacity(0.8))
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("Weekly Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isSaving || selectedDays.isEmpty)
                }
            }
            .onAppear {
                let settings = authManager.user?.settings ?? .default
                let savedDays = settings.normalizedWeeklyTrainingDays
                selectedDays = Set(
                    savedDays.isEmpty
                        ? WeeklyTrainingScheduleDefaults.days(
                            for: settings.weeklyFrequencyGoal
                        )
                        : savedDays
                )
            }
        }
    }

    private func save() async {
        guard !selectedDays.isEmpty else { return }
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.weeklyTrainingDays = selectedDays.sorted()
        settings.weeklyFrequencyGoal = selectedDays.count
        settings.weeklyTrainingDaysEffectiveDate =
            TrainingScheduleSettings.dateKey(Date())
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func clearGoal() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.weeklyFrequencyGoal = nil
        settings.weeklyTrainingDays = []
        settings.weeklyTrainingDaysEffectiveDate = nil
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to remove goal: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }
}

// MARK: - StepGoalEditorSheet

struct StepGoalEditorSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var stepGoal: Int = 10000
    @State private var isSaving = false
    @State private var saveError: String?

    private var progress: Double {
        min(Double(stepGoal) / 50000.0, 1.0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Icon in ring
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.15), lineWidth: 6)
                            .frame(width: 100, height: 100)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy(duration: 0.3), value: stepGoal)
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.green)
                    }

                    // Value display
                    VStack(spacing: 6) {
                        Text(formatSteps(stepGoal))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.text)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: stepGoal)

                        Text("steps per day")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(colors.muted)
                    }

                    // +/- controls
                    HStack(spacing: 20) {
                        Button {
                            if stepGoal > 1000 { stepGoal -= 1000 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(stepGoal > 1000 ? colors.text : colors.muted.opacity(0.4))
                                .frame(width: 56, height: 56)
                                .background(colors.surface, in: Circle())
                        }
                        .disabled(stepGoal <= 1000)

                        Button {
                            if stepGoal < 50000 { stepGoal += 1000 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(stepGoal < 50000 ? colors.text : colors.muted.opacity(0.4))
                                .frame(width: 56, height: 56)
                                .background(colors.surface, in: Circle())
                        }
                        .disabled(stepGoal >= 50000)
                    }

                    // Quick presets
                    HStack(spacing: 10) {
                        ForEach([5000, 8000, 10000, 12000, 15000], id: \.self) { preset in
                            Button {
                                stepGoal = preset
                            } label: {
                                Text(preset >= 10000 ? "\(preset / 1000)k" : "\(preset / 1000)k")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(stepGoal == preset ? colors.onSuccess : colors.text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        stepGoal == preset ? colors.success : colors.surface,
                                        in: Capsule()
                                    )
                            }
                        }
                    }

                    Spacer()

                    // Error
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }

                    // Remove goal
                    Button {
                        Task { await clearGoal() }
                    } label: {
                        Text("Remove Goal")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(colors.danger.opacity(0.8))
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("Step Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                stepGoal = authManager.user?.settings.dailyStepGoal ?? 10000
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.dailyStepGoal = stepGoal
        if settings.notifications.stepGoalAchievements {
            _ = try? await HealthKitService.requestAuthorization(
                settings: settings.healthKit,
                stepGoalTracking: true
            )
            _ = await NotificationManager.requestAuthorizationIfNeeded()
        }
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func clearGoal() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.dailyStepGoal = nil
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to remove goal: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

// MARK: - WeightGoalEditorSheet

struct WeightGoalEditorSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var targetWeight: Double = 70
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var saveError: String?

    private var weightUnit: String {
        authManager.user?.settings.weightUnit ?? "kg"
    }

    private var increment: Double {
        authManager.user?.settings.defaultWeightIncrement ?? 2.5
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Icon in ring
                    ZStack {
                        Circle()
                            .stroke(colors.accent2.opacity(0.15), lineWidth: 6)
                            .frame(width: 100, height: 100)
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(colors.accent2)
                    }

                    // Value display
                    VStack(spacing: 6) {
                        Text(formatWeight(targetWeight))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.text)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: targetWeight)

                        Text(weightUnit)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(colors.muted)
                    }

                    // +/- controls
                    HStack(spacing: 20) {
                        Button {
                            if targetWeight > increment { targetWeight -= increment }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(targetWeight > increment ? colors.text : colors.muted.opacity(0.4))
                                .frame(width: 56, height: 56)
                                .background(colors.surface, in: Circle())
                        }
                        .disabled(targetWeight <= increment)

                        Button {
                            if targetWeight < 300 { targetWeight += increment }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(targetWeight < 300 ? colors.text : colors.muted.opacity(0.4))
                                .frame(width: 56, height: 56)
                                .background(colors.surface, in: Circle())
                        }
                        .disabled(targetWeight >= 300)
                    }

                    // Deadline picker
                    VStack(spacing: 8) {
                        Text("Target Date")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.muted)
                        DatePicker(
                            "",
                            selection: $deadline,
                            in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...Calendar.current.date(byAdding: .year, value: 2, to: Date())!,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(colors.accent)
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }

                    Button {
                        Task { await clearGoal() }
                    } label: {
                        Text("Remove Goal")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(colors.danger.opacity(0.8))
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("Weight Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                let settings = authManager.user?.settings ?? .default
                targetWeight = settings.targetWeight ?? authManager.user?.weight ?? 70
                if let deadlineStr = settings.targetWeightDeadline,
                   let d = ISO8601DateFormatter.shared.date(from: deadlineStr)
                       ?? ISO8601DateFormatter.sharedWithFractional.date(from: deadlineStr) {
                    deadline = d
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.targetWeight = targetWeight
        settings.targetWeightDeadline = ISO8601DateFormatter.shared.string(from: deadline)
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func clearGoal() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.targetWeight = nil
        settings.targetWeightDeadline = nil
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to remove goal: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        PhoneSessionManager.shared.sendContextToWatch()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func formatWeight(_ w: Double) -> String {
        w == w.rounded() ? String(format: "%.0f", w) : String(format: "%.1f", w)
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    @Environment(\.shiftColors) private var colors
    let url: String?
    let initials: String
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = url, let imgUrl = URL(string: urlString) {
                CachedAsyncImage(url: imgUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(colors.accent)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(colors.onAccent)
        }
    }
}
