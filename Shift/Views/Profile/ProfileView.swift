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

    private var user: User? { authManager.user }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Progress (weight, measurements, photos)
                    progressCard
                        .padding(.horizontal, 16)

                    // Weight goal
                    weightGoalCard
                        .padding(.horizontal, 16)

                    // Step goal
                    stepGoalCard
                        .padding(.horizontal, 16)

                    // Weekly goal
                    frequencyGoalCard
                        .padding(.horizontal, 16)

                    // Exercise goals
                    if !activeExerciseGoals.isEmpty {
                        exerciseGoalsCard
                            .padding(.horizontal, 16)
                    }

                    // Personal bests
                    personalBestsCard
                        .padding(.horizontal, 16)

                    Spacer().frame(height: 32)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(colors.muted)
                }
            }
        }
        .navigationDestination(isPresented: $showProgress) {
            ProgressTrackingView()
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(onSaved: {
                toastMessage = "Settings saved"
                showToast = true
            })
        }
        .navigationDestination(isPresented: $showAllPBs) {
            PersonalBestsView()
        }
        .navigationDestination(for: Exercise.self) { exercise in
            ExerciseDetailView(exercise: exercise, initialTab: .goals)
        }
        .sheet(isPresented: $showWeightGoalEditor) {
            WeightGoalEditorSheet {
                Task { await loadProgressData() }
            }
        }
        .sheet(isPresented: $showStepGoalEditor) {
            StepGoalEditorSheet {
                Task {
                    await GoalNotificationService.refreshConfiguration()
                    await GoalNotificationService.handleStepCountChange()
                }
            }
        }
        .sheet(isPresented: $showFrequencyEditor) {
            FrequencyGoalEditorSheet {
                Task { frequencyProgress = try? await GoalService.getFrequencyProgress() }
            }
        }
        .task {
            await loadPersonalBests()
            await loadExerciseGoals()
            await loadProgressData()
            await loadTodaySteps()
            frequencyProgress = try? await GoalService.getFrequencyProgress()
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.onSuccess)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(colors.success)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showToast)
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [colors.accent, colors.accent2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 58, height: 58)

                AvatarView(
                    url: user?.profilePictureUrl,
                    initials: user?.initials ?? "?",
                    size: 50
                )
            }

            Text("Hi, \(user?.displayName ?? "there")")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colors.text)

            Spacer()
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Progress card

    private var progressCard: some View {
        let weightUnit = user?.settings.weightUnit ?? "kg"

        return Button {
            showProgress = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.accent)
                    Text("Progress")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .textCase(.uppercase)
                        .kerning(0.3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.muted)
                }

                HStack(spacing: 8) {
                    progressCell(
                        icon: "scalemass.fill",
                        title: "Weight",
                        value: latestWeight.map { formatWeightValue($0.weight) + " " + weightUnit },
                        hasData: latestWeight != nil
                    )
                    progressCell(
                        icon: "ruler",
                        title: "Body",
                        value: latestMeasurements.isEmpty ? nil : "\(latestMeasurements.count) logged",
                        hasData: !latestMeasurements.isEmpty
                    )
                    if user?.settings.lockPhotos == true {
                        progressCell(
                            icon: "lock.fill",
                            title: "Photos",
                            value: "Locked",
                            hasData: false
                        )
                    } else {
                        progressCell(
                            icon: "camera.fill",
                            title: "Photos",
                            value: latestProgressPhoto != nil ? "Logged" : nil,
                            hasData: latestProgressPhoto != nil
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func progressCell(icon: String, title: String, value: String?, hasData: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(hasData ? colors.accent : colors.muted)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(colors.muted)
            Text(value ?? "—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(hasData ? colors.text : colors.muted.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatWeightValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: - Weight goal card

    private var weightGoalCard: some View {
        let settings = user?.settings ?? .default
        let targetWeight = settings.targetWeight
        let weightUnit = settings.weightUnit
        let currentWeight = latestWeight?.weight
        let deadline: Date? = settings.targetWeightDeadline.flatMap {
            ISO8601DateFormatter.shared.date(from: $0)
            ?? ISO8601DateFormatter.sharedWithFractional.date(from: $0)
        }
        let daysRemaining: Int? = deadline.map { max(0, Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0) }

        let progress: Double = {
            guard let target = targetWeight, let current = currentWeight, target != current else { return 0 }
            let startWeight = user?.weight ?? current
            if target < startWeight {
                // Losing weight
                guard startWeight > target else { return 1.0 }
                return min(1.0, max(0, (startWeight - current) / (startWeight - target)))
            } else {
                // Gaining weight
                guard target > startWeight else { return 1.0 }
                return min(1.0, max(0, (current - startWeight) / (target - startWeight)))
            }
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.accent2)
                    Text("Weight Goal")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                Button {
                    showWeightGoalEditor = true
                } label: {
                    Image(systemName: targetWeight != nil ? "pencil" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 32, height: 32)
                        .background(colors.accent.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let target = targetWeight {
                HStack(spacing: 20) {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(colors.border, lineWidth: 8)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 1.0
                                    ? AnyShapeStyle(colors.success)
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [colors.accent2, colors.accent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(progress >= 1.0 ? colors.success : colors.accent2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let current = currentWeight {
                            Text("\(formatWeightValue(current)) \(weightUnit)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.text)
                        }
                        Text("Target: \(formatWeightValue(target)) \(weightUnit)")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)

                        if let days = daysRemaining {
                            if days == 0 {
                                Text("Deadline reached")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(colors.warning)
                            } else {
                                Text("\(days) day\(days == 1 ? "" : "s") remaining")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(colors.muted)
                            }
                        }

                        if progress >= 1.0 {
                            Text("Goal reached!")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.success)
                        }
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.muted.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No weight goal set")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text("Set a target weight and deadline to track progress.")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                }
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

    // MARK: - Step goal card

    private var stepGoalCard: some View {
        let stepGoal = user?.settings.dailyStepGoal
        let progress: Double = {
            guard let goal = stepGoal, goal > 0 else { return 0 }
            return min(1.0, Double(todaySteps) / Double(goal))
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.accent)
                    Text("Daily Steps")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                Button {
                    showStepGoalEditor = true
                } label: {
                    Image(systemName: stepGoal != nil ? "pencil" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 32, height: 32)
                        .background(colors.accent.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let goal = stepGoal {
                HStack(spacing: 20) {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(colors.border, lineWidth: 8)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 1.0
                                    ? AnyShapeStyle(colors.success)
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [colors.accent, colors.accent2],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "figure.walk")
                            .font(.system(size: 18))
                            .foregroundStyle(progress >= 1.0 ? colors.success : colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatSteps(todaySteps))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.text)
                        Text("of \(formatSteps(goal)) steps")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)

                        if progress >= 1.0 {
                            Text("Goal reached!")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.success)
                        }
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.muted.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No step goal set")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text("Set a daily step target to stay active.")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                }
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

    // MARK: - Weekly goal card

    @ViewBuilder
    private var frequencyGoalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.warning)
                    Text("Weekly Goal")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                Button {
                    showFrequencyEditor = true
                } label: {
                    Image(systemName: frequencyProgress != nil ? "pencil" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 32, height: 32)
                        .background(colors.accent.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let progress = frequencyProgress {
                HStack(spacing: 20) {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(colors.border, lineWidth: 10)
                            .frame(width: 88, height: 88)

                        Circle()
                            .trim(from: 0, to: min(1.0, Double(progress.completed) / Double(max(1, progress.target))))
                            .stroke(
                                LinearGradient(
                                    colors: progress.completed >= progress.target
                                        ? [colors.success, colors.success.opacity(0.7)]
                                        : [colors.accent, colors.accent2],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 88, height: 88)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 0) {
                            Text("\(progress.completed)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.text)
                            Text("of \(progress.target)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if progress.completed >= progress.target {
                            Text(progress.completed > progress.target
                                 ? "Above and beyond!"
                                 : "Goal complete!")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(colors.success)
                        } else {
                            let remaining = progress.target - progress.completed
                            Text("\(remaining) session\(remaining == 1 ? "" : "s") to go")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(colors.text)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text("\(progress.daysRemainingInWeek) day\(progress.daysRemainingInWeek == 1 ? "" : "s") left this week")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(colors.muted)

                        if progress.trainingDays.isEmpty {
                            Text("Choose your training days")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        } else {
                            HStack(spacing: 5) {
                                ForEach(1...7, id: \.self) { day in
                                    Text(weekdayInitial(for: day))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(
                                            progress.trainingDays.contains(day)
                                                ? colors.onAccent
                                                : colors.muted
                                        )
                                        .frame(width: 23, height: 23)
                                        .background(
                                            progress.trainingDays.contains(day)
                                                ? colors.accent
                                                : colors.surface2,
                                            in: Circle()
                                        )
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "Training days: \(trainingDayNames(progress.trainingDays))"
                            )
                        }
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.muted.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No goal set")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text("Set a weekly training target to track consistency.")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                }
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

    private func weekdayInitial(for isoWeekday: Int) -> String {
        ["M", "T", "W", "T", "F", "S", "S"][isoWeekday - 1]
    }

    private func trainingDayNames(_ days: [Int]) -> String {
        let names = Calendar.current.weekdaySymbols
        return days.map { isoDay in
            let appleIndex = isoDay == 7 ? 0 : isoDay
            return names[appleIndex]
        }.joined(separator: ", ")
    }

    // MARK: - Exercise goals card

    @ViewBuilder
    private var exerciseGoalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.accent)
                Text("Exercise Goals")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.text)
                Spacer()
                Text("\(activeExerciseGoals.count) active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.surface2)
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(activeExerciseGoals, id: \.goal.id) { item in
                    NavigationLink(value: item.exercise) {
                        exerciseGoalRow(item.goal, exercise: item.exercise)
                    }
                    .buttonStyle(.plain)
                }
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

    private func exerciseGoalRow(_ goal: ExerciseGoal, exercise: Exercise) -> some View {
        let days = goal.daysRemaining
        let weightUnit = user?.settings.weightUnit ?? "kg"

        return HStack(spacing: 12) {
            // Mini progress ring
            let currentMax = exerciseCurrentMaxes[goal.exerciseId] ?? goal.baselineWeight
            let progress = goal.targetWeight > goal.baselineWeight
                ? min(1.0, max(0, (currentMax - goal.baselineWeight) / (goal.targetWeight - goal.baselineWeight)))
                : 0.0

            ZStack {
                Circle()
                    .stroke(colors.border, lineWidth: 3)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Text(formatWeight(goal.targetWeight, unit: weightUnit))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            HStack(spacing: 6) {
                Text(days == 0 ? "Today" : days == 1 ? "1d" : "\(days)d")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(days <= 3 ? colors.danger : colors.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }
        }
        .padding(12)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Personal bests card

    @ViewBuilder
    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    Text("Personal Bests")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                Button {
                    showAllPBs = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                }
                .buttonStyle(.plain)
            }

            if isLoadingPBs {
                ProgressView()
                    .tint(colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if personalBests.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "medal")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.muted.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No records yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text("Complete workouts to see your records.")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(personalBests.prefix(3).enumerated()), id: \.element.exerciseId) { index, pb in
                        ProfilePBRow(pb: pb, rank: index, weightUnit: user?.settings.weightUnit ?? "kg")
                    }
                }
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

    // MARK: - Data loading

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
