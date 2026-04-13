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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .shiftTheme()
        }
    }
}
