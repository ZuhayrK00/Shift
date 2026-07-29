import AppIntents
import Foundation

enum ShiftShortcutAction: String {
    case startNextWorkout
    case startQuickWorkout
    case showToday
    case logWeight
    case startRestTimer
    case resumeWorkout
}

enum ShiftShortcutStore {
    private static let actionKey = "shift.shortcut.action"
    private static let valueKey = "shift.shortcut.value"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.zuhayrk.shift") ?? .standard
    }

    static func save(_ action: ShiftShortcutAction, value: Double? = nil) {
        defaults.set(action.rawValue, forKey: actionKey)
        if let value {
            defaults.set(value, forKey: valueKey)
        } else {
            defaults.removeObject(forKey: valueKey)
        }
    }

    static func consume() -> (action: ShiftShortcutAction, value: Double?)? {
        guard let raw = defaults.string(forKey: actionKey),
              let action = ShiftShortcutAction(rawValue: raw) else { return nil }
        let value = defaults.object(forKey: valueKey) as? Double
        defaults.removeObject(forKey: actionKey)
        defaults.removeObject(forKey: valueKey)
        return (action, value)
    }
}

struct StartNextShiftWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Next Shift Workout"
    static var description = IntentDescription("Opens Shift and starts the next workout in your active program.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        ShiftShortcutStore.save(.startNextWorkout)
        return .result()
    }
}

struct StartQuickShiftWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Quick Shift Workout"
    static var description = IntentDescription("Opens a blank workout in Shift.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        ShiftShortcutStore.save(.startQuickWorkout)
        return .result()
    }
}

struct ShowShiftTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Today in Shift"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        ShiftShortcutStore.save(.showToday)
        return .result()
    }
}

struct LogShiftWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight in Shift"
    static var description = IntentDescription("Logs body weight using your current Shift unit.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Weight")
    var weight: Double

    init() {}

    init(weight: Double) {
        self.weight = weight
    }

    func perform() async throws -> some IntentResult {
        ShiftShortcutStore.save(.logWeight, value: weight)
        return .result()
    }
}

struct StartShiftRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Shift Rest Timer"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Seconds", default: 90, inclusiveRange: (10, 3600))
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        ShiftShortcutStore.save(.startRestTimer, value: Double(seconds))
        return .result()
    }
}

struct ShiftAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNextShiftWorkoutIntent(),
            phrases: [
                "Start my next workout in \(.applicationName)",
                "Train with \(.applicationName)"
            ],
            shortTitle: "Next Workout",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StartQuickShiftWorkoutIntent(),
            phrases: ["Start a quick workout in \(.applicationName)"],
            shortTitle: "Quick Workout",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: LogShiftWeightIntent(),
            phrases: ["Log my weight in \(.applicationName)"],
            shortTitle: "Log Weight",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: StartShiftRestTimerIntent(),
            phrases: ["Start a rest timer in \(.applicationName)"],
            shortTitle: "Rest Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: ShowShiftTodayIntent(),
            phrases: ["Show today in \(.applicationName)"],
            shortTitle: "Show Today",
            systemImageName: "house.fill"
        )
    }
}
