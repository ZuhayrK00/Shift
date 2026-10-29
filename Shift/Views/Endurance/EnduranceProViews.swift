import SwiftUI

struct EnduranceProCard: View {
    @Environment(\.shiftColors) private var colors
    var title: String
    var message: String
    var actionTitle = "Explore Shift Pro"
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").foregroundStyle(colors.accent).frame(width: 42, height: 42).background(colors.accentSoft, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SHIFT PRO").font(.caption2.weight(.bold)).tracking(1.6).foregroundStyle(colors.accent)
                    Text(title).font(.headline)
                }
            }
            Text(message).font(.subheadline).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack { Text(actionTitle); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.weight(.semibold))
                    .padding(14).foregroundStyle(colors.onAccent).background(colors.accent, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }.enduranceCard()
    }
}

struct EnduranceFreeWeekNote: View {
    @Environment(\.shiftColors) private var colors
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your first week is on us", systemImage: "gift.fill").font(.subheadline.weight(.semibold)).foregroundStyle(colors.enduranceAccent)
            Text("One complete week with weather and Calendar planning. Adjust it before saving. No payment required, and your saved sessions stay yours.")
                .font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(colors.enduranceSoft, in: RoundedRectangle(cornerRadius: 18))
    }
}
