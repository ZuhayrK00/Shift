import SwiftUI

/// The home heading owns mode selection so it doesn't add a row to every tab.
struct TrainingModeHeader: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("shift.trainingMode") private var mode: TrainingMode = .strength
    @State private var showModes = false
    @State private var showCalendar = false

    private var modeColor: Color { tint(for: mode) }

    private func tint(for option: TrainingMode) -> Color {
        option == .strength ? colors.accent : colors.enduranceAccent
    }

    private func title(for option: TrainingMode) -> String {
        option == .strength ? "Strength training" : "Endurance"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Shift")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(colors.text)
                .accessibilityAddTraits(.isHeader)
            Button { showModes = true } label: {
                HStack(spacing: 6) {
                    Text(mode == .strength ? "Strength" : "Endurance")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(modeColor)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .modifier(ModePillSurface(tint: modeColor, reduceTransparency: reduceTransparency))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Training mode")
            .accessibilityValue(title(for: mode))
            .accessibilityHint("Choose strength training or endurance")
            .popover(isPresented: $showModes, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Training mode")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(colors.muted)
                        .padding(.horizontal, 12).padding(.bottom, 4)
                    ForEach(TrainingMode.allCases, id: \.self) { option in
                        Button {
                            showModes = false
                            mode = option
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option == .strength ? "dumbbell.fill" : "figure.run")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(tint(for: option).opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                                Text(title(for: option)).font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                if mode == option { Image(systemName: "checkmark").font(.subheadline.bold()) }
                            }
                            .foregroundStyle(tint(for: option))
                            .padding(10)
                            .frame(minHeight: 56)
                            .background(mode == option ? tint(for: option).opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == option ? .isSelected : [])
                    }
                }
                .padding(12)
                .frame(idealWidth: 290)
                .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
            Button("Training calendar", systemImage: "calendar") { showCalendar = true }
                .labelStyle(.iconOnly).font(.system(size: 19, weight: .medium))
                .foregroundStyle(modeColor).frame(width: 44, height: 44)
                .sheet(isPresented: $showCalendar, onDismiss: { EnduranceRecorder.shared.openPendingCalendarSession() }) { TrainingCalendarView() }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

private struct ModePillSurface: ViewModifier {
    @Environment(\.shiftColors) private var colors
    let tint: Color
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(colors.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .background(tint.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
    }
}
