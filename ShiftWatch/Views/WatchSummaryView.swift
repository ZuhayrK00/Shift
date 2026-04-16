import SwiftUI
import WatchKit

struct WatchSummaryView: View {
    @Environment(WatchWorkoutState.self) private var workout

    // Capture stats on appear so they survive workout.clear()
    @State private var savedDuration = ""
    @State private var savedExerciseCount = 0
    @State private var savedSetCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Check
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(WatchColors.success)

                Text("Workout Complete")
                    .font(.system(size: 16, weight: .bold))

                // Stats
                HStack(spacing: 20) {
                    statItem(value: savedDuration, label: "Duration")
                    statItem(value: "\(savedExerciseCount)", label: "Exercises")
                    statItem(value: "\(savedSetCount)", label: "Sets")
                }

                Button {
                    WKInterfaceDevice.current().play(.success)
                    workout.clear()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchColors.accent)
            }
            .padding(.horizontal, 4)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            savedDuration = computeDuration()
            savedExerciseCount = workout.exercises.count
            savedSetCount = workout.localSetCounts.values.reduce(0, +)
        }
    }

    private func computeDuration() -> String {
        guard let start = workout.startedAt else { return "0 min" }
        let mins = Int(Date().timeIntervalSince(start)) / 60
        if mins < 1 { return "<1 min" }
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(mins) min"
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
