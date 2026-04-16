import SwiftUI

struct WatchWorkoutView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout
    @Environment(\.dismiss) private var dismiss

    @State private var showAddExercise = false
    @State private var showFinishAlert = false
    @State private var isFinishing = false
    @State private var showSummary = false
    @State private var elapsedTimer: Timer?
    @State private var elapsed: String = "0:00"

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Timer
                Text(elapsed)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Exercise list
                if workout.exercises.isEmpty {
                    Text("No exercises yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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

                // Add exercise
                if let recent = session.context?.recentExercises, !recent.isEmpty {
                    Button {
                        showAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
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
        .navigationBarBackButtonHidden(true)
        .alert("Finish workout?", isPresented: $showFinishAlert) {
            Button("Finish", role: .destructive) { finishWorkout() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddExercise) {
            addExerciseSheet
        }
        .navigationDestination(isPresented: $showSummary) {
            WatchSummaryView(onDone: {
                dismiss()
            })
        }
        .onAppear { startTimer() }
        .onDisappear { elapsedTimer?.invalidate() }
    }

    // MARK: - Exercise row

    private func exerciseRow(_ exercise: WatchSessionExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let equip = exercise.equipment {
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

    // MARK: - Add exercise sheet

    private var addExerciseSheet: some View {
        NavigationStack {
            List {
                if let recent = session.context?.recentExercises {
                    ForEach(recent) { exercise in
                        Button {
                            guard let sid = workout.sessionId else { return }
                            session.addExercise(sessionId: sid, exerciseId: exercise.id) { success in
                                if success {
                                    Task { @MainActor in
                                        workout.addExercise(WatchSessionExercise(
                                            exerciseId: exercise.id,
                                            exerciseName: exercise.name,
                                            equipment: exercise.equipment,
                                            completedSets: 0,
                                            totalSets: 1
                                        ))
                                        showAddExercise = false
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.system(size: 14, weight: .medium))
                                if let equip = exercise.equipment {
                                    Text(equip)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
        }
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

    private func startTimer() {
        elapsed = workout.elapsedText
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsed = workout.elapsedText
            }
        }
    }
}
