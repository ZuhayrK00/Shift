import SwiftUI

/// Shared presentation for the home screen, activity preparation and weather settings.
struct OutdoorConditionsView: View {
    @Environment(\.shiftColors) private var colors
    let snapshot: OutdoorWeatherSnapshot
    let sport: EnduranceSport
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.place).font(.subheadline.weight(.medium)).foregroundStyle(colors.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Self.temperature(snapshot.current.celsius)).font(.system(size: compact ? 32 : 48, weight: .medium, design: .rounded)).tracking(-1.5)
                        if compact { Text(snapshot.current.condition).font(.subheadline).foregroundStyle(colors.muted) }
                    }
                    if !compact { Text(snapshot.current.condition).font(.subheadline).foregroundStyle(colors.muted) }
                }
                Spacer(minLength: 4)
                Image(systemName: snapshot.current.symbol).symbolRenderingMode(.palette)
                    .foregroundStyle(snapshot.current.symbol.hasPrefix("sun") ? colors.warning : colors.text.opacity(0.7), colors.accent2)
                    .font(.system(size: compact ? 34 : 50, weight: .light)).frame(width: compact ? 52 : 74)
            }
            HStack(spacing: 0) {
                metric("wind", "\(Int(snapshot.current.windKPH.rounded())) km/h", "Wind")
                Spacer(minLength: 8)
                metric("drop.fill", "\(Int((snapshot.current.rainChance * 100).rounded()))%", "Rain")
                Spacer(minLength: 8)
                metric("sun.max", "\(snapshot.current.uv)", "UV index")
            }
            let cautions = EnduranceWeatherPolicy.cautions(snapshot.current, sport: sport)
            if !cautions.isEmpty {
                Label(cautions.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private func metric(_ symbol: String, _ value: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.caption).foregroundStyle(colors.enduranceAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.caption.weight(.semibold)).foregroundStyle(colors.text)
                Text(title).font(.caption2).foregroundStyle(colors.muted)
            }
        }.accessibilityElement(children: .combine)
    }
    static func temperature(_ value: Double) -> String {
        Measurement(value: value, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
