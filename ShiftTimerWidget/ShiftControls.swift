import AppIntents
import SwiftUI
import WidgetKit

private enum SharedShiftAction: String {
    case startNextWorkout
    case startQuickWorkout
    case startRestTimer
    case resumeWorkout
}

private enum SharedShiftActionStore {
    static func save(_ action: SharedShiftAction, value: Double? = nil) {
        let defaults = UserDefaults(suiteName: "group.com.zuhayrk.shift")
        defaults?.set(action.rawValue, forKey: "shift.shortcut.action")
        if let value {
            defaults?.set(value, forKey: "shift.shortcut.value")
        } else {
            defaults?.removeObject(forKey: "shift.shortcut.value")
        }
    }
}

@available(iOS 18.0, *)
struct ControlStartNextWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Next Workout"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        SharedShiftActionStore.save(.startNextWorkout)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlQuickWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Workout"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        SharedShiftActionStore.save(.startQuickWorkout)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlResumeWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Workout"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        SharedShiftActionStore.save(.resumeWorkout)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlStartRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Rest Timer"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        SharedShiftActionStore.save(.startRestTimer, value: 90)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ShiftStartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zuhayrk.shift.control.next-workout") {
            ControlWidgetButton(action: ControlStartNextWorkoutIntent()) {
                Label("Next Workout", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .displayName("Next Workout")
        .description("Start your next scheduled Shift workout.")
    }
}

@available(iOS 18.0, *)
struct ShiftQuickWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zuhayrk.shift.control.quick-workout") {
            ControlWidgetButton(action: ControlQuickWorkoutIntent()) {
                Label("Quick Workout", systemImage: "bolt.fill")
            }
        }
        .displayName("Quick Workout")
        .description("Start a blank workout.")
    }
}

@available(iOS 18.0, *)
struct ShiftResumeWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zuhayrk.shift.control.resume-workout") {
            ControlWidgetButton(action: ControlResumeWorkoutIntent()) {
                Label("Resume Workout", systemImage: "play.fill")
            }
        }
        .displayName("Resume Workout")
        .description("Return to your active Shift workout.")
    }
}

@available(iOS 18.0, *)
struct ShiftRestTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zuhayrk.shift.control.rest-timer") {
            ControlWidgetButton(action: ControlStartRestIntent()) {
                Label("Rest 90s", systemImage: "timer")
            }
        }
        .displayName("Rest Timer")
        .description("Start a 90-second rest timer.")
    }
}
