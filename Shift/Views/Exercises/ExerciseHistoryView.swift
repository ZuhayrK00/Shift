import SwiftUI

// MARK: - ExerciseHistoryView

/// Shows all past sessions for an exercise, grouped by date, newest first.
struct ExerciseHistoryView: View {
    let exerciseId: String

    @Environment(\.shiftColors) private var colors

    @State private var sessions: [HistorySession] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading {
                loadingView
            } else if sessions.isEmpty {
                emptyView
            } else {
                sessionList
            }
        }
        .task { await load() }
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    sessionCard(session)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Session card

    @ViewBuilder
    private func sessionCard(_ session: HistorySession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                Text(relativeLabel(for: session.date))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider()
                .background(colors.border)
                .padding(.top, 8)

            // Set rows
            VStack(spacing: 0) {
                let completedSets = session.sets.filter { $0.isCompleted }
                ForEach(completedSets) { set in
                    setRow(set)
                }
            }

            Spacer().frame(height: 10)
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Set row

    @ViewBuilder
    private func setRow(_ set: SessionSet) -> some View {
        HStack(spacing: 10) {
            SetBadge(set: set, compact: true)

            let weightText: String = {
                if let w = set.weight {
                    return w.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f kg", w) : String(format: "%.1f kg", w)
                }
                return "Bodyweight"
            }()

            Text(weightText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)

            Text("×")
                .font(.system(size: 12))
                .foregroundStyle(colors.muted)

            Text(pluralise(set.reps, "rep"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Empty / loading

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(colors.muted)
            Text("No history yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("Sets you log will appear here after you finish a workout.")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().tint(colors.accent)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func load() async {
        loading = true
        defer { loading = false }
        sessions = (try? await ExerciseHistoryService.getHistory(exerciseId)) ?? []
    }

    private func relativeLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }
}

// MARK: - Preview

#Preview {
    ExerciseHistoryView(exerciseId: "exercise-1")
        .background(Color(hex: "#0b0b0f"))
        .shiftTheme()
}
