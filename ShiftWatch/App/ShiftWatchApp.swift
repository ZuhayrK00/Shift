import SwiftUI
import WatchKit

@main
struct ShiftWatchApp: App {
    @WKApplicationDelegateAdaptor(ShiftWatchDelegate.self) private var appDelegate
    @State private var sessionManager = WatchSessionManager.shared
    @State private var workoutState = WatchWorkoutState()

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
                if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen != "home" {
                    NavigationStack { WatchEnduranceView() }.task {
                        if StoreCaptureConfiguration.screen == "recording" { WatchEnduranceRecorder.shared.loadStoreCapture() }
                    }
                } else { WatchHomeView() }
                #else
                WatchHomeView()
                #endif
            }
                .environment(sessionManager)
                .environment(workoutState)
        }
    }
}

final class ShiftWatchDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchEnduranceRecorder.shared.recover() }
    }
}
