import SwiftUI

// MARK: - SegmentedControl

/// Reusable segmented control matching the Shift app style.
/// Generic over the value type so it works with any `Equatable` + `Hashable` tag.
struct SegmentedControl<Value: Hashable & Equatable>: View {
    struct Segment {
        let label: String
        let value: Value
    }

    let segments: [Segment]
    @Binding var selection: Value

    @Environment(\.shiftColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.value) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = segment.value
                    }
                } label: {
                    Text(segment.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == segment.value ? .white : colors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == segment.value
                                ? colors.accent
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - String convenience initialiser

extension SegmentedControl where Value == String {
    /// Convenience init for simple string-valued segments.
    init(options: [String], selection: Binding<String>) {
        self.segments = options.map { Segment(label: $0, value: $0) }
        self._selection = selection
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab = "Log"

    SegmentedControl(
        segments: [
            .init(label: "Log",      value: "Log"),
            .init(label: "Info",     value: "Info"),
            .init(label: "History",  value: "History"),
            .init(label: "Progress", value: "Progress"),
        ],
        selection: $tab
    )
    .padding()
    .background(Color(hex: "#0b0b0f"))
    .shiftTheme()
}
