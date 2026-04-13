import SwiftUI

// MARK: - Colour palettes

/// All raw colour values for a given colour scheme.
struct ShiftColorPalette {
    let bg: Color
    let surface: Color
    let surface2: Color
    let border: Color
    let text: Color
    let muted: Color
    let accent: Color
    let accent2: Color
    let success: Color
    let warning: Color
    let danger: Color
}

// MARK: - ShiftColors

/// Resolved colour set for the current colour scheme.
/// Access via the `\.shiftColors` environment key.
struct ShiftColors {
    private let light = ShiftColorPalette(
        bg:       Color(hex: "#fafafc"),
        surface:  Color(hex: "#ffffff"),
        surface2: Color(hex: "#f1f1f6"),
        border:   Color(hex: "#e2e2ea"),
        text:     Color(hex: "#11111a"),
        muted:    Color(hex: "#646478"),
        accent:   Color(hex: "#7c5cff"),
        accent2:  Color(hex: "#22d3ee"),
        success:  Color(hex: "#16a34a"),
        warning:  Color(hex: "#d97706"),
        danger:   Color(hex: "#dc2626")
    )

    private let dark = ShiftColorPalette(
        bg:       Color(hex: "#0b0b0f"),
        surface:  Color(hex: "#16161d"),
        surface2: Color(hex: "#1f1f29"),
        border:   Color(hex: "#2a2a36"),
        text:     Color(hex: "#f5f5f7"),
        muted:    Color(hex: "#9a9aae"),
        accent:   Color(hex: "#7c5cff"),
        accent2:  Color(hex: "#22d3ee"),
        success:  Color(hex: "#22c55e"),
        warning:  Color(hex: "#f59e0b"),
        danger:   Color(hex: "#ef4444")
    )

    private let scheme: ColorScheme

    init(colorScheme: ColorScheme) {
        self.scheme = colorScheme
    }

    private var palette: ShiftColorPalette {
        scheme == .dark ? dark : light
    }

    // MARK: Public accessors

    var bg:       Color { palette.bg }
    var surface:  Color { palette.surface }
    var surface2: Color { palette.surface2 }
    var border:   Color { palette.border }
    var text:     Color { palette.text }
    var muted:    Color { palette.muted }
    var accent:   Color { palette.accent }
    var accent2:  Color { palette.accent2 }
    var success:  Color { palette.success }
    var warning:  Color { palette.warning }
    var danger:   Color { palette.danger }
}

// MARK: - Environment key

private struct ShiftColorsKey: EnvironmentKey {
    static let defaultValue = ShiftColors(colorScheme: .dark)
}

extension EnvironmentValues {
    var shiftColors: ShiftColors {
        get { self[ShiftColorsKey.self] }
        set { self[ShiftColorsKey.self] = newValue }
    }
}

// MARK: - View modifier

/// Inject `shiftColors` into the environment, resolved from the current colour scheme.
struct ShiftThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.shiftColors, ShiftColors(colorScheme: colorScheme))
    }
}

extension View {
    /// Apply the Shift theme. Place once at the root view.
    func shiftTheme() -> some View {
        modifier(ShiftThemeModifier())
    }
}

// MARK: - Hex colour helper

extension Color {
    /// Initialise a Color from a 6-digit hex string ("#rrggbb" or "rrggbb").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >>  8) & 0xFF) / 255.0
        let b = Double( rgb        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
