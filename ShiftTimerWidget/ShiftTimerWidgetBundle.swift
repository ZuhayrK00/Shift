import SwiftUI
import WidgetKit

@main
struct ShiftTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
        TodaysActivityWidget()
        StepCounterWidget()
        WeeklyProgressWidget()
        StreakCounterWidget()
        QuickStartWidget()
        if #available(iOS 18.0, *) {
            ShiftStartWorkoutControl()
            ShiftQuickWorkoutControl()
            ShiftResumeWorkoutControl()
            ShiftRestTimerControl()
        }
    }
}
