import SwiftUI

struct TrainingCalendarGrid: View {
    @Environment(\.shiftColors) private var colors
    @Binding var selected: Date
    var sessions: [TrainingSession]
    var activities: [EnduranceActivity]
    var workouts: [WorkoutSession]
    var weekStartsOn: String
    var weeklySchedule: TrainingScheduleSettings
    @State private var month = Date()
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = weekStartsOn == "sunday" ? 1 : 2; return value }
    private var start: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var offset: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: start)?.count ?? 30 }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Previous month", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                Spacer()
                Text(start.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(colors.muted)
                }
                ForEach(0..<(offset + count), id: \.self) { index in
                    if index < offset { Color.clear.frame(height: 48) }
                    else if let date = calendar.date(byAdding: .day, value: index - offset, to: start) { day(date) }
                }
            }
            HStack(spacing: 16) {
                legend("Gym", colors.accent); legend("Endurance", colors.enduranceAccent); legend("Complete", colors.success)
            }
            Button("Today") { selected = Date(); month = selected }.font(.subheadline.weight(.semibold))
        }.enduranceCard().onAppear { month = selected }
            .onChange(of: selected) { _, value in if !calendar.isDate(value, equalTo: month, toGranularity: .month) { month = value } }
    }
    private func day(_ date: Date) -> some View {
        let planned = sessions.filter { $0.status == .scheduled && calendar.isDate($0.scheduledAt, inSameDayAs: date) }
        let completed = activities.contains { calendar.isDate($0.startedAt, inSameDayAs: date) }
            || workouts.contains { calendar.isDate($0.startedAt, inSameDayAs: date) }
        let selectedDay = calendar.isDate(selected, inSameDayAs: date)
        return Button { selected = date } label: {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: date))").font(.system(size: 15, weight: selectedDay ? .bold : .medium))
                    .foregroundStyle(selectedDay ? colors.onAccent : colors.text)
                    .frame(width: 30, height: 30).background(selectedDay ? colors.accent : .clear, in: Circle())
                HStack(spacing: 3) {
                    if planned.contains(where: { $0.kind == .strength }) { Circle().fill(colors.accent).frame(width: 4, height: 4) }
                    if planned.contains(where: { $0.kind == .endurance }) { Circle().fill(colors.enduranceAccent).frame(width: 4, height: 4) }
                    if completed { Circle().fill(colors.success).frame(width: 4, height: 4) }
                }.frame(height: 4)
            }.frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue("\(planned.count) planned sessions\(completed ? ", completed training" : "")")
            .accessibilityAddTraits(selectedDay ? .isSelected : [])
    }
    private func move(_ direction: Int) { if let date = calendar.date(byAdding: .month, value: direction, to: start) { month = date } }
    private func legend(_ title: String, _ color: Color) -> some View { HStack(spacing: 4) { Circle().fill(color).frame(width: 5, height: 5); Text(title).font(.caption2).foregroundStyle(colors.muted) } }
}
