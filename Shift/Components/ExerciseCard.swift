import SwiftUI

// MARK: - ExerciseCard

/// Card showing one exercise block inside the active workout overview.
struct ExerciseCard: View {
    let exercise: Exercise
    let sets: [SessionSet]
    var planExercise: PlanExercise?
    var weightUnit: String = "kg"
    var note: String? = nil
    var readOnly: Bool = false
    var onRemove: () -> Void = {}
    var onChangeSetType: (SessionSet, SetType) -> Void = { _, _ in }

    @Environment(\.shiftColors) private var colors

    // MARK: - Subtitle

    private var subtitle: String {
        let completed = sets.filter { $0.isCompleted }
        if completed.isEmpty {
            if let plan = planExercise {
                return plan.subtitle()
            }
            return "Tap to start"
        }
        let setCount = pluralise(completed.count, "set")
        if let w = completed.last?.weight {
            let reps = pluralise(completed.last?.reps ?? 0, "rep")
            return "\(setCount) × \(formatWeight(w, unit: weightUnit)) × \(reps)"
        }
        return setCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top) {
                // Exercise thumbnail
                exerciseThumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colors.text)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.muted)
                        .textCase(.uppercase)
                        .tracking(0.3)
                }

                Spacer()

                // Remove button (hidden in read-only mode)
                if !readOnly {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Set rows — only show completed sets
            let completedSets = sets.filter { $0.isCompleted }
            if !completedSets.isEmpty {
                Divider()
                    .background(colors.border)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(completedSets) { set in
                        setRow(set)
                    }
                }
            }

            // Exercise note
            if let note, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                        .lineLimit(3)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }

            Spacer().frame(height: 12)
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Set row

    @ViewBuilder
    private func setRow(_ set: SessionSet) -> some View {
        HStack(spacing: 10) {
            if readOnly {
                SetBadge(set: set, compact: true)
            } else {
                SetTypeMenuButton(set: set) { newType in
                    onChangeSetType(set, newType)
                }
            }

            // Weight + reps
            let weightText: String = {
                if let w = set.weight {
                    return formatWeight(w, unit: weightUnit)
                }
                return "—"
            }()
            Text(weightText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)

            Text("×")
                .font(.system(size: 12))
                .foregroundStyle(colors.muted)

            Text(pluralise(set.reps, "rep"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var exerciseThumbnail: some View {
        Group {
            if let url = exercise.imageUrl.flatMap(URL.init) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderThumbnail: some View {
        ZStack {
            colors.surface2
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18))
                .foregroundStyle(colors.muted)
        }
    }
}

// MARK: - Preview

#Preview {
    let ex = Exercise(
        id: "1", name: "Bench Press", slug: "bench-press",
        primaryMuscleId: "chest", secondaryMuscleIds: [],
        isBuiltIn: true
    )
    let sets: [SessionSet] = [
        SessionSet(id: "s1", sessionId: "sess", exerciseId: "1",
                   setNumber: 1, reps: 8, weight: 80, isCompleted: true),
        SessionSet(id: "s2", sessionId: "sess", exerciseId: "1",
                   setNumber: 2, reps: 8, weight: 80, isCompleted: true, setType: .warmup),
    ]

    ExerciseCard(exercise: ex, sets: sets)
        .padding()
        .background(Color(hex: "#0b0b0f"))
        .shiftTheme()
}
