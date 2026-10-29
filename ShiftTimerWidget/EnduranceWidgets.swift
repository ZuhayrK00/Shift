import SwiftUI
import WidgetKit

struct EnduranceWidgetEntry: TimelineEntry {
    var date: Date
    var summary: EnduranceWidgetData?
    var isPro: Bool
}
struct EnduranceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnduranceWidgetEntry {
        .init(date: .now, summary: .init(weekStart: .now, distanceMeters: 18_400, activeSeconds: 6_000, activities: 4,
            distanceUnit: "km", distanceGoalMeters: 25_000, runMeters: 10_000, walkMeters: 3_400, cycleMeters: 5_000, nextSessions: []), isPro: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (EnduranceWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .init(date: .now, summary: WidgetSnapshot.read()?.endurance, isPro: WidgetSnapshot.isProUser))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EnduranceWidgetEntry>) -> Void) {
        Task {
            let pro = await WidgetSnapshot.refreshProEntitlement()
            let entry = EnduranceWidgetEntry(date: .now, summary: WidgetSnapshot.read()?.endurance, isPro: pro)
            var entries = [entry]
            if let weather = entry.summary?.weather {
                let expiry = weather.fetchedAt.addingTimeInterval(3_601)
                if expiry > entry.date {
                    var expired = entry
                    expired.date = expiry; expired.summary?.weather = nil
                    entries.append(expired)
                }
            }
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}
struct EnduranceWeekWidget: Widget {
    let kind = "EnduranceWeekWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EnduranceWidgetProvider()) { entry in
            EnduranceWeekWidgetView(entry: entry).containerBackground(for: .widget) { Color(.systemBackground) }
        }.configurationDisplayName("Endurance this week")
            .description("Distance, activity time and quick starts for your runs, walks and rides.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
private struct EnduranceWeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EnduranceWidgetEntry
    var body: some View {
        Group {
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 3 : 10) {
                    Label("Endurance", systemImage: "figure.run").font(.caption.weight(.semibold)).foregroundStyle(WidgetColors.endurance)
                    Text(EnduranceFormat.distance(summary.distanceMeters, unit: summary.distanceUnit)).font(family == .accessoryRectangular ? .headline : .system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text("\(summary.activities) activities · \(Int(summary.activeSeconds / 60)) min").font(.caption).foregroundStyle(.secondary)
                    if family != .accessoryRectangular {
                        if let target = summary.distanceGoalMeters, target > 0 {
                            ProgressView(value: min(summary.distanceMeters, target), total: target).tint(WidgetColors.endurance)
                            Text("of \(EnduranceFormat.distance(target, unit: summary.distanceUnit)) this week").font(.caption2).foregroundStyle(.secondary)
                        }
                        if family == .systemMedium {
                            if let weather = summary.weather, weather.isFresh(at: entry.date) {
                                HStack {
                                    Label("\(Int(weather.celsius.rounded()))°C · \(weather.place)", systemImage: weather.symbol).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Link(destination: weather.legalURL) { Label("Weather", systemImage: "apple.logo") }
                                }.font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                ForEach(EnduranceSport.allCases) { sport in
                                    Link(destination: URL(string: "shift://endurance?sport=\(sport.rawValue)")!) {
                                        Label(sport.title, systemImage: sport.symbol).font(.caption.weight(.semibold)).padding(.vertical, 7).frame(maxWidth: .infinity)
                                            .background(WidgetColors.endurance.opacity(0.12), in: Capsule())
                                    }.foregroundStyle(WidgetColors.endurance)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).privacySensitive()
            } else {
                VStack(alignment: .leading, spacing: 8) { Label("Endurance", systemImage: "figure.run").foregroundStyle(WidgetColors.endurance); Text("Open Shift to sync your week").font(.caption).foregroundStyle(.secondary) }
            }
        }.widgetURL(URL(string: "shift://endurance")).proLocked(entry.isPro)
    }
}
struct TrainingAgendaWidget: Widget {
    let kind = "TrainingAgendaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EnduranceWidgetProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                Label("Up next in Shift", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(WidgetColors.accent)
                if let summary = entry.summary, !summary.nextSessions.isEmpty {
                    ForEach(Array(summary.nextSessions.prefix(3))) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol).foregroundStyle(item.kind == .strength ? WidgetColors.accent : WidgetColors.endurance).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                                if item.isAllDay == true { Text(item.scheduledAt, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.secondary) }
                                else { Text(item.scheduledAt, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                } else { Text("Room for your next session").font(.headline); Text("Plan a gym workout, run, walk or ride.").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).privacySensitive()
                .widgetURL(URL(string: "shift://training-calendar")).proLocked(entry.isPro)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }.configurationDisplayName("Training calendar").description("Your next planned gym and endurance sessions together.").supportedFamilies([.systemMedium])
    }
}
