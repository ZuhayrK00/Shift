import SwiftUI

struct WatchWorkoutView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout

    @State private var showFinishAlert = false
    @State private var isFinishing = false
    @State private var showSummary = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Exercise list
                if workout.exercises.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Add exercises on your iPhone")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(groupedExercises, id: \.id) { group in
                        if group.exercises.count > 1 {
                            // Superset / tri-set / giant set
                            supersetBlock(group.exercises)
                        } else if let exercise = group.exercises.first {
                            NavigationLink {
                                WatchExerciseLogView(exercise: exercise)
                            } label: {
                                exerciseRow(exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Finish
                Button {
                    showFinishAlert = true
                } label: {
                    Text("Finish")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchColors.success)
                .disabled(isFinishing)
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(workout.sessionName)
        .alert("Finish workout?", isPresented: $showFinishAlert) {
            Button("Finish", role: .destructive) { finishWorkout() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: $showSummary) {
            WatchSummaryView()
        }
        .onChange(of: session.context?.activeSession?.exercises) { _, newExercises in
            if let exercises = newExercises {
                let active = WatchActiveSession(
                    sessionId: workout.sessionId ?? "",
                    name: workout.sessionName,
                    startedAt: workout.startedAt ?? Date(),
                    exercises: exercises
                )
                workout.syncExercises(from: active)
            }
        }
    }

    // MARK: - Grouped exercises

    private struct ExerciseGroup: Identifiable {
        var id: String
        var exercises: [WatchSessionExercise]
    }

    private var groupedExercises: [ExerciseGroup] {
        var result: [ExerciseGroup] = []
        var currentGroupId: String?
        var buffer: [WatchSessionExercise] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            let id = buffer.map { $0.exerciseId }.joined(separator: "+")
            result.append(ExerciseGroup(id: id, exercises: buffer))
        }

        for exercise in workout.exercises {
            if let gid = exercise.groupId {
                if gid == currentGroupId {
                    buffer.append(exercise)
                } else {
                    flush()
                    currentGroupId = gid
                    buffer = [exercise]
                }
            } else {
                flush()
                currentGroupId = nil
                buffer = []
                result.append(ExerciseGroup(id: exercise.exerciseId, exercises: [exercise]))
            }
        }
        flush()
        return result
    }

    private var groupLabel: (Int) -> String = { count in
        switch count {
        case 2: return "Superset"
        case 3: return "Tri-set"
        default: return "Giant set"
        }
    }

    private func supersetBlock(_ exercises: [WatchSessionExercise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            HStack(spacing: 4) {
                Rectangle()
                    .fill(.orange)
                    .frame(width: 3, height: 14)
                    .clipShape(Capsule())
                Text(groupLabel(exercises.count).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .tracking(0.5)
            }
            .padding(.bottom, 4)

            VStack(spacing: 4) {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        WatchExerciseLogView(exercise: exercise)
                    } label: {
                        exerciseRow(exercise)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.orange.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Exercise row

    private func exerciseRow(_ exercise: WatchSessionExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                // Show last logged set detail
                if let sets = workout.loggedSetDetails[exercise.exerciseId], let last = sets.last {
                    let weightStr = last.weight.map { formatWeight($0) } ?? "BW"
                    Text("\(weightStr) \u{00d7} \(last.reps)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let equip = exercise.equipment {
                    Text(equip)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Set count badge — only show target when from a plan
            let completed = workout.localSetCounts[exercise.exerciseId] ?? exercise.completedSets
            let total = exercise.totalSets
            let hasPlan = workout.planId != nil
            if hasPlan && total > 0 {
                Text("\(completed)/\(total)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(completed >= total ? WatchColors.success : .primary)
            } else if completed > 0 {
                Text("\(completed)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchColors.success)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func finishWorkout() {
        guard let sid = workout.sessionId else { return }
        isFinishing = true
        session.finishSession(sessionId: sid) { _ in
            Task { @MainActor in
                isFinishing = false
                showSummary = true
            }
        }
    }

    private func formatWeight(_ w: Double) -> String {
        if w.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(w))"
        }
        return String(format: "%.1f", w)
    }
}
