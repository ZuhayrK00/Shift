import SwiftUI
import GRDB

// MARK: - App entry point

@main
struct ShiftApp: App {
    @State private var authManager = AuthManager()

    // Ensure the database is opened before any view appears.
    private let database = AppDatabase.shared

    init() {
        setAuthManager(authManager)
        NotificationManager.requestPermissionIfNeeded()
        Task { await GoalNotificationService.scheduleAllNotifications() }
    }

    private var preferredScheme: ColorScheme? {
        switch authManager.user?.settings.theme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil  // "system" or nil → follow system
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .preferredColorScheme(preferredScheme)
                .shiftTheme()
        }
    }
}
