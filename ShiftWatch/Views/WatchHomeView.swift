import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout

    @State private var navigateToWorkout = false
    @State private var navigateToStart = false

    @State private var showCompletedDetail = false

    private var ctx: WatchContext? { session.context }
    private var workedOutToday: Bool { ctx?.snapshot.workedOutToday ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Continue active workout
                    if workout.isActive {
                        Button {
                            navigateToWorkout = true
                        } label: {
                            Label("Continue Workout", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    // Resume session from phone (watch state cleared but session still active)
                    else if let active = ctx?.activeSession {
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
                    // Show last completed workout today
                    else if workedOutToday, let completed = ctx?.lastCompletedSession {
                        Button {
                            showCompletedDetail = true
                        } label: {
                            lastWorkoutCard(completed)
                        }
                        .buttonStyle(.plain)
                    }
                    // Start workout (only if not already worked out today)
                    else {
                        Button {
                            navigateToStart = true
                        } label: {
                            Label("Start Workout", systemImage: "bolt.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchColors.accent)
                    }

                    // Step counter
                    stepCard

                    // Weekly goal
                    weeklyGoalCard

                    // Streak
                    streakCard
                }
                .padding(.horizontal, 4)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("ShiftLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .navigationDestination(isPresented: $navigateToWorkout) {
                WatchWorkoutView()
            }
            .navigationDestination(isPresented: $navigateToStart) {
                WatchStartWorkoutView(navigateToWorkout: $navigateToWorkout)
            }
            .navigationDestination(isPresented: $showCompletedDetail) {
                if let completed = ctx?.lastCompletedSession {
                    WatchCompletedDetailView(completed: completed)
                }
            }
            .onChange(of: workout.isActive) { _, isActive in
                if !isActive && navigateToWorkout {
                    navigateToWorkout = false
                }
            }
            .onChange(of: session.context?.activeSession) { _, activeSession in
                // Phone finished the workout — clear watch state
                if activeSession == nil && workout.isActive {
                    workout.clear()
                }
            }
        }
    }

    // MARK: - Last workout card

    private func lastWorkoutCard(_ completed: WatchCompletedSession) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(WatchColors.success)
                Text(completed.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 12) {
                let duration = formatDuration(from: completed.startedAt, to: completed.endedAt)
                miniStat(value: duration, label: "Duration")
                miniStat(value: "\(completed.exerciseCount)", label: "Exercises")
                miniStat(value: "\(completed.setCount)", label: "Sets")
            }

            HStack(spacing: 4) {
                Spacer()
                Text("View details")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(from start: Date, to end: Date) -> String {
        let mins = Int(end.timeIntervalSince(start)) / 60
        if mins < 1 { return "<1m" }
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(mins)m"
    }

    // MARK: - Step counter card

    private var stepCard: some View {
        Group {
            if let snap = ctx?.snapshot {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Steps")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatSteps(snap.stepsToday))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        if let goal = snap.stepGoal, goal > 0 {
                            Text("/ \(formatSteps(goal))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if let goal = snap.stepGoal, goal > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.green)
                                    .frame(width: geo.size.width * min(Double(snap.stepsToday) / Double(goal), 1.0), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Weekly goal card

    private var weeklyGoalCard: some View {
        Group {
            if let snap = ctx?.snapshot {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        Text("This Week")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let goal = snap.weeklyGoal, goal > 0 {
                            Text("\(snap.workoutsThisWeek)/\(goal)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("workouts")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(snap.workoutsThisWeek)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("workouts")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if let goal = snap.weeklyGoal, goal > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.purple)
                                    .frame(width: geo.size.width * min(Double(snap.workoutsThisWeek) / Double(goal), 1.0), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Streak card

    private var streakCard: some View {
        Group {
            if let snap = ctx?.snapshot {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(snap.currentStreak > 0 ? .orange : .gray)
                    Text("\(snap.currentStreak)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("day streak")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
