import SwiftUI
import WidgetKit

// MARK: - Entry

struct QuickStartEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry {
        QuickStartEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) {
        completion(QuickStartEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        completion(Timeline(entries: [QuickStartEntry(date: .now)], policy: .never))
    }
}

// MARK: - View

struct QuickStartWidgetView: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: mediumLayout
        default: smallLayout
        }
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.purple)
            }

            VStack(spacing: 2) {
                Text("Start")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Workout")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "com.zuhayrk.shift://start-workout"))
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Start Workout")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Tap to jump right in")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "com.zuhayrk.shift://start-workout"))
    }
}

// MARK: - Widget

struct QuickStartWidget: Widget {
    let kind = "QuickStartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStartProvider()) { _ in
            QuickStartWidgetView()
        }
        .configurationDisplayName("Quick Start")
        .description("Tap to start a workout.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
