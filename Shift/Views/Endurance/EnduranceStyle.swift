import SwiftUI

struct EnduranceStat: View {
    @Environment(\.shiftColors) private var colors
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(colors.muted)
        }
    }
}

private struct EnduranceCardModifier: ViewModifier {
    @Environment(\.shiftColors) private var colors
    func body(content: Content) -> some View {
        content.padding(18).background(colors.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(colors.border, lineWidth: 1))
    }
}
extension View {
    func enduranceCard() -> some View { modifier(EnduranceCardModifier()) }
}
