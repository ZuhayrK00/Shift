import SwiftUI
import WidgetKit

// MARK: - Entry

struct TodaysActivityEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let stepGoal: Int?
    let workedOutToday: Bool
    let workoutsThisWeek: Int
    let weeklyGoal: Int?
    let currentStreak: Int
}

// MARK: - Provider

struct TodaysActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodaysActivityEntry {
        Self.entry(from: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaysActivityEntry) -> Void) {
        completion(Self.entry(from: WidgetSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaysActivityEntry>) -> Void) {
        let entry = Self.entry(from: WidgetSnapshot.read() ?? .placeholder)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    static func entry(from s: WidgetSnapshot) -> TodaysActivityEntry {
        TodaysActivityEntry(
            date: .now,
            steps: s.stepsToday,
            stepGoal: s.stepGoal,
            workedOutToday: s.workedOutToday,
            workoutsThisWeek: s.workoutsThisWeek,
            weeklyGoal: s.weeklyGoal,
            currentStreak: s.currentStreak
        )
    }
}

// MARK: - View

struct TodaysActivityWidgetView: View {
    let entry: TodaysActivityEntry
    @Environment(\.widgetFamily) var family

    private var stepProgress: Double {
        guard let goal = entry.stepGoal, goal > 0 else { return 0 }
        return min(Double(entry.steps) / Double(goal), 1.0)
    }

    private var weeklyProgress: Double {
        guard let goal = entry.weeklyGoal, goal > 0 else { return 0 }
        return min(Double(entry.workoutsThisWeek) / Double(goal), 1.0)
    }

    var body: some View {
        switch family {
        case .systemLarge: largeLayout
        case .systemMedium: mediumLayout
        default: smallLayout
        }
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Steps
            HStack(spacing: 6) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(formatSteps(entry.steps))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                if let goal = entry.stepGoal, goal > 0 {
                    Text("/ \(formatSteps(goal))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let _ = entry.stepGoal {
                progressBar(value: stepProgress, color: .green)
                    .padding(.top, 5)
            }

            Spacer()

            // Streak
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(entry.currentStreak > 0 ? .orange : .gray)
                Text("\(entry.currentStreak)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(entry.currentStreak > 0 ? .primary : .gray)
                Text("day streak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Weekly
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
                if let goal = entry.weeklyGoal, goal > 0 {
                    Text("\(entry.workoutsThisWeek)/\(goal)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("weekly")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.workoutsThisWeek)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("this week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Trained
            HStack(spacing: 6) {
                Image(systemName: entry.workedOutToday ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(entry.workedOutToday ? .green : .gray)
                Text(entry.workedOutToday ? "Trained today" : "Not trained")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.workedOutToday ? .primary : .gray)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 0) {
            mediumColumn(
                color: .green,
                icon: "shoeprints.fill",
                progress: entry.stepGoal != nil ? stepProgress : nil,
                value: formatSteps(entry.steps),
                label: "steps"
            )
            mediumColumn(
                color: entry.currentStreak > 0 ? .orange : .gray,
                icon: "flame.fill",
                progress: nil,
                value: "\(entry.currentStreak)",
                label: "day streak"
            )
            mediumColumn(
                color: .purple,
                icon: "calendar",
                progress: entry.weeklyGoal != nil ? weeklyProgress : nil,
                value: entry.weeklyGoal != nil
                    ? "\(entry.workoutsThisWeek)/\(entry.weeklyGoal!)"
                    : "\(entry.workoutsThisWeek)",
                label: "this week"
            )
            mediumColumn(
                color: entry.workedOutToday ? .green : .gray,
                icon: entry.workedOutToday ? "checkmark" : "xmark",
                progress: entry.workedOutToday ? 1.0 : 0,
                value: nil,
                label: "trained"
            )
        }
        .containerBackground(.background, for: .widget)
    }

    private func mediumColumn(
        color: Color,
        icon: String,
        progress: Double?,
        value: String?,
        label: String
    ) -> some View {
        VStack(spacing: 8) {
            // Icon above ring
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            // Ring
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if let value {
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 52, height: 52)

            // Label
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Large

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image("ShiftLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                Text("Shift")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(entry.date, style: .date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // ── Section 1: Steps ──
            VStack(alignment: .leading, spacing: 6) {
                Label("Steps", systemImage: "shoeprints.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)

                Text(formatSteps(entry.steps))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)

                if let goal = entry.stepGoal, goal > 0 {
                    progressBar(value: stepProgress, color: .green)
                    Text("of \(formatSteps(goal)) steps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("steps today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(maxWidth: .infinity, maxHeight: 1)

            Spacer()

            // ── Section 2: Weekly Goal ──
            VStack(alignment: .leading, spacing: 6) {
                Label("This Week", systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)

                Text("\(entry.workoutsThisWeek)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let goal = entry.weeklyGoal, goal > 0 {
                    progressBar(value: weeklyProgress, color: .purple)
                    Text("of \(goal) workouts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.workoutsThisWeek == 1 ? "workout" : "workouts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(maxWidth: .infinity, maxHeight: 1)

            Spacer()

            // ── Section 3: Streak + Trained ──
            HStack(spacing: 0) {
                // Streak
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(entry.currentStreak > 0 ? .orange : .gray)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(entry.currentStreak)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(entry.currentStreak > 0 ? .primary : .gray)
                        Text("day streak")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trained
                HStack(spacing: 10) {
                    Image(systemName: entry.workedOutToday ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 18))
                        .foregroundStyle(entry.workedOutToday ? .green : .gray)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.workedOutToday ? "Done" : "Not yet")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(entry.workedOutToday ? .primary : .gray)
                        Text("trained today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Helpers

    private func progressBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.2))
                    .frame(height: 5)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * value, height: 5)
            }
        }
        .frame(height: 5)
    }

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

struct TodaysActivityWidget: Widget {
    let kind = "TodaysActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaysActivityProvider()) { entry in
            TodaysActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Activity")
        .description("Steps, streak, workouts, and more.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
