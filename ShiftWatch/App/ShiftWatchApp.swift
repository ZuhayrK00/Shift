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
                if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen == "gym" {
                    NavigationStack { WatchWorkoutView() }.task {
                        workoutState.start(sessionId: "capture-watch-gym", name: "Upper body A", planId: "capture-plan-0", startedAt: Date().addingTimeInterval(-1_620), exercises: StoreCaptureWatchData.gymExercises)
                    }
                } else if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen == "sets" {
                    NavigationStack { WatchExerciseLogView(exercise: StoreCaptureWatchData.gymExercises[0]) }.task {
                        workoutState.start(sessionId: "capture-watch-gym", name: "Upper body A", planId: "capture-plan-0", startedAt: Date().addingTimeInterval(-1_620), exercises: StoreCaptureWatchData.gymExercises)
                        workoutState.loggedSetDetails["capture-ex-0"] = [.init(weight: 70, reps: 10), .init(weight: 70, reps: 10)]
                    }
                } else if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen != "home" {
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
