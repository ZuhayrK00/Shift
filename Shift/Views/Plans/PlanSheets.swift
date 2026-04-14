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
                    VStack(spacing: 20) {
                        // Exercise header with image
                        exerciseHeader

                        // Sets
                        configSection(icon: "square.stack.fill", title: "Sets", color: colors.accent) {
                            stepperRow(value: $targetSets, range: 1...20, label: "\(targetSets)", suffix: targetSets == 1 ? "set" : "sets")
                        }

                        // Reps
                        configSection(icon: "arrow.counterclockwise", title: "Reps", color: .orange) {
                            VStack(spacing: 0) {
                                stepperRow(value: $targetRepsMin, range: 1...100, label: hasMaxReps ? "Min" : "Reps", displayValue: "\(targetRepsMin)")

                                if hasMaxReps {
                                    Divider()
                                        .background(colors.border)
                                        .padding(.horizontal, 16)

                                    stepperRow(value: $targetRepsMax, range: 1...100, label: "Max", displayValue: "\(targetRepsMax)")
                                }
                            }

                            // Max toggle
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
                            .padding(.vertical, 10)
                            .background(colors.surface.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Target Weight
                        configSection(icon: "scalemass.fill", title: "Target Weight", color: .green) {
                            HStack(spacing: 12) {
                                TextField("e.g. 60", text: $targetWeight)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(colors.text)

                                Text(weightUnit)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(colors.muted)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colors.border, lineWidth: 1)
                            )
                        }

                        Spacer()
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
        HStack(spacing: 14) {
            if let urlStr = exercise?.imageUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colors.surface2)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colors.border, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise?.name ?? "Exercise")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(colors.text)
                    .lineLimit(2)

                // Summary preview
                HStack(spacing: 8) {
                    Text("\(targetSets) sets")
                    Text("·")
                    Text(hasMaxReps ? "\(targetRepsMin)-\(targetRepsMax) reps" : "\(targetRepsMin) reps")
                    if let w = Double(targetWeight), w > 0 {
                        Text("·")
                        Text("\(targetWeight) \(weightUnit)")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.muted)
            }

            Spacer()
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func configSection<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.muted)
                    .kerning(0.5)
            }

            content()
        }
    }

    // MARK: - Stepper row

    @ViewBuilder
    private func stepperRow(value: Binding<Int>, range: ClosedRange<Int>, label: String, suffix: String? = nil, displayValue: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(colors.muted)

            Spacer()

            Text(displayValue ?? "\(value.wrappedValue)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
                .frame(minWidth: 32)

            if let suffix {
                Text(suffix)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
            }

            HStack(spacing: 0) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(value.wrappedValue <= range.lowerBound ? colors.muted.opacity(0.3) : colors.text)
                        .frame(width: 40, height: 40)
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Divider()
                    .frame(height: 20)
                    .background(colors.border)

                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(value.wrappedValue >= range.upperBound ? colors.muted.opacity(0.3) : colors.text)
                        .frame(width: 40, height: 40)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
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
