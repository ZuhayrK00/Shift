import SwiftUI

struct WatchStartWorkoutView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout
    @Binding var navigateToWorkout: Bool

    @State private var isStarting = false
    @State private var showPlanList = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Start from scratch
                Button {
                    guard !isStarting else { return }
                    isStarting = true
                    session.startSession { id, name, date in
                        Task { @MainActor in
                            isStarting = false
                            if let id, let date {
                                workout.start(sessionId: id, name: name ?? "Workout", startedAt: date)
                                navigateToWorkout = true
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text(isStarting ? "Starting..." : "Start from Scratch")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchColors.accent)
                .disabled(isStarting)

                // Select a plan
                if let plans = session.context?.plans, !plans.isEmpty {
                    Button {
                        showPlanList = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 20))
                            Text("Select a Plan")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Start Workout")
        .navigationDestination(isPresented: $showPlanList) {
            WatchPlanListView(onStarted: {
                navigateToWorkout = true
            })
        }
    }
}
