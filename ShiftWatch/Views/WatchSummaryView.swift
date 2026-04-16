import SwiftUI
import WatchKit

struct WatchSummaryView: View {
    @Environment(WatchWorkoutState.self) private var workout

    var onDone: () -> Void

    private var duration: String {
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

    private var totalSets: Int {
        workout.localSetCounts.values.reduce(0, +)
    }

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
                    statItem(value: duration, label: "Duration")
                    statItem(value: "\(workout.exercises.count)", label: "Exercises")
                    statItem(value: "\(totalSets)", label: "Sets")
                }

                Button {
                    WKInterfaceDevice.current().play(.success)
                    workout.clear()
                    onDone()
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
