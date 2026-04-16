import SwiftUI

// Minimal color palette for watchOS — matches the iPhone app's accent colors
enum WatchColors {
    static let accent = Color(red: 0.486, green: 0.361, blue: 1.0)   // #7c5cff
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369) // #22c55e
    static let warning = Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)  // #ef4444

    static let surface = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.5)
}
