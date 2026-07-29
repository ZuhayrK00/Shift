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
    let onAccent: Color
    let controlTint: Color
    let accentSoft: Color
    let accent2: Color
    let success: Color
    let onSuccess: Color
    let warning: Color
    let onWarning: Color
    let danger: Color
    let onDanger: Color
}

// MARK: - ShiftColors

/// Resolved colour set for the current colour scheme.
/// Access via the `\.shiftColors` environment key.
struct ShiftColors {
    private let light = ShiftColorPalette(
        bg:         Color(hex: "#f6f6f4"),
        surface:    Color(hex: "#ffffff"),
        surface2:   Color(hex: "#ececea"),
        border:     Color(hex: "#d8d8d4"),
        text:       Color(hex: "#0a0a0a"),
        muted:      Color(hex: "#626262"),
        accent:     Color(hex: "#111111"),
        onAccent:   Color(hex: "#ffffff"),
        controlTint: Color(hex: "#111111"),
        accentSoft: Color(hex: "#e6e6e2"),
        accent2:    Color(hex: "#6f6f6a"),
        success:    Color(hex: "#16803c"),
        onSuccess:  Color(hex: "#ffffff"),
        warning:    Color(hex: "#b35a00"),
        onWarning:  Color(hex: "#ffffff"),
        danger:     Color(hex: "#c62828"),
        onDanger:   Color(hex: "#ffffff")
    )

    private let dark = ShiftColorPalette(
        bg:         Color(hex: "#050505"),
        surface:    Color(hex: "#101010"),
        surface2:   Color(hex: "#191919"),
        border:     Color(hex: "#2a2a2a"),
        text:       Color(hex: "#f4f4f2"),
        muted:      Color(hex: "#a0a09b"),
        accent:     Color(hex: "#f2f2ee"),
        onAccent:   Color(hex: "#0a0a0a"),
        controlTint: Color(hex: "#3978f6"),
        accentSoft: Color(hex: "#242424"),
        accent2:    Color(hex: "#a8a8a2"),
        success:    Color(hex: "#39c66d"),
        onSuccess:  Color(hex: "#050505"),
        warning:    Color(hex: "#f0a23b"),
        onWarning:  Color(hex: "#050505"),
        danger:     Color(hex: "#ff5b5b"),
        onDanger:   Color(hex: "#050505")
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
    var onAccent: Color { palette.onAccent }
    /// Interactive controls need a mid-tone track in dark mode so their white
    /// thumb or glyph remains legible.
    var controlTint: Color { palette.controlTint }
    var accentSoft: Color { palette.accentSoft }
    var accent2:  Color { palette.accent2 }
    var success:  Color { palette.success }
    var onSuccess: Color { palette.onSuccess }
    var warning:  Color { palette.warning }
    var onWarning: Color { palette.onWarning }
    var danger:   Color { palette.danger }
    var onDanger: Color { palette.onDanger }
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
