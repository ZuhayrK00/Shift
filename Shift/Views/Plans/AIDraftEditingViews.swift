import SwiftUI

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
struct AIDraftTargetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors

    let exercise: GeneratedExercise
    let onSave: (GeneratedExercise) -> Void

    @State private var sets: Int
    @State private var repsMin: Int
    @State private var repsMax: Int
    @State private var rest: Int

    init(exercise: GeneratedExercise, onSave: @escaping (GeneratedExercise) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _sets = State(initialValue: exercise.sets)
        _repsMin = State(initialValue: exercise.repsMin)
        _repsMax = State(initialValue: exercise.repsMax)
        _rest = State(initialValue: exercise.restSeconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(exercise.exerciseName) {
                    Stepper("Sets: \(sets)", value: $sets, in: 2...5)
                    Stepper("Minimum reps: \(repsMin)", value: $repsMin, in: 1...30)
                    Stepper("Maximum reps: \(repsMax)", value: $repsMax, in: repsMin...30)
                    Stepper("Rest: \(rest) seconds", value: $rest, in: 30...300, step: 15)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Edit Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = exercise
                        updated.sets = sets
                        updated.repsMin = repsMin
                        updated.repsMax = max(repsMin, repsMax)
                        updated.restSeconds = rest
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

@available(iOS 26, *)
struct AIExerciseReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors

    let current: Exercise
    let suggestions: [Exercise]
    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No Close Matches",
                        systemImage: "dumbbell",
                        description: Text("Try changing your equipment or muscle preferences.")
                    )
                } else {
                    List(suggestions) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(colors.text)
                                Text(exercise.equipment?.capitalized ?? "No equipment")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.muted)
                            }
                        }
                        .listRowBackground(colors.surface)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Replace \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
#endif
