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
    @State private var isLoadingGoals = false

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

                    // Attribution
                    Text("Shift · Built with SwiftUI")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
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
        .sheet(isPresented: $showFrequencyEditor) {
            FrequencyGoalEditorSheet {
                Task { frequencyProgress = try? await GoalService.getFrequencyProgress() }
            }
        }
        .task {
            await loadPersonalBests()
            await loadExerciseGoals()
            frequencyProgress = try? await GoalService.getFrequencyProgress()
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
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

                        // Day indicators
                        HStack(spacing: 6) {
                            ForEach(0..<progress.target, id: \.self) { i in
                                Circle()
                                    .fill(i < progress.completed
                                          ? (progress.completed >= progress.target ? colors.success : colors.accent)
                                          : colors.border)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .padding(.top, 2)
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
            let currentMax = activeExerciseGoals.first(where: { $0.goal.id == goal.id })
                .map { _ in goal.baselineWeight } ?? goal.baselineWeight
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

    private func loadExerciseGoals() async {
        guard let userId = try? authManager.requireUserId() else { return }
        isLoadingGoals = true
        let goals = (try? await ExerciseGoalRepository.findActiveForUser(userId)) ?? []
        let exerciseIds = goals.map(\.exerciseId)
        let exerciseMap = (try? await ExerciseRepository.findByIds(exerciseIds)) ?? [:]
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

    @State private var target: Int = 3
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    Section("Sessions per week") {
                        Stepper(
                            "\(target) day\(target == 1 ? "" : "s")",
                            value: $target,
                            in: 1...7
                        )
                        .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    Section {
                        Button(role: .destructive) {
                            Task { await clearGoal() }
                        } label: {
                            Text("Remove Goal")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(colors.surface)
                }
                .scrollContentBackground(.hidden)
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
                    .disabled(isSaving)
                }
            }
            .onAppear {
                target = authManager.user?.settings.weeklyFrequencyGoal ?? 3
            }
        }
    }

    private func save() async {
        isSaving = true
        var settings = authManager.user?.settings ?? .default
        settings.weeklyFrequencyGoal = target
        try? await ProfileService.updateSettings(settings)
        await authManager.refreshUser()
        Task { await GoalNotificationService.scheduleAllNotifications() }
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func clearGoal() async {
        isSaving = true
        var settings = authManager.user?.settings ?? .default
        settings.weeklyFrequencyGoal = nil
        try? await ProfileService.updateSettings(settings)
        await authManager.refreshUser()
        Task { await GoalNotificationService.scheduleAllNotifications() }
        isSaving = false
        onSaved?()
        dismiss()
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
                AsyncImage(url: imgUrl) { phase in
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
                .foregroundStyle(.white)
        }
    }
}
