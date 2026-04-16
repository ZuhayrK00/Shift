import SwiftUI
import WidgetKit

// MARK: - Step Complication

struct StepComplicationEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int?
}

struct StepComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepComplicationEntry {
        StepComplicationEntry(date: .now, steps: 6420, goal: 10000)
    }

    func getSnapshot(in context: Context, completion: @escaping (StepComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepComplicationEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(nextUpdate)))
    }

    private func entry() -> StepComplicationEntry {
        let snap = WidgetSnapshot.read()
        return StepComplicationEntry(
            date: .now,
            steps: snap?.stepsToday ?? 0,
            goal: snap?.stepGoal
        )
    }
}

struct StepComplicationView: View {
    let entry: StepComplicationEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        guard let goal = entry.goal, goal > 0 else { return 0 }
        return min(Double(entry.steps) / Double(goal), 1.0)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryInline: inlineView
        case .accessoryCorner: cornerView
        case .accessoryRectangular: rectangularView
        default: circularView
        }
    }

    private var circularView: some View {
        ZStack {
            if entry.goal != nil {
                Gauge(value: progress) {
                    Image(systemName: "shoeprints.fill")
                } currentValueLabel: {
                    Text(formatCompact(entry.steps))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.green)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 10))
                    Text(formatCompact(entry.steps))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "shoeprints.fill")
            if let goal = entry.goal, goal > 0 {
                Text("\(formatCompact(entry.steps))/\(formatCompact(goal)) steps")
            } else {
                Text("\(formatCompact(entry.steps)) steps")
            }
        }
    }

    private var cornerView: some View {
        ZStack {
            if let goal = entry.goal, goal > 0 {
                Gauge(value: progress) {
                    Text(formatCompact(entry.steps))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.green)
            } else {
                Text(formatCompact(entry.steps))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("Steps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let goal = entry.goal, goal > 0 {
                HStack(spacing: 6) {
                    Text(formatCompact(entry.steps))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("/ \(formatCompact(goal))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.green)
            } else {
                HStack(spacing: 6) {
                    Text(formatCompact(entry.steps))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("steps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 10000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct StepComplication: Widget {
    let kind = "StepComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepComplicationProvider()) { entry in
            StepComplicationView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Today's step count.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner, .accessoryRectangular])
    }
}
