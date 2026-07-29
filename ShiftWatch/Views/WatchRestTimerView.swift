import SwiftUI
import WatchKit
import UserNotifications

struct WatchRestTimerView: View {
    let duration: Int

    @Environment(\.dismiss) private var dismiss

    @State private var remaining: Int = 0
    @State private var timer: Timer?
    @State private var endTime: Date?
    @State private var notificationToken = UUID()

    private let notificationIdentifier = "shift.watch.rest-timer-complete"

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(remaining) / Double(duration)
    }

    private var timeText: String {
        let mins = remaining / 60
        let secs = remaining % 60
        return mins > 0
            ? String(format: "%d:%02d", mins, secs)
            : "\(secs)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WatchColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)

                VStack(spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("rest")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            Spacer()

            Button {
                cleanup(cancelNotification: true)
                dismiss()
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { start() }
        .onDisappear {
            // The view timer can stop, but the system-owned notification must
            // remain so rest completion still works after navigation/suspension.
            timer?.invalidate()
            timer = nil
        }
    }

    private func start() {
        if let endTime {
            let resumedRemaining = Int(ceil(endTime.timeIntervalSinceNow))
            guard resumedRemaining > 0 else {
                cleanup(cancelNotification: true)
                dismiss()
                return
            }
            remaining = resumedRemaining
            startTicker()
            return
        }

        remaining = duration
        endTime = Date().addingTimeInterval(Double(duration))
        scheduleCompletionNotification()
        startTicker()
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let endTime else { return }
                let diff = Int(ceil(endTime.timeIntervalSinceNow))
                remaining = max(0, diff)

                if remaining <= 0 {
                    cleanup(cancelNotification: true)
                    WKInterfaceDevice.current().play(.notification)
                    dismiss()
                }
            }
        }
    }

    private func cleanup(cancelNotification: Bool) {
        timer?.invalidate()
        timer = nil
        if cancelNotification {
            notificationToken = UUID()
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        }
    }

    private func scheduleCompletionNotification() {
        let token = UUID()
        notificationToken = token
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])

        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let updatedSettings = await center.notificationSettings()
            guard [.authorized, .provisional].contains(updatedSettings.authorizationStatus),
                  notificationToken == token else { return }

            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Ready for your next set?"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(max(duration, 1)),
                    repeats: false
                )
            )
            try? await center.add(request)

            if notificationToken != token {
                center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
                center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
            }
        }
    }
}
