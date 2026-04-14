import SwiftUI

// MARK: - SupersetContainerView
//
// Renders a group of exercise blocks that share a groupId as a labelled
// superset / tri-set / giant-set container with an orange left border.
// Extracted from WorkoutView to keep that file under the 400-line limit.

struct SupersetContainerView: View {
    let blocks: [ExerciseBlock]
    let sessionId: String
    var planExerciseMap: [String: PlanExercise] = [:]
    var weightUnit: String = "kg"
    var readOnly: Bool = false
    var onRemove: (String) -> Void  = { _ in }
    var onChangeSetType: (SessionSet, SetType) -> Void = { _, _ in }

    @Environment(\.shiftColors) private var colors

    private var groupLabel: String {
        switch blocks.count {
        case 2:  return "Superset"
        case 3:  return "Tri-set"
        default: return "Giant set"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label row with accent bar
            HStack(spacing: 6) {
                Rectangle()
                    .fill(colors.warning)
                    .frame(width: 3, height: 18)
                    .clipShape(Capsule())
                Text(groupLabel.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(colors.warning)
                    .tracking(0.5)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            VStack(spacing: 10) {
                ForEach(blocks) { block in
                    if readOnly {
                        ExerciseCard(
                            exercise: block.exercise,
                            sets: block.sets,
                            planExercise: planExerciseMap[block.exercise.id],
                            weightUnit: weightUnit,
                            readOnly: true,
                            onRemove: {},
                            onChangeSetType: { _, _ in }
                        )
                    } else {
                        NavigationLink(value: ExerciseLogRoute(
                            sessionId: sessionId,
                            exerciseId: block.exercise.id
                        )) {
                            ExerciseCard(
                                exercise: block.exercise,
                                sets: block.sets,
                                planExercise: planExerciseMap[block.exercise.id],
                                weightUnit: weightUnit,
                                onRemove: { onRemove(block.exercise.id) },
                                onChangeSetType: { set, type in onChangeSetType(set, type) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(colors.warning.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
    }
}
