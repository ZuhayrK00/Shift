import SwiftUI
import WidgetKit

// MARK: - Entry

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let goal: Int?
    let isPro: Bool
}

// MARK: - Provider

struct WeeklyProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyProgressEntry {
        WeeklyProgressEntry(date: .now, completed: 3, goal: 5, isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let entry = entry(from: WidgetSnapshot.read())
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> WeeklyProgressEntry {
        let s = snapshot ?? .placeholder
        return WeeklyProgressEntry(
            date: .now,
            completed: s.workoutsThisWeek,
            goal: s.weeklyGoal,
            isPro: WidgetSnapshot.isProUser
        )
    }
}

// MARK: - View

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        guard let goal = entry.goal, goal > 0 else { return 0 }
        return min(Double(entry.completed) / Double(goal), 1.0)
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
            if let goal = entry.goal, goal > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.completed)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("of \(goal)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                Text("This Week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.purple)
                Text("\(entry.completed)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(entry.completed == 1 ? "workout this week" : "workouts this week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            if let goal = entry.goal, goal > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.completed)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("of \(goal)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly Progress")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if progress >= 1.0 {
                        Label("Goal complete!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.purple)
                    } else {
                        let remaining = goal - entry.completed
                        Text("\(remaining) more \(remaining == 1 ? "workout" : "workouts") to go")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(entry.completed)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(entry.completed == 1 ? "workout" : "workouts")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget

struct WeeklyProgressWidget: Widget {
    let kind = "WeeklyProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Progress")
        .description("Track your workouts this week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
