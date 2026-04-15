// Dynamic Island and Lock Screen views for the Shift rest timer.
//
// The countdown text uses Text(timerInterval:) which iOS ticks automatically
// so we never need to push content updates just to keep the number moving.
// The progress arc is a static snapshot of the fraction remaining at the
// moment the activity was started or last updated.

import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // ── Lock Screen / Notification Banner ────────────────────────────
            LockScreenBanner(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (user presses the Dynamic Island) ───────────────
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SHIFT")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Rest")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: .now...context.state.endTime, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 80, alignment: .trailing)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressBar(state: context.state)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
            } compactLeading: {
                // ── Compact (pill when another app is foreground) ────────────
                Image(systemName: "dumbbell.fill")
                    .imageScale(.small)
                    .foregroundStyle(Color.purple)
            } compactTrailing: {
                Text(timerInterval: .now...context.state.endTime, countsDown: true)
                    .monospacedDigit()
                    .foregroundStyle(Color.purple)
                    .frame(width: 35)
            } minimal: {
                // ── Minimal (tiny dot when two activities compete) ───────────
                Image(systemName: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.purple)
            }
        }
    }
}

// MARK: - Lock Screen Banner

struct LockScreenBanner: View {
    let state: RestTimerAttributes.TimerState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: 50, height: 50)
                Image(systemName: "dumbbell.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Shift · Rest Timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timerInterval: .now...state.endTime, countsDown: true)
                    .monospacedDigit()
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Arc snapshot
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: arcProgress)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var arcProgress: CGFloat {
        let remaining = max(0, state.endTime.timeIntervalSinceNow)
        let total = Double(state.totalSeconds)
        guard total > 0 else { return 0 }
        return CGFloat(remaining / total)
    }
}

// MARK: - Progress bar (expanded bottom region)

struct ProgressBar: View {
    let state: RestTimerAttributes.TimerState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.purple)
                    .frame(width: geo.size.width * fraction, height: 4)
            }
        }
        .frame(height: 4)
    }

    private var fraction: CGFloat {
        let remaining = max(0, state.endTime.timeIntervalSinceNow)
        let total = Double(state.totalSeconds)
        guard total > 0 else { return 0 }
        return CGFloat(remaining / total)
    }
}
