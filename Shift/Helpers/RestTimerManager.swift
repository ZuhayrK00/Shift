import Foundation
import UIKit

/// Shared singleton that manages the rest timer countdown.
/// Lives outside the view hierarchy so the timer survives navigation.
/// Uses wall-clock `endTime` so the timer stays accurate across background/foreground transitions.
@Observable
final class RestTimerManager {
    static let shared = RestTimerManager()

    private(set) var isActive = false
    private(set) var remaining: Int = 0
    private(set) var duration: Int = 0
    private var timer: Timer?
    private var endTime: Date?

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

    private init() {
        // Recalculate remaining time when app returns to foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.recalculateRemaining()
            // Timer expired while app was in background — clean up
            if self.isActive && self.remaining <= 0 {
                self.fireCompletionHaptics()
                self.stop()
            }
            // Clean up any zombie Live Activities that outlived the timer
            if !self.isActive {
                LiveActivityManager.endAllActivities()
            }
        }
    }

    func start(seconds: Int) {
        stop()
        duration = seconds
        remaining = seconds
        endTime = Date().addingTimeInterval(Double(seconds))
        isActive = true
        LiveActivityManager.start(durationSeconds: seconds)
        NotificationManager.scheduleRestTimerNotification(seconds: seconds)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recalculateRemaining()
            if self.remaining <= 0 {
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
            NotificationManager.cancelRestTimerNotification()
        }
        isActive = false
        remaining = 0
        duration = 0
        endTime = nil
    }

    /// Recalculates `remaining` from wall-clock `endTime`.
    /// Called on each tick and when the app returns to foreground.
    private func recalculateRemaining() {
        guard let endTime else { return }
        let diff = Int(ceil(endTime.timeIntervalSinceNow))
        remaining = max(0, diff)
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
