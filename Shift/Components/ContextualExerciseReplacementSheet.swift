import SwiftUI

struct ContextualExerciseReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors

    let current: Exercise
    let excluding: Set<String>
    let onSelect: (Exercise) -> Void

    @State private var catalogue: [Exercise] = []
    @State private var query = ""
    @State private var isLoading = true

    private var suggestions: [ExerciseSubstitution] {
        ExerciseSubstitutionService.rankedSuggestions(
            for: current,
            from: catalogue,
            excluding: excluding,
            limit: 8
        )
    }

    private var searchResults: [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return catalogue
            .filter { exercise in
                exercise.id != current.id
                    && !excluding.contains(exercise.id)
                    && (
                        exercise.name.localizedCaseInsensitiveContains(trimmed)
                            || (exercise.equipment?.localizedCaseInsensitiveContains(trimmed) ?? false)
                            || exercise.primaryMuscleId.localizedCaseInsensitiveContains(trimmed)
                    )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List {
                        if query.isEmpty {
                            Section {
                                ForEach(suggestions) { suggestion in
                                    replacementButton(
                                        suggestion.exercise,
                                        reason: suggestion.explanation
                                    )
                                }
                            } header: {
                                Text("Best matches")
                            } footer: {
                                Text("Matches consider target muscle, movement, equipment and difficulty.")
                            }
                        } else {
                            Section("All exercises") {
                                ForEach(searchResults) { exercise in
                                    replacementButton(
                                        exercise,
                                        reason: exercise.equipment?.capitalized ?? "No equipment"
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if query.isEmpty && suggestions.isEmpty {
                            ContentUnavailableView(
                                "No close matches",
                                systemImage: "arrow.triangle.2.circlepath",
                                description: Text("Search the exercise catalogue instead.")
                            )
                        } else if !query.isEmpty && searchResults.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
            }
            .background(colors.bg)
            .navigationTitle("Replace \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search all exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                catalogue = (try? await ExerciseService.listExercises()) ?? []
                isLoading = false
            }
        }
    }

    private func replacementButton(_ exercise: Exercise, reason: String) -> some View {
        Button {
            onSelect(exercise)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
            .padding(.vertical, 3)
        }
        .listRowBackground(colors.surface)
    }
}
