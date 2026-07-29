import SwiftUI

// watchOS is always presented against a dark canvas, so Shift's monochrome
// action colour resolves to an off-white rather than the old purple accent.
enum WatchColors {
    static let accent = Color(red: 0.949, green: 0.949, blue: 0.933)   // #f2f2ee
    static let success = Color(red: 0.224, green: 0.776, blue: 0.427) // #39c66d
    static let warning = Color(red: 0.941, green: 0.635, blue: 0.231) // #f0a23b
    static let danger = Color(red: 1.0, green: 0.357, blue: 0.357)    // #ff5b5b

    static let surface = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.5)
}
