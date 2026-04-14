import SwiftUI

struct GoalEditorSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    let exercise: Exercise
    var existingGoal: ExerciseGoal?
    var onSaved: (() async -> Void)?

    @State private var targetIncrease: Double = 5.0
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var currentMax: Double?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existingGoal != nil }
    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }
    private var increment: Double { authManager.user?.settings.defaultWeightIncrement ?? 2.5 }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    // Current max
                    Section("Current Best") {
                        HStack {
                            Text("Max weight lifted")
                                .foregroundStyle(colors.text)
                            Spacer()
                            if isLoading {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text(currentMax.map { formatWeight($0, unit: weightUnit) } ?? "No history")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .listRowBackground(colors.surface)

                    // Target
                    Section("Target") {
                        HStack {
                            Text("Weight increase")
                                .foregroundStyle(colors.text)
                            Spacer()
                            Text("+\(formatWeightValue(targetIncrease)) \(weightUnit)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .frame(width: 90, alignment: .trailing)
                            Stepper("", value: $targetIncrease, in: increment...200, step: increment)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Target weight")
                                .foregroundStyle(colors.text)
                            Spacer()
                            let baseline = isEditing ? existingGoal!.baselineWeight : (currentMax ?? 0)
                            let target = baseline + targetIncrease
                            Text(formatWeight(target, unit: weightUnit))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(colors.text)
                        }
                    }
                    .listRowBackground(colors.surface)

                    // Deadline
                    Section("Deadline") {
                        DatePicker(
                            "Due by",
                            selection: $deadline,
                            in: tomorrow...,
                            displayedComponents: .date
                        )
                        .foregroundStyle(colors.text)
                        .tint(colors.accent)
                    }
                    .listRowBackground(colors.surface)

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger)
                        }
                        .listRowBackground(colors.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
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
                    .disabled(isSaving || isLoading)
                }
            }
            .task { await loadCurrentMax() }
        }
    }

    private func loadCurrentMax() async {
        isLoading = true
        currentMax = try? await ExerciseGoalRepository.findCurrentMaxWeight(exerciseId: exercise.id)

        // Pre-populate fields when editing
        if let goal = existingGoal {
            targetIncrease = goal.targetWeightIncrease
            deadline = goal.deadline < tomorrow ? tomorrow : goal.deadline
        }

        isLoading = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            if let goal = existingGoal {
                try await GoalService.updateGoal(
                    goal.id,
                    targetWeightIncrease: targetIncrease,
                    deadline: deadline
                )
            } else {
                _ = try await GoalService.createGoal(
                    exerciseId: exercise.id,
                    targetWeightIncrease: targetIncrease,
                    deadline: deadline
                )
            }
            await onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func formatWeightValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
