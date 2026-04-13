import SwiftUI

// MARK: - StepperControl

/// Custom stepper with label, minus/plus buttons, and an editable text field.
/// Supports both integer and decimal values via the `allowDecimal` flag.
struct StepperControl: View {
    let label: String
    @Binding var value: Double
    var step: Double = 1.0
    var allowDecimal: Bool = false

    @Environment(\.shiftColors) private var colors

    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 0) {
                // Minus button
                Button {
                    adjustValue(by: -step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.text)
                        .frame(width: 44, height: 44)
                        .background(colors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                // Value text field
                TextField("0", text: $textValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.text)
                    .multilineTextAlignment(.center)
                    .keyboardType(allowDecimal ? .decimalPad : .numberPad)
                    .focused($isFocused)
                    .frame(minWidth: 72)
                    .onChange(of: textValue) { _, newVal in
                        commitText(newVal)
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { syncText() }
                    }
                    .onAppear { syncText() }
                    .onChange(of: value) { _, _ in
                        if !isFocused { syncText() }
                    }

                // Plus button
                Button {
                    adjustValue(by: step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.text)
                        .frame(width: 44, height: 44)
                        .background(colors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func adjustValue(by delta: Double) {
        let newVal = max(0, value + delta)
        // Snap to nearest step multiple
        let snapped = (newVal / step).rounded() * step
        value = snapped
        syncText()
    }

    private func syncText() {
        if allowDecimal {
            // Show one decimal if non-integer, otherwise whole number
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                textValue = String(format: "%.0f", value)
            } else {
                textValue = String(format: "%.1f", value)
            }
        } else {
            textValue = String(format: "%.0f", value)
        }
    }

    private func commitText(_ text: String) {
        let sanitised = text.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(sanitised) else { return }
        value = max(0, parsed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var weight: Double = 80.0
    @Previewable @State var reps: Double = 8.0

    HStack(spacing: 24) {
        StepperControl(label: "Weight", value: $weight, step: 2.5, allowDecimal: true)
        StepperControl(label: "Reps", value: $reps, step: 1.0, allowDecimal: false)
    }
    .padding()
    .background(Color(hex: "#0b0b0f"))
    .shiftTheme()
}
