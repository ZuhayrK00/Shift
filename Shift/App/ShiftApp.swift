import SwiftUI
import GRDB
import UserNotifications
import Supabase

extension Notification.Name {
    static let shiftDeepLinkStartWorkout = Notification.Name("shiftDeepLinkStartWorkout")
}

// MARK: - Notification Delegate

class ShiftNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == NotificationManager.finishWorkoutAction {
            let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
            if let sessionId {
                try? await WorkoutService.finishSession(sessionId)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - App entry point

@main
struct ShiftApp: App {
    @State private var authManager = AuthManager()
    private let notificationDelegate = ShiftNotificationDelegate()

    // Ensure the database is opened before any view appears.
    private let database = AppDatabase.shared

    init() {
        setAuthManager(authManager)
        NotificationManager.requestPermissionIfNeeded()
        NotificationManager.registerCategories()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        HealthKitService.enableStepCountBackgroundDelivery()
        Task { await GoalNotificationService.scheduleAllNotifications() }
    }

    private var preferredScheme: ColorScheme? {
        switch authManager.user?.settings.theme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil  // "system" or nil → follow system
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .preferredColorScheme(preferredScheme)
                .shiftTheme()
                .onOpenURL { url in
                    if url.host == "start-workout" {
                        NotificationCenter.default.post(name: .shiftDeepLinkStartWorkout, object: nil)
                    } else {
                        supabase.auth.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await GoalNotificationService.checkAndNotifyGoalCompletion() }
                Task { await WidgetDataService.updateSnapshot() }
            }
        }
    }
}
