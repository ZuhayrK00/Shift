import SwiftUI
import GRDB
import UserNotifications
import Supabase
import WatchConnectivity

extension Notification.Name {
    static let shiftOpenTrainingCalendar = Notification.Name("shiftOpenTrainingCalendar")
    static let shiftOpenEndurance = Notification.Name("shiftOpenEndurance")
    static let shiftDeepLinkStartWorkout = Notification.Name("shiftDeepLinkStartWorkout")
    static let shiftDeepLinkOpenWorkout = Notification.Name("shiftDeepLinkOpenWorkout")
    static let shiftShortcutStartNextWorkout = Notification.Name("shiftShortcutStartNextWorkout")
    static let shiftShortcutResumeWorkout = Notification.Name("shiftShortcutResumeWorkout")
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
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        let trainingID = info["trainingSessionId"] as? String
        let activityID = info["enduranceActivityId"] as? String
        let trainingDate = info["trainingDate"] as? String
        if let owner = info["ownerId"] as? String,
           trainingID != nil || activityID != nil {
            await MainActor.run {
                var components = URLComponents(); components.scheme = "shift"; components.host = trainingID != nil ? "training-calendar" : "endurance"
                components.queryItems = [URLQueryItem(name: "owner", value: owner), URLQueryItem(name: "date", value: trainingDate), URLQueryItem(name: "activity", value: activityID)]
                if let url = components.url { TrainingDeepLinkStore.store(url) }
                NotificationCenter.default.post(name: components.host == "training-calendar" ? .shiftOpenTrainingCalendar : .shiftOpenEndurance, object: nil)
            }
            return
        }
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
            Group {
                #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
                if StoreCaptureConfiguration.enabled { StoreCaptureRoot() } else { ContentView() }
                #else
                ContentView()
                #endif
            }
                .environment(authManager)
                .environment(StoreService.shared)
                .preferredColorScheme(preferredScheme)
                .shiftTheme()
                .onOpenURL { url in
                    if url.host == "endurance" {
                        TrainingDeepLinkStore.store(url)
                        let sport = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sport" }?.value
                        NotificationCenter.default.post(name: .shiftOpenEndurance, object: nil, userInfo: ["sport": sport ?? ""])
                    } else if url.host == "training-calendar" {
                        TrainingDeepLinkStore.store(url)
                        NotificationCenter.default.post(name: .shiftOpenTrainingCalendar, object: nil)
                    } else if url.host == "start-workout" {
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
                    await TrainingNotificationService.reconcile()
                    await GoalNotificationService.reconcileMissedTrainingDays()
                    await GoalNotificationService.notifyFrequencyGoalIfReached()
                }
            }
            if newPhase == .background {
                Task { await WidgetDataService.updateSnapshot() }
            }
        }
    }

}
