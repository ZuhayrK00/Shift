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
                        SyncService.flushInBackground()
                        try? await SyncService.pullReferenceData()
                        // Prefetch all exercise images early so they're instant everywhere
                        if let exercises = try? await ExerciseService.listExercises() {
                            let urls = exercises.compactMap { $0.imageUrl.flatMap(URL.init) }
                            ImageCache.shared.prefetch(urls)
                        }
                    }
            }
        }
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
