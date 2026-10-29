import SwiftUI

/// Shared paywall content; only features that are available in this build are listed.
struct ShiftProBenefitsView: View {
    @Environment(\.shiftColors) private var colors
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Strength + Endurance", endurance: true) {
                row("sparkles", "Personalised endurance weeks", "Plan runs, walks and rides around your availability.", endurance: true)
                row("cloud.sun", "Weather + Calendar planning", "Find suitable forecast windows and avoid busy events.", endurance: true)
                row("calendar.badge.clock", "Forecast change suggestions", "Review better times if the forecast worsens. You confirm every move.", endurance: true)
                row("bubble.left.and.text.bubble.right", "Your endurance coach", "Talk through goals and routines with on-device AI.", endurance: true)
                row("chart.xyaxis.line", "Plans and longer-term trends", "Use the training plan library and explore six months of endurance progress.", endurance: true)
            }
            group("More ways to train", endurance: false) {
                row("dumbbell.fill", "AI strength plans + unlimited plans", "Build personalised gym workouts and keep your full plan library.")
                row("applewatch", "Apple Watch + widgets", "Record from your wrist and keep your training in view.")
                row("photo.on.rectangle.angled", "Photos + body measurements", "Keep a visual journal and follow changes over time.")
            }
            Text("AI features need a compatible device with Apple Intelligence enabled. You can use the week planner controls without AI.").font(.caption).foregroundStyle(colors.muted)
            Label("Recording, Apple Health imports, activity history, basic goals and reminders stay free.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func group<Content: View>(_ title: String, endurance: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(endurance ? colors.enduranceAccent : colors.accent).padding(.bottom, 6)
            content()
        }.padding(16).background(colors.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(colors.border, lineWidth: 1))
    }
    private func row(_ symbol: String, _ title: String, _ detail: String, endurance: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(endurance ? colors.enduranceAccent : colors.accent)
                .frame(width: 34, height: 34).background(endurance ? colors.enduranceSoft : colors.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colors.text)
                Text(detail).font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }
}
