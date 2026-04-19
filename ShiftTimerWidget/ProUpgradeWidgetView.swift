import SwiftUI
import WidgetKit

/// Overlay modifier that blurs widget content and shows a "Shift Pro" lock when not Pro.
/// Replaces the containerBackground with a dimmed version so the overlay fills edge-to-edge.
struct ProLockedOverlay: ViewModifier {
    let isPro: Bool
    @Environment(\.widgetFamily) var family

    private var isSmall: Bool { family == .systemSmall }

    func body(content: Content) -> some View {
        if isPro {
            content
        } else {
            VStack(spacing: isSmall ? 8 : 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: isSmall ? 18 : 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Shift Pro")
                    .font(.system(size: isSmall ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .containerBackground(for: .widget) {
                ZStack {
                    // Render original content as background, blurred
                    content
                        .blur(radius: 14)
                    // Dark tint over the entire widget
                    Color.black.opacity(0.55)
                }
            }
        }
    }
}

extension View {
    func proLocked(_ isPro: Bool) -> some View {
        modifier(ProLockedOverlay(isPro: isPro))
    }
}
