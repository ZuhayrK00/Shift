import SwiftUI
import WatchKit

struct WatchExerciseLogView: View {
    let exercise: WatchSessionExercise

    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var workout

    @State private var weight: Double = 0
    @State private var reps: Double = 10
    @State private var crownOnWeight = true
    @State private var isLogging = false
    @State private var showRestTimer = false

    private var settings: WatchSettings? { session.context?.settings }
    private var increment: Double { settings?.defaultWeightIncrement ?? 2.5 }
    private var weightUnit: String { settings?.weightUnit ?? "kg" }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Weight control
                valueControl(
                    label: "Weight (\(weightUnit))",
                    value: formatWeight(weight),
                    isActive: crownOnWeight,
                    onTap: { crownOnWeight = true },
                    onMinus: { weight = max(0, weight - increment) },
                    onPlus: { weight += increment }
                )

                // Reps control
                valueControl(
                    label: "Reps",
                    value: "\(Int(reps))",
                    isActive: !crownOnWeight,
                    onTap: { crownOnWeight = false },
                    onMinus: { reps = max(1, reps - 1) },
                    onPlus: { reps += 1 }
                )

                // Log button
                Button {
                    logSet()
                } label: {
                    Text(isLogging ? "Logging..." : "Log Set")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchColors.accent)
                .disabled(isLogging || Int(reps) < 1)

                // Logged sets detail
                if let sets = workout.loggedSetDetails[exercise.exerciseId], !sets.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(sets.enumerated()), id: \.offset) { index, loggedSet in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let weightStr = loggedSet.weight.map { formatWeight($0) } ?? "BW"
                                Text("\(weightStr) \u{00d7} \(loggedSet.reps)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(exercise.exerciseName)
        .focusable()
        .digitalCrownRotation(
            crownOnWeight ? $weight : $reps,
            from: crownOnWeight ? 0 : 1,
            through: crownOnWeight ? 500 : 100,
            by: crownOnWeight ? increment : 1,
            sensitivity: .medium
        )
        .navigationDestination(isPresented: $showRestTimer) {
            WatchRestTimerView(duration: settings?.restTimerDurationSeconds ?? 90)
        }
        .onAppear { seedValues() }
    }

    // MARK: - Value control

    private func valueControl(
        label: String,
        value: String,
        isActive: Bool,
        onTap: @escaping () -> Void,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(minWidth: 60)
                    .onTapGesture(perform: onTap)

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isActive ? WatchColors.accent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Actions

    private func logSet() {
        guard let sid = workout.sessionId, Int(reps) > 0 else { return }
        isLogging = true

        let w = weight > 0 ? weight : nil
        let r = Int(reps)
        session.logSet(sessionId: sid, exerciseId: exercise.exerciseId, reps: r, weight: w) { success in
            Task { @MainActor in
                isLogging = false
                if success {
                    workout.loggedSet(for: exercise.exerciseId, weight: w, reps: r)
                    WKInterfaceDevice.current().play(.success)

                    // Show rest timer if enabled
                    if settings?.restTimerEnabled ?? true {
                        showRestTimer = true
                    }
                }
            }
        }
    }

    private func seedValues() {
        // Seed from last logged set if available
        if let sets = workout.loggedSetDetails[exercise.exerciseId], let last = sets.last {
            if let w = last.weight { weight = w }
            reps = Double(last.reps)
            return
        }

        // Try to use plan target weight/reps if available
        if let plans = session.context?.plans {
            for plan in plans {
                if let pe = plan.exercises.first(where: { $0.exerciseId == exercise.exerciseId }) {
                    if let tw = pe.targetWeight, tw > 0 {
                        weight = tw
                    }
                    if let rMin = pe.targetRepsMin {
                        reps = Double(rMin)
                    }
                    return
                }
            }
        }
    }

    private func formatWeight(_ w: Double) -> String {
        if w == 0 { return "BW" }
        if w.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(w))"
        }
        return String(format: "%.1f", w)
    }
}
