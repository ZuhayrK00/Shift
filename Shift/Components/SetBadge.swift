import SwiftUI

// MARK: - SetBadge

/// Compact or regular circle badge showing set number or type indicator.
struct SetBadge: View {
    let set: SessionSet
    var compact: Bool = false

    @Environment(\.shiftColors) private var colors

    private var size: CGFloat { compact ? 28 : 36 }

    private var badgeColor: Color {
        switch set.setType {
        case .warmup:  return colors.warning
        case .drop:    return colors.accent2
        case .failure: return colors.danger
        case .normal:  return colors.surface2
        }
    }

    private var textColor: Color {
        switch set.setType {
        case .normal: return colors.muted
        default:      return .white
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: size, height: size)
            Text(set.badgeLabel)
                .font(.system(size: compact ? 11 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
        }
    }
}

// MARK: - SetTypeMenu

/// Context menu for changing a set's type. Attach as a modifier or embed as a button.
struct SetTypeMenuButton: View {
    let set: SessionSet
    let onChangeType: (SetType) -> Void

    @Environment(\.shiftColors) private var colors

    var body: some View {
        Menu {
            ForEach(SetType.allCases, id: \.self) { type in
                Button {
                    onChangeType(type)
                } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                }
            }
        } label: {
            SetBadge(set: set, compact: true)
        }
    }
}

// MARK: - SetType display helpers

extension SetType {
    var displayName: String {
        switch self {
        case .normal:  return "Normal"
        case .warmup:  return "Warm-up"
        case .drop:    return "Drop set"
        case .failure: return "To failure"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:  return "checkmark.circle"
        case .warmup:  return "flame"
        case .drop:    return "arrow.down.circle"
        case .failure: return "bolt.circle"
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        let base = SessionSet(
            id: "1", sessionId: "s", exerciseId: "e",
            setNumber: 1, isCompleted: true
        )
        SetBadge(set: base)
        SetBadge(set: SessionSet(id: "2", sessionId: "s", exerciseId: "e",
                                  setNumber: 2, isCompleted: true, setType: .warmup))
        SetBadge(set: SessionSet(id: "3", sessionId: "s", exerciseId: "e",
                                  setNumber: 3, isCompleted: true, setType: .drop))
        SetBadge(set: SessionSet(id: "4", sessionId: "s", exerciseId: "e",
                                  setNumber: 4, isCompleted: true, setType: .failure), compact: true)
    }
    .padding()
    .background(Color(hex: "#0b0b0f"))
    .shiftTheme()
}
