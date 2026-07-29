import SwiftUI

@MainActor
@Observable
final class AppErrorCenter {
    static let shared = AppErrorCenter()
    var message: String?

    func present(_ error: Error) {
        message = error.localizedDescription
    }
}

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var onboardingCheckDone = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if authManager.isLoading {
                loadingView
            } else if authManager.session == nil {
                NavigationStack {
                    SignInView()
                }
            } else if authManager.user == nil {
                // Wait for loadUser to finish before checking onboarding
                loadingView
            } else if !onboardingCheckDone {
                loadingView
                    .task { await checkOnboardingNeeded() }
            } else if showOnboarding {
                OnboardingView()
                    .task {
                        // Pull reference data so exercise picker works during onboarding
                        _ = try? await SyncService.pullReferenceData()
                    }
            } else {
                MainTabView()
                    .task {
                        let pullReference = SyncService.shouldPullReferenceData()
                        let pullUser = SyncService.shouldPullUserData()
                        if pullReference && pullUser {
                            async let referenceSync = SyncService.pullReferenceData()
                            async let userSync: Void = SyncService.pullUserData()
                            _ = try? await referenceSync
                            _ = try? await userSync
                        } else if pullReference {
                            _ = try? await SyncService.pullReferenceData()
                        } else if pullUser {
                            try? await SyncService.pullUserData()
                        } else {
                            SyncService.flushInBackground()
                        }
                        // Auto-read weight from HealthKit if enabled and no weight is set
                        await autoReadHealthKitWeightIfNeeded()
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { authManager.showPasswordReset },
            set: { authManager.showPasswordReset = $0 }
        )) {
            ResetPasswordSheet()
                .environment(authManager)
        }
        .onChange(of: authManager.currentUserId) { _, _ in
            // Reset onboarding state when user changes (sign out → sign in, or account deletion)
            onboardingCheckDone = false
            showOnboarding = false
        }
        .onChange(of: authManager.user?.settings.hasCompletedOnboarding) { _, newValue in
            if newValue == true {
                showOnboarding = false
            }
        }
        .task(id: authManager.user?.id) {
            guard authManager.user != nil else { return }
            await GoalNotificationService.prepareForCurrentUser()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { AppErrorCenter.shared.message != nil },
            set: { if !$0 { AppErrorCenter.shared.message = nil } }
        )) {
            Button("OK", role: .cancel) { AppErrorCenter.shared.message = nil }
        } message: {
            Text(AppErrorCenter.shared.message ?? "Please try again.")
        }
    }

    private func checkOnboardingNeeded() async {
        guard let user = authManager.user else {
            onboardingCheckDone = true
            return
        }

        // Already completed — skip
        if user.settings.hasCompletedOnboarding {
            onboardingCheckDone = true
            return
        }

        // Check if this is an existing user with data (sessions or plans)
        if let userId = try? authManager.requireUserId() {
            let sessions = (try? await SessionRepository.findCompleted(userId: userId)) ?? []
            let plans = (try? await PlanService.listPlans()) ?? []

            if !sessions.isEmpty || !plans.isEmpty {
                // Existing user — auto-mark onboarding complete, skip it
                var settings = user.settings
                settings.hasCompletedOnboarding = true
                _ = try? await ProfileService.updateSettings(settings)
                await authManager.refreshUser()
                onboardingCheckDone = true
                return
            }
        }

        // New user — show onboarding
        showOnboarding = true
        onboardingCheckDone = true
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
            Color(hex: "#050505").ignoresSafeArea()
            VStack(spacing: 16) {
                Image("ShiftLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .environment(\.colorScheme, .dark)
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
    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase

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
        .onReceive(NotificationCenter.default.publisher(for: .shiftDeepLinkOpenWorkout)) { _ in
            selectedTab = 0
        }
        .task {
            await Task.yield()
            if let pending = ShiftShortcutStore.consume() {
                await handleShortcut(pending.action, value: pending.value)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let pending = ShiftShortcutStore.consume() else { return }
            Task { await handleShortcut(pending.action, value: pending.value) }
        }
    }

    @MainActor
    private func handleShortcut(_ action: ShiftShortcutAction, value: Double?) async {
        switch action {
        case .startNextWorkout:
            selectedTab = 0
            NotificationCenter.default.post(name: .shiftShortcutStartNextWorkout, object: nil)
        case .startQuickWorkout:
            selectedTab = 0
            NotificationCenter.default.post(name: .shiftDeepLinkStartWorkout, object: nil)
        case .showToday:
            selectedTab = 0
        case .resumeWorkout:
            selectedTab = 0
            NotificationCenter.default.post(name: .shiftShortcutResumeWorkout, object: nil)
        case .startRestTimer:
            selectedTab = 0
            let seconds = min(3600, max(10, Int(value ?? 90)))
            RestTimerManager.shared.start(seconds: seconds)
        case .logWeight:
            guard let value, value > 0,
                  let userID = authManager.currentUserId else { return }
            do {
                let unit = authManager.user?.settings.weightUnit ?? "kg"
                try await WeightEntryService.insert(WeightEntry(
                    id: UUID().uuidString.lowercased(),
                    userId: userID,
                    weight: value,
                    unit: unit,
                    source: "shortcut",
                    recordedAt: Date()
                ))
                try await ProfileService.updateProfile(ProfilePatch(weight: value))
                if authManager.user?.settings.healthKit.syncBodyWeight == true {
                    let kilograms = unit == "lbs" ? value / 2.20462 : value
                    _ = try? await HealthKitService.writeBodyWeight(kilograms, date: Date())
                }
                await authManager.refreshUser()
                selectedTab = 3
            } catch {
                AppErrorCenter.shared.present(error)
            }
        }
    }
}

// MARK: - Reset Password Sheet

struct ResetPasswordSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "lock.rotation")
                                .font(.system(size: 40))
                                .foregroundStyle(colors.accent)
                                .padding(.bottom, 8)

                            Text("Set New Password")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(colors.text)

                            Text("Enter your new password below.")
                                .font(.system(size: 16))
                                .foregroundStyle(colors.muted)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 32)

                        if success {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Password updated successfully!")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(colors.text)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 16)

                            Button {
                                dismiss()
                            } label: {
                                Text("Done")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(colors.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(colors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else {
                            VStack(spacing: 12) {
                                ShiftSecureField(placeholder: "New password", text: $newPassword)
                                ShiftSecureField(placeholder: "Confirm password", text: $confirmPassword)
                            }
                            .padding(.bottom, 8)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.danger)
                                    .padding(.bottom, 8)
                            }

                            Button {
                                Task { await updatePassword() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoading {
                                        ProgressView()
                                            .tint(colors.onAccent)
                                            .scaleEffect(0.8)
                                    }
                                    Text("Update Password")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(colors.onAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(isValid ? colors.accent : colors.accent.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!isValid || isLoading)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !success {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(colors.muted)
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }

    private func updatePassword() async {
        isLoading = true
        errorMessage = nil

        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            isLoading = false
            return
        }

        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            isLoading = false
            return
        }

        do {
            try await authManager.updatePassword(newPassword)
            success = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
                authManager.showPasswordReset = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
