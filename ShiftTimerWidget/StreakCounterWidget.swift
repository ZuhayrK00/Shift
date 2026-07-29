import SwiftUI
import WidgetKit

// MARK: - Entry

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let unit: String
    let isPro: Bool
    let hasData: Bool
}

// MARK: - Provider

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 4, unit: "days", isPro: true, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry(from: context.isPreview ? .placeholder : WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        Task {
            let snapshot = WidgetSnapshot.read()
            let isPro = await WidgetSnapshot.refreshProEntitlement()
            let tomorrow = Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            )
            completion(Timeline(entries: [entry(from: snapshot, isPro: isPro)], policy: .after(tomorrow)))
        }
    }

    private func entry(
        from snapshot: WidgetSnapshot?,
        isPro: Bool = WidgetSnapshot.isProUser
    ) -> StreakEntry {
        return StreakEntry(
            date: .now,
            streak: snapshot?.currentStreak ?? 0,
            unit: snapshot?.streakUnit ?? "days",
            isPro: isPro,
            hasData: snapshot != nil
        )
    }
}

// MARK: - View

struct StreakCounterWidgetView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) var family

    private var accentColor: Color { entry.streak > 0 ? .orange : .gray }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumLayout
            default: smallLayout
            }
        }
        .proProtected(isPro: entry.isPro, hasData: entry.hasData)
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: "flame.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            if entry.streak > 0 {
                VStack(spacing: 2) {
                    Text("\(entry.streak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("day streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Start a streak!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 70, height: 70)
                Image(systemName: "flame.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            if entry.streak > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout Streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(entry.streak)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(entry.streak == 1 ? "day" : "days")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Keep it going!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout Streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No active streak")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Work out today to start one!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget

struct StreakCounterWidget: Widget {
    let kind = "StreakCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your current workout streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
