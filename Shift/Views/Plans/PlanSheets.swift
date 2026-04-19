import SwiftUI

// MARK: - ExercisePickerSheet
// Reusable exercise search+select sheet used by PlanEditorView.

struct ExercisePickerSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let onAdd: (Exercise) -> Void

    @State private var exercises: [Exercise] = []
    @State private var muscles: [MuscleGroup] = []
    @State private var searchQuery = ""
    @State private var isLoading = false

    private var filtered: [Exercise] {
        guard !searchQuery.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    private func muscleName(for id: String) -> String {
        muscles.first { $0.id == id }?.name ?? id
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(colors.muted)
                        TextField("Search exercises...", text: $searchQuery)
                            .font(.system(size: 15))
                            .foregroundStyle(colors.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding()

                    if isLoading {
                        Spacer()
                        ProgressView().tint(colors.accent)
                        Spacer()
                    } else {
                        List(filtered) { exercise in
                            Button {
                                dismiss()
                                onAdd(exercise)
                            } label: {
                                ExerciseRow(
                                    exercise: exercise,
                                    muscleName: muscleName(for: exercise.primaryMuscleId)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.surface)
                            .listRowInsets(EdgeInsets())
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
            .task {
                isLoading = true
                async let m = ExerciseService.listMuscleGroups()
                async let e = ExerciseService.listExercises()
                muscles = (try? await m) ?? []
                exercises = (try? await e) ?? []
                isLoading = false
            }
        }
    }
}

// MARK: - PlanExerciseConfigSheet
// Inline sheet for editing sets/reps/weight targets on a single plan exercise.

struct PlanExerciseConfigSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    let planExercise: PlanExercise
    let exercise: Exercise?
    let onSave: (PlanExercise) -> Void

    @State private var targetSets: Int
    @State private var targetRepsMin: Int
    @State private var targetRepsMax: Int
    @State private var hasMaxReps: Bool
    @State private var targetWeight: String

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }

    init(planExercise: PlanExercise, exercise: Exercise?, onSave: @escaping (PlanExercise) -> Void) {
        self.planExercise = planExercise
        self.exercise = exercise
        self.onSave = onSave
        _targetSets = State(initialValue: planExercise.targetSets > 0 ? planExercise.targetSets : 3)
        _targetRepsMin = State(initialValue: planExercise.targetRepsMin ?? 8)
        let maxVal = planExercise.targetRepsMax ?? 12
        let minVal = planExercise.targetRepsMin ?? 8
        _targetRepsMax = State(initialValue: maxVal)
        _hasMaxReps = State(initialValue: maxVal != minVal)
        _targetWeight = State(initialValue: planExercise.targetWeight.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Exercise header with image
                        exerciseHeader

                        // Unified config card
                        VStack(spacing: 0) {
                            // Sets row
                            configRow(icon: "square.stack.fill", title: "Sets", color: colors.accent) {
                                HStack(spacing: 2) {
                                    Text("\(targetSets)")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(colors.text)
                                        .frame(minWidth: 28)

                                    stepperButtons(value: $targetSets, range: 1...20)
                                }
                            }

                            Divider().background(colors.border).padding(.horizontal, 16)

                            // Reps row
                            configRow(icon: "arrow.counterclockwise", title: hasMaxReps ? "Rep Range" : "Reps", color: .orange) {
                                if hasMaxReps {
                                    HStack(spacing: 4) {
                                        miniStepperField(value: $targetRepsMin, range: 1...100)
                                        Text("-")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(colors.muted)
                                        miniStepperField(value: $targetRepsMax, range: 1...100)
                                    }
                                } else {
                                    HStack(spacing: 2) {
                                        Text("\(targetRepsMin)")
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundStyle(colors.text)
                                            .frame(minWidth: 28)

                                        stepperButtons(value: $targetRepsMin, range: 1...100)
                                    }
                                }
                            }

                            // Rep range toggle
                            HStack {
                                Text("Rep range")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.muted)
                                Spacer()
                                Toggle("", isOn: $hasMaxReps)
                                    .labelsHidden()
                                    .tint(colors.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().background(colors.border).padding(.horizontal, 16)

                            // Target weight row
                            configRow(icon: "scalemass.fill", title: "Weight", color: .green) {
                                HStack(spacing: 6) {
                                    TextField("--", text: $targetWeight)
                                        .keyboardType(.decimalPad)
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(colors.text)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 60)

                                    Text(weightUnit)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(colors.muted)
                                }
                            }
                        }
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(colors.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(exercise?.name ?? "Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(colors.accent)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .onChange(of: hasMaxReps) { _, enabled in
                if !enabled {
                    targetRepsMax = targetRepsMin
                }
            }
        }
    }

    // MARK: - Exercise header

    private var exerciseHeader: some View {
        VStack(spacing: 12) {
            if let urlStr = exercise?.imageUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colors.surface2)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(colors.border, lineWidth: 1)
                )
            }

            VStack(spacing: 6) {
                Text(exercise?.name ?? "Exercise")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Live summary preview
                HStack(spacing: 6) {
                    Text("\(targetSets) sets")
                    Text("·")
                    Text(hasMaxReps ? "\(targetRepsMin)-\(targetRepsMax) reps" : "\(targetRepsMin) reps")
                    if let w = Double(targetWeight), w > 0 {
                        Text("·")
                        Text("\(targetWeight) \(weightUnit)")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Config row

    @ViewBuilder
    private func configRow<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
            }

            Spacer()

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Stepper buttons

    @ViewBuilder
    private func stepperButtons(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 0) {
            Button {
                if value.wrappedValue > range.lowerBound {
                    value.wrappedValue -= 1
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue <= range.lowerBound ? colors.muted.opacity(0.3) : colors.text)
                    .frame(width: 36, height: 36)
            }
            .disabled(value.wrappedValue <= range.lowerBound)

            Divider()
                .frame(height: 18)
                .background(colors.border)

            Button {
                if value.wrappedValue < range.upperBound {
                    value.wrappedValue += 1
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue >= range.upperBound ? colors.muted.opacity(0.3) : colors.text)
                    .frame(width: 36, height: 36)
            }
            .disabled(value.wrappedValue >= range.upperBound)
        }
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Mini stepper field (for rep range)

    @ViewBuilder
    private func miniStepperField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Text("\(value.wrappedValue)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
                .frame(minWidth: 24)

            stepperButtons(value: value, range: range)
        }
    }

    // MARK: - Save

    private func save() {
        var updated = planExercise
        updated.targetSets = targetSets
        updated.targetRepsMin = targetRepsMin
        updated.targetRepsMax = hasMaxReps ? targetRepsMax : targetRepsMin
        updated.targetWeight = Double(targetWeight)
        dismiss()
        onSave(updated)
    }
}
