import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout

    @State private var showPlanList = false
    @State private var isStarting = false
    @State private var navigateToWorkout = false

    private var ctx: WatchContext? { session.context }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Today summary card
                    todaySummary

                    // Resume active workout
                    if let active = ctx?.activeSession, !workout.isActive {
                        Button {
                            workout.start(
                                sessionId: active.sessionId,
                                name: active.name,
                                startedAt: active.startedAt,
                                exercises: active.exercises
                            )
                            navigateToWorkout = true
                        } label: {
                            Label("Resume Workout", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    // Start blank workout
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
                        Label(isStarting ? "Starting..." : "Start Workout", systemImage: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColors.accent)
                    .disabled(isStarting)

                    // From plan
                    if let plans = ctx?.plans, !plans.isEmpty {
                        Button {
                            showPlanList = true
                        } label: {
                            Label("From Plan", systemImage: "doc.text")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Shift")
            .navigationDestination(isPresented: $navigateToWorkout) {
                WatchWorkoutView()
            }
            .navigationDestination(isPresented: $showPlanList) {
                WatchPlanListView(onStarted: { navigateToWorkout = true })
            }
        }
    }

    // MARK: - Today summary

    private var todaySummary: some View {
        VStack(spacing: 8) {
            if let snap = ctx?.snapshot {
                HStack(spacing: 16) {
                    // Steps
                    VStack(spacing: 2) {
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(formatSteps(snap.stepsToday))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        if let goal = snap.stepGoal, goal > 0 {
                            Text("/ \(formatSteps(goal))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Workouts
                    VStack(spacing: 2) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        if let goal = snap.weeklyGoal, goal > 0 {
                            Text("\(snap.workoutsThisWeek)/\(goal)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        } else {
                            Text("\(snap.workoutsThisWeek)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        Text("this week")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    // Streak
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(snap.currentStreak > 0 ? .orange : .gray)
                        Text("\(snap.currentStreak)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("streak")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } else {
                Text("Open Shift on iPhone to sync")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            }
        }
    }

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 10000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}
