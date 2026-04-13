import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var personalBests: [PersonalBest] = []
    @State private var isLoadingPBs = false
    @State private var showAllPBs = false
    @State private var showSettings = false

    private var user: User? { authManager.user }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header row
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Personal bests card
                    personalBestsCard
                        .padding(.horizontal, 16)

                    // Attribution
                    Text("Shift · Built with SwiftUI")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.muted.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(colors.muted)
                }
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .navigationDestination(isPresented: $showAllPBs) {
            PersonalBestsView()
        }
        .task { await loadPersonalBests() }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 14) {
            // Avatar
            AvatarView(
                url: user?.profilePictureUrl,
                initials: user?.initials ?? "?",
                size: 72
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Hi, \(user?.displayName ?? "there")")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(colors.text)

                if let email = user?.email {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Text("Edit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Personal bests card

    @ViewBuilder
    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Personal Bests")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.text)
                Spacer()
                Button {
                    showAllPBs = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if isLoadingPBs {
                ProgressView()
                    .tint(colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if personalBests.isEmpty {
                Text("Complete workouts to see your records.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(personalBests.prefix(3).enumerated()), id: \.element.exerciseId) { index, pb in
                        ProfilePBRow(pb: pb, rank: index)
                    }
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadPersonalBests() async {
        isLoadingPBs = true
        personalBests = (try? await ExerciseService.getPersonalBests(limit: 5)) ?? []
        isLoadingPBs = false
    }
}

// MARK: - ProfilePBRow

private struct ProfilePBRow: View {
    @Environment(\.shiftColors) private var colors
    let pb: PersonalBest
    let rank: Int

    private var rankColor: Color {
        switch rank {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 1: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 2: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return colors.muted
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(rank + 1)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rankColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pb.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Text(pb.achievedAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            Text(formattedWeight)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var formattedWeight: String {
        let val = pb.maxWeight
        return val == val.rounded() ? "\(Int(val)) kg" : "\(val) kg"
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    @Environment(\.shiftColors) private var colors
    let url: String?
    let initials: String
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = url, let imgUrl = URL(string: urlString) {
                AsyncImage(url: imgUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(colors.accent)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
