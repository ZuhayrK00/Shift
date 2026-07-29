import SwiftUI
import GRDB
import UserNotifications
import Supabase
import WatchConnectivity

extension Notification.Name {
    static let shiftDeepLinkStartWorkout = Notification.Name("shiftDeepLinkStartWorkout")
    static let shiftDeepLinkOpenWorkout = Notification.Name("shiftDeepLinkOpenWorkout")
    static let shiftShortcutStartNextWorkout = Notification.Name("shiftShortcutStartNextWorkout")
}

enum ShiftDeepLinkStore {
    private static let workoutKey = "shift.deepLink.workoutSessionId"

    static func storeWorkoutSessionId(_ sessionId: String) {
        UserDefaults.standard.set(sessionId, forKey: workoutKey)
    }

    static func consumeWorkoutSessionId() -> String? {
        let sessionId = UserDefaults.standard.string(forKey: workoutKey)
        UserDefaults.standard.removeObject(forKey: workoutKey)
        return sessionId
    }
}

// MARK: - Notification Delegate

class ShiftNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let isOpenAction = response.actionIdentifier == NotificationManager.openWorkoutAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard isOpenAction,
              let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        else { return }

        await MainActor.run {
            ShiftDeepLinkStore.storeWorkoutSessionId(sessionId)
            NotificationCenter.default.post(
                name: .shiftDeepLinkOpenWorkout,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["shiftNotificationKind"] as? String == "achievement" {
            return [.banner]
        }
        return [.banner, .sound]
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
        NotificationManager.registerCategories()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        HealthKitService.configureBackgroundDelivery()
        PhoneSessionManager.shared.activate()
        Task { await NotificationManager.removeLegacyGoalNotifications() }
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
                .environment(StoreService.shared)
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
                Task {
                    await StoreService.shared.updatePurchasedProducts(syncWatch: false)
                    await WidgetDataService.updateSnapshot(
                        knownProStatus: StoreService.shared.isPro
                    )
                    PhoneSessionManager.shared.sendContextToWatch()
                    await GoalNotificationService.checkAndNotifyGoalCompletion()
                    await GoalNotificationService.notifyFrequencyGoalIfReached()
                }
            }
            if newPhase == .background {
                Task { await WidgetDataService.updateSnapshot() }
            }
        }
    }

}
