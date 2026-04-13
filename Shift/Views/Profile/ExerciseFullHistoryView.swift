import SwiftUI

/// Standalone exercise history screen with History + Progress tabs.
/// Opened from the Personal Bests list.
struct ExerciseFullHistoryView: View {
    let exercise: Exercise

    @Environment(\.shiftColors) private var colors
    @State private var activeTab: Tab = .history

    enum Tab: String, CaseIterable {
        case history  = "History"
        case progress = "Progress"
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar

                switch activeTab {
                case .history:
                    ExerciseHistoryView(exerciseId: exercise.id)
                case .progress:
                    ExerciseProgressView(exerciseId: exercise.id)
                }
            }
        }
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTab == tab ? colors.text : colors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(activeTab == tab ? colors.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
