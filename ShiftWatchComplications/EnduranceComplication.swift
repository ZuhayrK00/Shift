import SwiftUI
import WidgetKit

struct EnduranceComplicationEntry: TimelineEntry {
    var date: Date
    var data: EnduranceWidgetData?
    var isPro: Bool
}
struct EnduranceComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnduranceComplicationEntry { .init(date: .now, data: nil, isPro: true) }
    func getSnapshot(in context: Context, completion: @escaping (EnduranceComplicationEntry) -> Void) {
        completion(.init(date: .now, data: WidgetSnapshot.read()?.endurance, isPro: WidgetSnapshot.isProUser))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EnduranceComplicationEntry>) -> Void) {
        Task {
            let pro = await WidgetSnapshot.refreshProEntitlement()
            completion(Timeline(entries: [.init(date: .now, data: WidgetSnapshot.read()?.endurance, isPro: pro)], policy: .after(Date().addingTimeInterval(900))))
        }
    }
}
struct EnduranceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnduranceComplication", provider: EnduranceComplicationProvider()) { entry in
            EnduranceComplicationView(entry: entry).containerBackground(for: .widget) { Color.black }
        }.configurationDisplayName("Endurance").description("Your weekly distance and endurance recording shortcut.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
private struct EnduranceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EnduranceComplicationEntry
    private var distance: String { entry.data.map { EnduranceFormat.distance($0.distanceMeters, unit: $0.distanceUnit) } ?? "Endurance" }
    var body: some View {
        Group {
            if !entry.isPro { Label("Shift Pro", systemImage: "lock.fill").font(.caption) }
            else if family == .accessoryInline { Label(distance, systemImage: "figure.run") }
            else if family == .accessoryCircular {
                VStack(spacing: 2) {
                    Image(systemName: "figure.run").foregroundStyle(WatchColors.endurance)
                    if let data = entry.data { Text(String(format: "%.1f", data.distanceMeters / (data.distanceUnit == "mi" ? 1_609.344 : 1_000))).font(.system(size: 15, weight: .bold, design: .rounded)); Text(data.distanceUnit).font(.system(size: 9)) }
                    else { Text("Shift").font(.caption2) }
                }.minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Endurance", systemImage: "figure.run").font(.caption).foregroundStyle(WatchColors.endurance)
                    Text(distance).font(.headline)
                    if let data = entry.data { Text("\(data.activities) activities this week").font(.caption2) }
                    else { Text("Open Shift to sync").font(.caption2) }
                }
            }
        }.privacySensitive().widgetAccentable().widgetURL(URL(string: "shift://endurance"))
    }
}
