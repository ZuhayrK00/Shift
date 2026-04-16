import SwiftUI

struct WatchPlanListView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout

    var onStarted: () -> Void

    @State private var isStarting: String?

    var body: some View {
        List {
            if let plans = session.context?.plans, !plans.isEmpty {
                ForEach(plans) { plan in
                    Button {
                        guard isStarting == nil else { return }
                        isStarting = plan.id
                        session.startSessionFromPlan(planId: plan.id) { id, name, date in
                            Task { @MainActor in
                                isStarting = nil
                                if let id, let date {
                                    // Build exercise list from plan
                                    let exercises = plan.exercises.map { pe in
                                        WatchSessionExercise(
                                            exerciseId: pe.exerciseId,
                                            exerciseName: pe.exerciseName,
                                            equipment: pe.equipment,
                                            completedSets: 0,
                                            totalSets: pe.targetSets
                                        )
                                    }
                                    workout.start(sessionId: id, name: name ?? plan.name, startedAt: date, exercises: exercises)
                                    onStarted()
                                }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(plan.exercises.count) exercises")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isStarting != nil)
                    .opacity(isStarting == plan.id ? 0.5 : 1)
                }
            } else {
                Text("No plans yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plans")
    }
}
