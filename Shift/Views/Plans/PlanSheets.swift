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

    let planExercise: PlanExercise
    let exercise: Exercise?
    let onSave: (PlanExercise) -> Void

    @State private var targetSets: Int
    @State private var targetRepsMin: Int
    @State private var targetRepsMax: Int
    @State private var targetWeight: String

    init(planExercise: PlanExercise, exercise: Exercise?, onSave: @escaping (PlanExercise) -> Void) {
        self.planExercise = planExercise
        self.exercise = exercise
        self.onSave = onSave
        _targetSets = State(initialValue: planExercise.targetSets > 0 ? planExercise.targetSets : 3)
        _targetRepsMin = State(initialValue: planExercise.targetRepsMin ?? 8)
        _targetRepsMax = State(initialValue: planExercise.targetRepsMax ?? 12)
        _targetWeight = State(initialValue: planExercise.targetWeight.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    Section("Sets") {
                        Stepper("\(targetSets) sets", value: $targetSets, in: 1...20)
                            .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    Section("Reps") {
                        Stepper("Min: \(targetRepsMin)", value: $targetRepsMin, in: 1...100)
                            .foregroundStyle(colors.text)
                        Stepper("Max: \(targetRepsMax)", value: $targetRepsMax, in: 1...100)
                            .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    Section("Target Weight") {
                        TextField("e.g. 60", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)
                }
                .scrollContentBackground(.hidden)
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
        }
    }

    private func save() {
        var updated = planExercise
        updated.targetSets = targetSets
        updated.targetRepsMin = targetRepsMin
        updated.targetRepsMax = targetRepsMax
        updated.targetWeight = Double(targetWeight)
        dismiss()
        onSave(updated)
    }
}
