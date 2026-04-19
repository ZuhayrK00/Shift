import SwiftUI
import WidgetKit

// MARK: - Workout Complication

struct WorkoutComplicationEntry: TimelineEntry {
    let date: Date
    let workouts: Int
    let goal: Int?
    let workedOutToday: Bool
}

struct WorkoutComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutComplicationEntry {
        WorkoutComplicationEntry(date: .now, workouts: 3, goal: 5, workedOutToday: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutComplicationEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(nextUpdate)))
    }

    private func entry() -> WorkoutComplicationEntry {
        let snap = WidgetSnapshot.read()
        return WorkoutComplicationEntry(
            date: .now,
            workouts: snap?.workoutsThisWeek ?? 0,
            goal: snap?.weeklyGoal,
            workedOutToday: snap?.workedOutToday ?? false
        )
    }
}

struct WorkoutComplicationView: View {
    let entry: WorkoutComplicationEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        guard let goal = entry.goal, goal > 0 else { return 0 }
        return min(Double(entry.workouts) / Double(goal), 1.0)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryInline: inlineView
        case .accessoryRectangular: rectangularView
        default: circularView
        }
    }

    private var circularView: some View {
        ZStack {
            if entry.goal != nil {
                Gauge(value: progress) {
                    VStack(spacing: 0) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 8))
                        Text("\(entry.workouts)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.purple)
            } else {
                Gauge(value: 0) {
                    VStack(spacing: 0) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 8))
                        Text("\(entry.workouts)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.purple)
            }
        }
    }

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "dumbbell.fill")
            if let goal = entry.goal, goal > 0 {
                Text("\(entry.workouts)/\(goal) workouts")
            } else {
                Text("\(entry.workouts) workout\(entry.workouts == 1 ? "" : "s")")
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
                Text("This Week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let goal = entry.goal, goal > 0 {
                HStack(spacing: 6) {
                    Text("\(entry.workouts)/\(goal)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("workouts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.purple)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(entry.workouts)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(entry.workouts == 1 ? "workout" : "workouts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Gauge(value: 0) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.purple)
            }
        }
    }
}

struct WorkoutComplication: Widget {
    let kind = "WorkoutComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutComplicationProvider()) { entry in
            WorkoutComplicationView(entry: entry)
        }
        .configurationDisplayName("Workouts")
        .description("Weekly workout progress.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
