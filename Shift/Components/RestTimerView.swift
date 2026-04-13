import SwiftUI

// MARK: - RestTimerView

/// Full-width rest timer banner with linear progress bar and countdown.
/// Uses the shared RestTimerManager so the timer survives navigation.
struct RestTimerView: View {
    let duration: Int
    let onDismiss: () -> Void

    @Environment(\.shiftColors) private var colors

    private var timer: RestTimerManager { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Timer icon
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(timer.progress < 0.2 ? colors.warning : colors.accent)

                // Countdown text
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .tracking(1)
                    Text(timer.timeText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.text)
                        .monospacedDigit()
                }

                Spacer()

                // Skip button
                Button {
                    timer.stop()
                    onDismiss()
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(colors.surface2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Full-width progress bar
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
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
        .onAppear {
            if !timer.isActive {
                timer.start(seconds: duration)
            }
        }
        .onChange(of: timer.isActive) { _, active in
            if !active {
                onDismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RestTimerView(duration: 90) { }
        .padding()
        .background(Color(hex: "#0b0b0f"))
        .shiftTheme()
}
