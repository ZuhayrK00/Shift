import SwiftUI
import WidgetKit

// MARK: - Entry

struct StepCounterEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int?
    let isPro: Bool
}

// MARK: - Provider

struct StepCounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepCounterEntry {
        StepCounterEntry(date: .now, steps: 6420, goal: 10000, isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StepCounterEntry) -> Void) {
        let s = WidgetSnapshot.read() ?? .placeholder
        completion(StepCounterEntry(date: .now, steps: s.stepsToday, goal: s.stepGoal, isPro: WidgetSnapshot.isProUser))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepCounterEntry>) -> Void) {
        let s = WidgetSnapshot.read() ?? .placeholder
        let entry = StepCounterEntry(date: .now, steps: s.stepsToday, goal: s.stepGoal, isPro: WidgetSnapshot.isProUser)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - View

struct StepCounterWidgetView: View {
    let entry: StepCounterEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        guard let goal = entry.goal, goal > 0 else { return 0 }
        return min(Double(entry.steps) / Double(goal), 1.0)
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumLayout
            default: smallLayout
            }
        }
        .proLocked(entry.isPro)
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(spacing: 8) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)

            if let goal = entry.goal, goal > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(formatSteps(entry.steps))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.5)
                        Text("of \(formatSteps(goal))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 76, height: 76)

                if progress >= 1.0 {
                    Text("Goal hit!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(formatSteps(goal - entry.steps)) to go")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(formatSteps(entry.steps))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                Text("steps")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 20) {
            if let goal = entry.goal, goal > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 80, height: 80)
            } else {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Steps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(formatSteps(entry.steps))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)

                if let goal = entry.goal, goal > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                                .frame(height: 5)
                            Capsule()
                                .fill(Color.green)
                                .frame(width: geo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)

                    if progress >= 1.0 {
                        Text("Goal complete!")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(formatSteps(entry.steps)) of \(formatSteps(goal))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Helpers

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 10000 {
            let k = Double(steps) / 1000.0
            return String(format: "%.1fk", k)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

// MARK: - Widget

struct StepCounterWidget: Widget {
    let kind = "StepCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepCounterProvider()) { entry in
            StepCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Step Counter")
        .description("Track your daily steps and goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
