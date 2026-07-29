import SwiftUI
import WidgetKit

/// Overlay modifier that blurs widget content and shows a "Shift Pro" lock when not Pro.
/// Replaces the containerBackground with a dimmed version so the overlay fills edge-to-edge.
struct ProLockedOverlay: ViewModifier {
    let isPro: Bool
    var hasData: Bool = true
    @Environment(\.widgetFamily) var family

    private var isSmall: Bool { family == .systemSmall }

    func body(content: Content) -> some View {
        if isPro && hasData {
            content
        } else if isPro {
            VStack(spacing: isSmall ? 7 : 9) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: isSmall ? 17 : 21, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Open Shift to sync")
                    .font(.system(size: isSmall ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.background, for: .widget)
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

    func proProtected(isPro: Bool, hasData: Bool) -> some View {
        modifier(ProLockedOverlay(isPro: isPro, hasData: hasData))
    }
}
