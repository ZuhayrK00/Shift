import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    var body: some View {
        Group {
            if authManager.isLoading {
                loadingView
            } else if authManager.session == nil {
                SignInView()
            } else {
                MainTabView()
                    .task {
                        // pullReferenceData and pullUserData both flush the queue internally
                        _ = try? await SyncService.pullReferenceData()
                        try? await SyncService.pullUserData()
                        // Auto-read weight from HealthKit if enabled and no weight is set
                        await autoReadHealthKitWeightIfNeeded()
                        // Prefetch all exercise images early so they're instant everywhere
                        if let exercises = try? await ExerciseService.listExercises() {
                            let urls = exercises.compactMap { $0.imageUrl.flatMap(URL.init) }
                            ImageCache.shared.prefetch(urls)
                        }
                    }
            }
        }
    }

    private func autoReadHealthKitWeightIfNeeded() async {
        guard let user = authManager.user,
              user.settings.healthKit.syncBodyWeight,
              (user.weight == nil || user.weight == 0),
              let weightKg = await HealthKitService.readLatestBodyWeight(),
              let userId = try? authManager.requireUserId() else { return }

        let unit = user.settings.weightUnit
        let displayWeight: Double
        if unit == "lbs" {
            displayWeight = (weightKg * 2.20462 * 10).rounded() / 10
        } else {
            displayWeight = (weightKg * 10).rounded() / 10
        }

        _ = try? await ProfileService.updateProfile(ProfilePatch(weight: displayWeight))
        let entry = WeightEntry(
            id: UUID().uuidString.lowercased(),
            userId: userId,
            weight: displayWeight,
            unit: unit,
            source: "healthkit",
            recordedAt: Date()
        )
        _ = try? await WeightEntryService.insert(entry)
        await authManager.refreshUser()
    }

    private var loadingView: some View {
        ZStack {
            colors.accent.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(\.shiftColors) private var colors

    @State private var selectedTab = 0
    @State private var plansPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tag(0)
                .tabItem {
                    Label("Today", systemImage: "house.fill")
                }

            NavigationStack(path: $plansPath) {
                PlansView()
            }
            .tag(1)
            .tabItem {
                Label("Plans", systemImage: "list.bullet.rectangle.fill")
            }

            NavigationStack {
                ExercisesView()
            }
            .tag(2)
            .tabItem {
                Label("Exercises", systemImage: "dumbbell.fill")
            }

            NavigationStack {
                ProfileView()
            }
            .tag(3)
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .tint(colors.accent)
        .onChange(of: selectedTab) { oldTab, _ in
            // Reset Plans nav stack when switching away from it
            if oldTab == 1 && !plansPath.isEmpty {
                plansPath = NavigationPath()
            }
        }
    }
}
