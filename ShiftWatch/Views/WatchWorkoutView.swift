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
                    ForEach(workout.exercises) { exercise in
                        NavigationLink {
                            WatchExerciseLogView(exercise: exercise)
                        } label: {
                            exerciseRow(exercise)
                        }
                        .buttonStyle(.plain)
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

            // Set count badge
            let completed = workout.localSetCounts[exercise.exerciseId] ?? exercise.completedSets
            let total = exercise.totalSets
            Text("\(completed)/\(total)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(completed >= total && total > 0 ? WatchColors.success : .primary)
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
