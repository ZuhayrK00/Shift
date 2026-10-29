import SwiftUI

// Violet strength accents and teal endurance accents match the iPhone theme.
enum WatchColors {
    static let accent = Color(red: 0.671, green: 0.604, blue: 0.980)   // #f2f2ee
    static let onAccent = Color.black
    static let endurance = Color(red: 0.220, green: 0.788, blue: 0.737)
    static let success = Color(red: 0.224, green: 0.776, blue: 0.427) // #39c66d
    static let warning = Color(red: 0.941, green: 0.635, blue: 0.231) // #f0a23b
    static let danger = Color(red: 1.0, green: 0.357, blue: 0.357)    // #ff5b5b

    static let surface = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.5)
}
