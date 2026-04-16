import SwiftUI

@main
struct ShiftWatchApp: App {
    @State private var sessionManager = WatchSessionManager.shared
    @State private var workoutState = WatchWorkoutState()

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(sessionManager)
                .environment(workoutState)
        }
    }
}
