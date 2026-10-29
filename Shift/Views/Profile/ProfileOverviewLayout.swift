import SwiftUI

enum ProfileOverviewAction: Hashable {
    case frequency, steps, weight, body, strengthRecords, enduranceRecords, enduranceGoals, calendar
    case exercise(String)
}
struct ProfileOverviewRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var value: String = ""
    var progress: Double?
    var endurance = false
    var action: ProfileOverviewAction
}
struct ProfileOverviewData {
    var name: String
    var strengthCount: Int
    var enduranceCount: Int
    var distance: String
    var enduranceTime: String
    var goals: [ProfileOverviewRow]
    var weight: String
    var body: String
    var photos: String
    var strengthRecords: [String]
    var enduranceRecords: [String]
    var loading = false
    var error: String?
}

struct ProfileOverviewLayout<Avatar: View>: View {
    @Environment(\.shiftColors) private var colors
    let data: ProfileOverviewData
    let avatar: Avatar
    var action: (ProfileOverviewAction) -> Void
    init(data: ProfileOverviewData, @ViewBuilder avatar: () -> Avatar, action: @escaping (ProfileOverviewAction) -> Void) {
        self.data = data; self.avatar = avatar(); self.action = action
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR SHIFT").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(colors.muted)
                    Text(data.name).font(.system(size: 29, weight: .bold, design: .rounded)).lineLimit(2)
                    HStack(spacing: 8) { modeTag("Strength", "dumbbell.fill", colors.accent); modeTag("Endurance", "figure.run", colors.enduranceAccent) }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 8)
            overview
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Your goals", subtitle: "Every kind of progress, together")
                VStack(spacing: 0) {
                    ForEach(Array(data.goals.enumerated()), id: \.element.id) { index, goal in
                        if index > 0 { Divider().overlay(colors.border).padding(.leading, 60) }
                        goalRow(goal)
                    }
                }.background(colors.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Body & wellbeing", subtitle: "Your personal progress journal")
                Button { action(.body) } label: {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Text("Progress journal").font(.headline); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(colors.muted) }
                        HStack(alignment: .top, spacing: 10) {
                            journalMetric("Weight", data.weight, "scalemass")
                            journalMetric("Body", data.body, "ruler")
                            journalMetric("Photos", data.photos, data.photos == "Locked" ? "lock" : "camera")
                        }
                    }.padding(18).background(colors.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Your records", subtitle: "Strength inside. Distance outside.")
                VStack(spacing: 0) {
                    recordsRow("Strength", icon: "trophy", records: data.strengthRecords, endurance: false, destination: .strengthRecords)
                    Divider().overlay(colors.border).padding(.horizontal, 18)
                    recordsRow("Endurance", icon: "medal", records: data.enduranceRecords, endurance: true, destination: .enduranceRecords)
                }.background(colors.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
            }
            if let error = data.error { Text(error).font(.footnote).foregroundStyle(colors.warning) }
        }.foregroundStyle(colors.text).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Button { action(.calendar) } label: { Image(systemName: "calendar").frame(width: 36, height: 36).background(colors.surface.opacity(0.5), in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Open training calendar")
            }
            HStack(alignment: .top, spacing: 12) {
                metric("Gym sessions", "\(data.strengthCount)", color: colors.accent)
                metric("Endurance", data.distance, color: colors.enduranceAccent)
                metric("Endurance time", data.enduranceTime, color: colors.text)
            }
            HStack(spacing: 7) {
                Image(systemName: "figure.mixed.cardio").foregroundStyle(colors.enduranceAccent)
                Text(data.loading ? "Updating your week…" : "\(data.strengthCount + data.enduranceCount) completed sessions across Strength & Endurance")
                    .font(.caption).foregroundStyle(colors.muted)
            }
        }.padding(20).background(LinearGradient(colors: [colors.accent.opacity(0.13), colors.enduranceAccent.opacity(0.08), colors.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(colors.accent.opacity(0.15), lineWidth: 1))
    }
    private func modeTag(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 6).background(tint.opacity(0.1), in: Capsule())
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(colors.muted) }
    }
    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1).foregroundStyle(color); Text(title).font(.caption2).foregroundStyle(colors.muted) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func journalMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Image(systemName: symbol).font(.subheadline).foregroundStyle(colors.accent); Text(value).font(.subheadline.weight(.semibold)).lineLimit(2); Text(title).font(.caption).foregroundStyle(colors.muted) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func goalRow(_ row: ProfileOverviewRow) -> some View {
        Button { action(row.action) } label: {
            HStack(spacing: 13) {
                Image(systemName: row.symbol).foregroundStyle(row.endurance ? colors.enduranceAccent : colors.accent).frame(width: 36, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title).font(.subheadline.weight(.semibold))
                    Text(row.subtitle).font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
                    if let progress = row.progress {
                        GeometryReader { geometry in
                            Capsule().fill(colors.border).overlay(alignment: .leading) {
                                Capsule().fill(row.endurance ? colors.enduranceAccent : colors.accent)
                                    .frame(width: geometry.size.width * min(1, max(0, progress)))
                            }
                        }.frame(maxWidth: 170).frame(height: 4).padding(.top, 3)
                            .accessibilityLabel("Goal progress").accessibilityValue("\(Int(min(1, max(0, progress)) * 100)) percent")
                    }
                }
                Spacer(minLength: 4)
                if !row.value.isEmpty { Text(row.value).font(.caption.weight(.semibold)).foregroundStyle(row.endurance ? colors.enduranceAccent : colors.accent) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(colors.muted)
            }.padding(.horizontal, 16).padding(.vertical, 16).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func recordsRow(_ title: String, icon: String, records: [String], endurance: Bool, destination: ProfileOverviewAction) -> some View {
        Button { action(destination) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(endurance ? colors.enduranceAccent : colors.accent); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(colors.muted) }
                if records.isEmpty { Text("Your first record is ahead of you.").font(.caption).foregroundStyle(colors.muted) }
                ForEach(Array(records.prefix(2).enumerated()), id: \.offset) { _, value in Text(value).font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
