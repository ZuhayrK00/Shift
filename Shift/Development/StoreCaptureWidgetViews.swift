#if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
import SwiftUI
import WidgetKit
struct EnduranceWidgetEntry: TimelineEntry {
    var date: Date
    var summary: EnduranceWidgetData?
    var isPro: Bool
}

private struct EnduranceWeekWidgetView: View {
    private let family: WidgetFamily = .systemMedium
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

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let goal: Int?
    let isPro: Bool
    let hasData: Bool
}

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry
    private let family: WidgetFamily = .systemSmall

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
        .proProtected(isPro: entry.isPro, hasData: entry.hasData)
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(spacing: 8) {
            if let goal = entry.goal, goal > 0 {
                ZStack {
                    Circle()
                        .stroke(WidgetColors.accentSoft, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WidgetColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
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
                    .foregroundStyle(WidgetColors.accent)
                    .widgetAccentable()
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
                        .stroke(WidgetColors.accentSoft, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WidgetColors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
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
                            .foregroundStyle(WidgetColors.accent)
                            .widgetAccentable()
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
                    .foregroundStyle(WidgetColors.accent)
                    .widgetAccentable()

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




/// Overlay modifier that blurs widget content and shows a "Shift Pro" lock when not Pro.
/// Replaces the containerBackground with a dimmed version so the overlay fills edge-to-edge.
struct ProLockedOverlay: ViewModifier {
    let isPro: Bool
    var hasData: Bool = true
    private let family: WidgetFamily = .systemSmall

    private var isSmall: Bool { family == .systemSmall }

    func body(content: Content) -> some View {
        if isPro && hasData {
            content
        } else if isPro {
            VStack(spacing: isSmall ? 7 : 9) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: isSmall ? 17 : 21, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Open Shift to sync")
                    .font(.system(size: isSmall ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.background, for: .widget)
        } else {
            VStack(spacing: isSmall ? 8 : 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: isSmall ? 18 : 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Shift Pro")
                    .font(.system(size: isSmall ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .containerBackground(for: .widget) {
                ZStack {
                    // Render original content as background, blurred
                    content
                        .blur(radius: 14)
                    // Dark tint over the entire widget
                    Color.black.opacity(0.55)
                }
            }
        }
    }
}

extension View {
    func proLocked(_ isPro: Bool) -> some View {
        modifier(ProLockedOverlay(isPro: isPro))
    }

    func proProtected(isPro: Bool, hasData: Bool) -> some View {
        modifier(ProLockedOverlay(isPro: isPro, hasData: hasData))
    }
}

private enum WidgetColors {
    static let endurance = Color(red: 0.18, green: 0.76, blue: 0.71)
    static let accent = Color(red: 0.69, green: 0.61, blue: 1)
    static let accentSoft = accent.opacity(0.14)
}
struct StoreCaptureWidgetsView: View {
    var body: some View {
        VStack(spacing: 32) {
            EnduranceWeekWidgetView(entry:.init(date:.now,summary:StoreCaptureWatchData.summary,isPro:true))
                .padding(18).frame(width:364,height:180)
                .background(Color(red:0.07,green:0.07,blue:0.08),in:RoundedRectangle(cornerRadius:28))
            WeeklyProgressWidgetView(entry:.init(date:.now,completed:2,goal:4,isPro:true,hasData:true))
                .padding(18).frame(width:170,height:170)
                .background(Color(red:0.07,green:0.07,blue:0.08),in:RoundedRectangle(cornerRadius:28))
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
}

#endif
