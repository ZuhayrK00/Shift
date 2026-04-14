import SwiftUI

struct PersonalBestsView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }

    @State private var personalBests: [PersonalBest] = []
    @State private var isLoading = false
    @State private var exerciseMap: [String: Exercise] = [:]

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView()
                        .tint(colors.accent)
                } else if personalBests.isEmpty {
                    emptyState
                } else {
                    pbList
                }
            }
        }
        .navigationTitle("Personal Bests")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadData() }
    }

    // MARK: - PB list

    private var pbList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(personalBests.enumerated()), id: \.element.exerciseId) { index, pb in
                    NavigationLink {
                        if let exercise = exerciseMap[pb.exerciseId] {
                            ExerciseFullHistoryView(exercise: exercise)
                        }
                    } label: {
                        pbCard(pb, rank: index)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func pbCard(_ pb: PersonalBest, rank: Int) -> some View {
        HStack(spacing: 14) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor(rank).opacity(0.15))
                    .frame(width: 40, height: 40)
                Text("\(rank + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(rankColor(rank))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pb.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Text(pb.achievedAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            Text(formattedWeight(pb.maxWeight))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(colors.accent)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundStyle(colors.muted)

            Text("No records yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.text)

            Text("Complete workouts to start tracking your personal bests.")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        personalBests = (try? await ExerciseService.getPersonalBests(limit: 100)) ?? []
        let ids = personalBests.map { $0.exerciseId }
        exerciseMap = (try? await ExerciseService.getByIds(ids)) ?? [:]
        isLoading = false
    }

    private func formattedWeight(_ val: Double) -> String {
        formatWeight(val, unit: weightUnit)
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0)   // gold
        case 1: return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 2: return Color(red: 0.80, green: 0.50, blue: 0.20) // bronze
        default: return colors.muted
        }
    }
}

