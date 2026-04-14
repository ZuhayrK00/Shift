import SwiftUI

/// Compact rest timer banner that reads from the shared RestTimerManager.
/// Unlike RestTimerView, this never starts the timer — it only displays
/// the countdown when one is already running.
struct CompactRestTimerView: View {
    @Environment(\.shiftColors) private var colors

    private var timer: RestTimerManager { .shared }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(timer.progress < 0.2 ? colors.warning : colors.accent)

            Text("REST")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.muted)
                .tracking(0.8)

            Text(timer.timeText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
                .monospacedDigit()
                .contentTransition(.numericText())

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colors.surface2)
                        .frame(height: 4)
                    Capsule()
                        .fill(timer.progress < 0.2 ? colors.warning : colors.accent)
                        .frame(width: geo.size.width * timer.progress, height: 4)
                        .animation(.linear(duration: 0.5), value: timer.progress)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)

            Button {
                timer.stop()
            } label: {
                Text("Skip")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(colors.surface2)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
    }
}
