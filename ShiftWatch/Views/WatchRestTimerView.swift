import SwiftUI
import WatchKit

struct WatchRestTimerView: View {
    let duration: Int

    @Environment(\.dismiss) private var dismiss

    @State private var remaining: Int = 0
    @State private var timer: Timer?
    @State private var endTime: Date?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(remaining) / Double(duration)
    }

    private var timeText: String {
        let mins = remaining / 60
        let secs = remaining % 60
        return mins > 0
            ? String(format: "%d:%02d", mins, secs)
            : "\(secs)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WatchColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)

                VStack(spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("rest")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            Spacer()

            Button {
                cleanup()
                dismiss()
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { start() }
        .onDisappear { cleanup() }
    }

    private func start() {
        remaining = duration
        endTime = Date().addingTimeInterval(Double(duration))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let endTime else { return }
                let diff = Int(ceil(endTime.timeIntervalSinceNow))
                remaining = max(0, diff)

                if remaining <= 0 {
                    WKInterfaceDevice.current().play(.notification)
                    cleanup()
                    dismiss()
                }
            }
        }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
    }
}
