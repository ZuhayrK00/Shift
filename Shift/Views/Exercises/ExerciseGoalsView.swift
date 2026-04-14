import SwiftUI

struct ExerciseGoalsView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    let exercise: Exercise

    @State private var goals: [ExerciseGoal] = []
    @State private var currentMax: Double?
    @State private var isLoading = true
    @State private var showEditor = false
    @State private var editingGoal: ExerciseGoal?

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }

    private var activeGoals: [ExerciseGoal] { goals.filter { !$0.isCompleted } }
    private var completedGoals: [ExerciseGoal] { goals.filter { $0.isCompleted } }

    @State private var showCompleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView()
                        .tint(colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if goals.isEmpty {
                    emptyState
                } else {
                    // Active goals
                    if !activeGoals.isEmpty {
                        ForEach(activeGoals) { goal in
                            goalCard(goal)
                        }
                    }

                    // Add goal button
                    addGoalButton

                    // Completed goals
                    if !completedGoals.isEmpty {
                        completedSection
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showEditor) {
            GoalEditorSheet(exercise: exercise, existingGoal: editingGoal) {
                await loadGoals()
            }
        }
        .onChange(of: showEditor) { _, isPresented in
            if !isPresented { editingGoal = nil }
        }
        .task { await loadGoals() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundStyle(colors.muted.opacity(0.5))

            Text("No goals yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.text)

            Text("Set a weight target for this exercise and track your progress.")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)

            Button {
                showEditor = true
            } label: {
                Text("Set a Goal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(colors.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Goal card

    private func goalCard(_ goal: ExerciseGoal) -> some View {
        let current = currentMax ?? goal.baselineWeight
        let target = goal.targetWeight
        let progress = target > goal.baselineWeight
            ? min(1.0, max(0, (current - goal.baselineWeight) / (target - goal.baselineWeight)))
            : (current >= target ? 1.0 : 0.0)

        return VStack(alignment: .leading, spacing: 12) {
            // Header: target + deadline
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target: \(formatWeight(target, unit: weightUnit))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)

                    Text("+\(formatWeight(goal.targetWeightIncrease, unit: weightUnit)) from \(formatWeight(goal.baselineWeight, unit: weightUnit))")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    let days = goal.daysRemaining
                    Text(days == 0 ? "Due today" : days == 1 ? "1 day left" : "\(days) days left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(days <= 3 ? colors.danger : colors.accent)

                    Text(goal.deadline, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted)
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colors.surface2)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(progress >= 1.0 ? colors.success : colors.accent)
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Current: \(formatWeight(current, unit: weightUnit))")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(progress >= 1.0 ? colors.success : colors.accent)
                }
            }
        }
        .padding(16)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            editingGoal = goal
            showEditor = true
        }
        .contextMenu {
            Button {
                editingGoal = goal
                showEditor = true
            } label: {
                Label("Edit Goal", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Task {
                    try? await GoalService.deleteGoal(goal.id)
                    await loadGoals()
                }
            } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        }
    }

    // MARK: - Add goal button

    private var addGoalButton: some View {
        Button {
            showEditor = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                Text("Add Goal")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(colors.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.accent.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Completed section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showCompleted.toggle() }
            } label: {
                HStack {
                    Text("Completed (\(completedGoals.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.muted)
                }
            }
            .buttonStyle(.plain)

            if showCompleted {
                ForEach(completedGoals) { goal in
                    completedGoalRow(goal)
                }
            }
        }
        .padding(.top, 8)
    }

    private func completedGoalRow(_ goal: ExerciseGoal) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(colors.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatWeight(goal.targetWeight, unit: weightUnit))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                if let completedAt = goal.completedAt {
                    Text("Achieved \(completedAt, style: .date)")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted)
                }
            }

            Spacer()

            Text("+\(formatWeight(goal.targetWeightIncrease, unit: weightUnit))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.success)
        }
        .padding(12)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    try? await GoalService.deleteGoal(goal.id)
                    await loadGoals()
                }
            } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        }
    }

    // MARK: - Data loading

    private func loadGoals() async {
        isLoading = true
        goals = (try? await ExerciseGoalRepository.findByExercise(exercise.id)) ?? []
        currentMax = try? await ExerciseGoalRepository.findCurrentMaxWeight(exerciseId: exercise.id)
        isLoading = false
    }
}
