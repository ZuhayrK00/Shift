import Foundation
import UIKit

/// Shared singleton that manages the rest timer countdown.
/// Lives outside the view hierarchy so the timer survives navigation.
@Observable
final class RestTimerManager {
    static let shared = RestTimerManager()

    private(set) var isActive = false
    private(set) var remaining: Int = 0
    private(set) var duration: Int = 0
    private var timer: Timer?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(remaining) / Double(duration)
    }

    var timeText: String {
        let mins = remaining / 60
        let secs = remaining % 60
        return mins > 0
            ? String(format: "%d:%02d", mins, secs)
            : String(secs)
    }

    private init() {}

    func start(seconds: Int) {
        stop()
        duration = seconds
        remaining = seconds
        isActive = true
        LiveActivityManager.start(durationSeconds: seconds)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.fireCompletionHaptics()
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isActive {
            LiveActivityManager.stop()
        }
        isActive = false
        remaining = 0
        duration = 0
    }

    private func fireCompletionHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            generator.impactOccurred()
        }
    }
}
