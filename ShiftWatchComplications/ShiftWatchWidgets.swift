import SwiftUI
import WidgetKit

@main
struct ShiftWatchWidgets: WidgetBundle {
    var body: some Widget {
        StepComplication()
        WorkoutComplication()
    }
}
