import SwiftUI

// MARK: - WeekCalendar

/// Horizontally paged week view. One page = 7 days.
/// Dot indicators: green = completed, orange = in-progress, red = missed.
struct WeekCalendar: View {
    @Binding var selected: Date
    var completedDates: Set<String>   = []
    var inProgressDates: Set<String>  = []
    var weekStartsOn: String          = "monday"  // "monday" | "sunday"

    @Environment(\.shiftColors) private var colors

    // Page index relative to the "anchor" week (the week containing today).
    @State private var pageIndex: Int = 0

    private let today = Calendar.current.startOfDay(for: Date())

    // Week offset from the anchor week that contains `selected`.
    private var initialPage: Int {
        let cal = Calendar.current
        let anchor = weekStart(for: today)
        let selWeek = weekStart(for: selected)
        return cal.dateComponents([.weekOfYear], from: anchor, to: selWeek).weekOfYear ?? 0
    }

    var body: some View {
        TabView(selection: $pageIndex) {
            // Render ±8 weeks for practical scrolling
            ForEach(-8 ... 8, id: \.self) { offset in
                weekRow(for: offset)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 80)
        .onAppear { pageIndex = initialPage }
    }

    // MARK: - Week row

    @ViewBuilder
    private func weekRow(for weekOffset: Int) -> some View {
        let days = daysForWeek(offset: weekOffset)
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(for: day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(for day: Date) -> some View {
        let key     = toLocalDateKey(day)
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let isFuture = day > today
        let dotColor = dotIndicatorColor(key: key, day: day)

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selected = day
            }
        } label: {
            VStack(spacing: 4) {
                // Day-of-week letter
                Text(dayLetter(for: day))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? colors.accent : colors.muted)

                // Day number circle
                ZStack {
                    if isSelected {
                        Circle().fill(colors.accent)
                    } else if isToday {
                        Circle().stroke(colors.accent, lineWidth: 1.5)
                    }
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: 15, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(
                            isSelected
                                ? .white
                                : isFuture ? colors.muted : colors.text
                        )
                }
                .frame(width: 34, height: 34)

                // Dot indicator
                if let color = dotColor {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                } else {
                    Spacer().frame(height: 5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func daysForWeek(offset: Int) -> [Date] {
        let cal = Calendar.current
        let anchor = weekStart(for: today)
        guard let weekAnchor = cal.date(byAdding: .weekOfYear, value: offset, to: anchor) else {
            return []
        }
        return (0 ..< 7).compactMap { cal.date(byAdding: .day, value: $0, to: weekAnchor) }
    }

    /// Returns the Monday (or Sunday) that starts the week containing `date`.
    private func weekStart(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOn == "sunday" ? 1 : 2
        return cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: date)
                  .date ?? date
    }

    private func dayLetter(for date: Date) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let weekday = Calendar.current.component(.weekday, from: date) // 1=Sun
        return letters[(weekday - 1) % 7]
    }

    private func dotIndicatorColor(key: String, day: Date) -> Color? {
        if completedDates.contains(key)  { return colors.success }
        if inProgressDates.contains(key) { return colors.warning }
        // Missed: past day, no session
        if day < today && !completedDates.contains(key) && !inProgressDates.contains(key) {
            return nil  // Don't show red dot for every empty past day — too noisy
        }
        return nil
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selected = Date()
    let completed: Set<String> = [toLocalDateKey(Date().addingTimeInterval(-86400))]
    let inProgress: Set<String> = [toLocalDateKey(Date())]

    WeekCalendar(
        selected: $selected,
        completedDates: completed,
        inProgressDates: inProgress
    )
    .background(Color(hex: "#0b0b0f"))
    .shiftTheme()
}
