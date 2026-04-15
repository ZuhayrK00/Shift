import SwiftUI
import PhotosUI
import LocalAuthentication

// MARK: - Settings Hub

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var showSignOutAlert = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            List {
                // Profile
                Section {
                    NavigationLink {
                        ProfileSettingsPage(onSaved: onSaved)
                    } label: {
                        settingsRow(
                            icon: "person.fill",
                            iconColor: colors.accent,
                            title: "Profile",
                            subtitle: "Name, email, age, photo"
                        )
                    }
                }
                .listRowBackground(colors.surface)

                // Preferences & Workout
                Section {
                    NavigationLink {
                        PreferencesSettingsPage(onSaved: onSaved)
                    } label: {
                        settingsRow(
                            icon: "slider.horizontal.3",
                            iconColor: colors.accent2,
                            title: "Preferences",
                            subtitle: "Units, theme, week start"
                        )
                    }

                    NavigationLink {
                        WorkoutSettingsPage(onSaved: onSaved)
                    } label: {
                        settingsRow(
                            icon: "timer",
                            iconColor: colors.warning,
                            title: "Workout",
                            subtitle: "Rest timer"
                        )
                    }

                    NavigationLink {
                        NotificationSettingsPage(onSaved: onSaved)
                    } label: {
                        settingsRow(
                            icon: "bell.fill",
                            iconColor: colors.danger,
                            title: "Notifications",
                            subtitle: "Goal & frequency reminders"
                        )
                    }

                    NavigationLink {
                        PrivacySettingsPage(onSaved: onSaved)
                    } label: {
                        settingsRow(
                            icon: "lock.fill",
                            iconColor: .green,
                            title: "Privacy",
                            subtitle: "Photo lock"
                        )
                    }
                }
                .listRowBackground(colors.surface)

                // Data
                Section {
                    if HealthKitService.isAvailable {
                        NavigationLink {
                            HealthSettingsPage(onSaved: onSaved)
                        } label: {
                            settingsRow(
                                icon: "heart.fill",
                                iconColor: .pink,
                                title: "Health",
                                subtitle: "Apple Health integration"
                            )
                        }
                    }

                }
                .listRowBackground(colors.surface)

                // Sign out
                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                }
                .listRowBackground(colors.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authManager.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Settings Page

private struct ProfileSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var email = ""
    @State private var name = ""
    @State private var ageText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var emailSuccess: String?

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ZStack {
                                    if let data = avatarData, let uiImg = UIImage(data: data) {
                                        Image(uiImage: uiImg)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                    } else {
                                        AvatarView(
                                            url: authManager.user?.profilePictureUrl,
                                            initials: authManager.user?.initials ?? "?",
                                            size: 80
                                        )
                                    }

                                    Circle()
                                        .fill(colors.accent)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.white)
                                        )
                                        .offset(x: 28, y: 28)
                                }

                                Text("Change photo")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.accent)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listRowBackground(colors.surface)

                Section("Details") {
                    LabeledContent("Email") {
                        TextField("your@email.com", text: $email)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(colors.text)
                    }
                    LabeledContent("Name") {
                        TextField("Your name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(colors.text)
                    }
                    LabeledContent("Age") {
                        TextField("e.g. 28", text: $ageText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .foregroundStyle(colors.text)
                    }
                }
                .listRowBackground(colors.surface)
                .foregroundStyle(colors.text)

                if let emailSuccess {
                    Section {
                        Text(emailSuccess)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.success)
                    }
                    .listRowBackground(colors.surface)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving || !isValidEmail)
            }
        }
        .onAppear { populateFields() }
        .onChange(of: photoItem) { _, newItem in
            Task { await handlePhotoPick(newItem) }
        }
    }

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".") else { return false }
        return true
    }

    private func populateFields() {
        guard let user = authManager.user else { return }
        email = user.email ?? ""
        name = user.name ?? ""
        ageText = user.age.map { "\($0)" } ?? ""
    }

    private func save() async {
        isSaving = true
        saveError = nil
        emailSuccess = nil

        // Handle email change if different from current
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentEmail = (authManager.user?.email ?? "").lowercased()
        if !trimmedEmail.isEmpty && trimmedEmail != currentEmail {
            do {
                try await authManager.updateEmail(trimmedEmail)
                emailSuccess = "A confirmation link has been sent to \(trimmedEmail). Check your inbox to verify the change."
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("already registered")
                    || message.localizedCaseInsensitiveContains("already been registered")
                    || message.localizedCaseInsensitiveContains("email address is already") {
                    saveError = "An account with that email already exists. Please use a different email."
                } else {
                    saveError = "Failed to update email: \(message)"
                }
                isSaving = false
                return
            }
        }

        let parsedAge = Int(ageText)
        var patch = ProfilePatch(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
            age: parsedAge.flatMap { (1...120).contains($0) ? $0 : nil }
        )

        if let data = avatarData, let userId = authManager.currentUserId {
            do {
                let url = try await ProfileService.uploadProfilePicture(imageData: data, userId: userId)
                patch.profilePictureUrl = url
            } catch {
                saveError = "Photo upload failed: \(error.localizedDescription)"
                isSaving = false
                return
            }
        }

        do {
            _ = try await ProfileService.updateProfile(patch)
        } catch {
            saveError = "Failed to save profile: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        isSaving = false

        // If email was changed, stay on the page to show the confirmation message
        if emailSuccess != nil {
            return
        }
        onSaved?()
        dismiss()
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        avatarData = jpegData
    }
}

// MARK: - Preferences Settings Page

private struct PreferencesSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var weightUnit = "kg"
    @State private var defaultIncrement = 2.5
    @State private var distanceUnit = "km"
    @State private var measurementUnit = "cm"
    @State private var weekStartsOn = "monday"
    @State private var theme = "dark"
    @State private var isSaving = false
    @State private var saveError: String?

    private let weightUnits = ["kg", "lbs"]
    private let distanceUnits = ["km", "mi"]
    private let measurementUnits = ["cm", "in"]
    private let weekDays = ["monday", "sunday"]
    private let themes = ["dark", "light", "system"]
    private let increments = [1.0, 1.25, 2.5, 5.0, 10.0]

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section("Units") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight unit")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $weightUnit) {
                            ForEach(weightUnits, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default increment")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $defaultIncrement) {
                            ForEach(increments, id: \.self) { inc in
                                Text("\(inc, specifier: inc == 1.0 || inc == 5.0 || inc == 10.0 ? "%.0f" : "%.2f")")
                                    .tag(inc)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distance unit")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $distanceUnit) {
                            ForEach(distanceUnits, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Measurement unit")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $measurementUnit) {
                            ForEach(measurementUnits, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(colors.surface)
                .foregroundStyle(colors.text)

                Section("General") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Week starts on")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $weekStartsOn) {
                            ForEach(weekDays, id: \.self) { Text($0.capitalized) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Theme")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                        Picker("", selection: $theme) {
                            ForEach(themes, id: \.self) { Text($0.capitalized) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(colors.surface)
                .foregroundStyle(colors.text)

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            let s = authManager.user?.settings ?? .default
            weightUnit = s.weightUnit
            defaultIncrement = s.defaultWeightIncrement
            distanceUnit = s.distanceUnit
            measurementUnit = s.measurementUnit
            weekStartsOn = s.weekStartsOn
            theme = s.theme
        }
    }

    private func save() async {
        isSaving = true
        var settings = authManager.user?.settings ?? .default
        settings.weightUnit = weightUnit
        settings.defaultWeightIncrement = defaultIncrement
        settings.distanceUnit = distanceUnit
        settings.measurementUnit = measurementUnit
        settings.weekStartsOn = weekStartsOn
        settings.theme = theme
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        isSaving = false
        onSaved?()
        dismiss()
    }
}

// MARK: - Workout Settings Page

private struct WorkoutSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var restTimerEnabled = true
    @State private var restTimerDuration = 90
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section("Rest Timer") {
                    Toggle("Enable rest timer", isOn: $restTimerEnabled)
                        .tint(colors.accent)

                    if restTimerEnabled {
                        HStack {
                            Text("Duration")
                                .foregroundStyle(colors.text)
                            Spacer()
                            Text(formatDuration(restTimerDuration))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .frame(width: 60, alignment: .trailing)
                            Stepper("", value: $restTimerDuration, in: 5...600, step: 15)
                                .labelsHidden()
                        }
                    }
                }
                .listRowBackground(colors.surface)
                .foregroundStyle(colors.text)

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            let s = authManager.user?.settings ?? .default
            restTimerEnabled = s.restTimer.enabled
            restTimerDuration = s.restTimer.durationSeconds
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.restTimer = RestTimerSettings(
            enabled: restTimerEnabled,
            durationSeconds: restTimerDuration
        )
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

// MARK: - Notification Settings Page

private struct NotificationSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var exerciseGoalReminders = true
    @State private var frequencyReminders = true
    @State private var stepGoalReminders = true
    @State private var progressReminders = true
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section("Goal Reminders") {
                    Toggle("Exercise goal reminders", isOn: $exerciseGoalReminders)
                        .tint(colors.accent)

                    Toggle("Frequency reminders", isOn: $frequencyReminders)
                        .tint(colors.accent)

                    Toggle("Step goal reminders", isOn: $stepGoalReminders)
                        .tint(colors.accent)

                    Toggle("Progress reminders", isOn: $progressReminders)
                        .tint(colors.accent)
                }
                .listRowBackground(colors.surface)
                .foregroundStyle(colors.text)

                Section {
                    Text("When enabled, you'll receive notifications to help you stay on track with your exercise weight goals, weekly gym frequency targets, daily step goals, and progress tracking.")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                }
                .listRowBackground(colors.surface)

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            let s = authManager.user?.settings ?? .default
            exerciseGoalReminders = s.notifications.exerciseGoalReminders
            frequencyReminders = s.notifications.frequencyReminders
            stepGoalReminders = s.notifications.stepGoalReminders
            progressReminders = s.notifications.progressReminders
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        var notifs = NotificationSettings()
        notifs.exerciseGoalReminders = exerciseGoalReminders
        notifs.frequencyReminders = frequencyReminders
        notifs.stepGoalReminders = stepGoalReminders
        notifs.progressReminders = progressReminders
        settings.notifications = notifs
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        Task { await GoalNotificationService.scheduleAllNotifications() }
        isSaving = false
        onSaved?()
        dismiss()
    }
}

// MARK: - Health Settings Page

private struct HealthSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var syncWorkouts = false
    @State private var syncBodyWeight = false
    @State private var countExternal = false
    @State private var isSaving = false
    @State private var showAuthAlert = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section {
                    Toggle(isOn: $syncWorkouts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save workouts to Health")
                                .foregroundStyle(colors.text)
                            Text("Completed sessions appear in Apple Health")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.muted)
                        }
                    }
                    .tint(colors.accent)
                } header: {
                    Text("Workouts")
                }
                .listRowBackground(colors.surface)

                Section {
                    Toggle(isOn: $syncBodyWeight) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync body weight")
                                .foregroundStyle(colors.text)
                            Text("Read from smart scales, write when you update")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.muted)
                        }
                    }
                    .tint(colors.accent)
                } header: {
                    Text("Body Weight")
                }
                .listRowBackground(colors.surface)

                Section {
                    Toggle(isOn: $countExternal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Count external workouts")
                                .foregroundStyle(colors.text)
                            Text("Include strength workouts from other apps in your weekly goal")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.muted)
                        }
                    }
                    .tint(colors.accent)
                } header: {
                    Text("Goals")
                }
                .listRowBackground(colors.surface)

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear { populateFields() }
        .alert("Health Access Required", isPresented: $showAuthAlert) {
            Button("OK") {}
        } message: {
            Text("Enable Health access for Shift in Settings > Privacy & Security > Health.")
        }
    }

    private func populateFields() {
        let hk = authManager.user?.settings.healthKit ?? .init()
        syncWorkouts = hk.syncWorkouts
        syncBodyWeight = hk.syncBodyWeight
        countExternal = hk.countExternalWorkouts
    }

    private func save() async {
        isSaving = true

        // Request authorization if any toggle is being enabled
        let wasEnabled = authManager.user?.settings.healthKit ?? .init()
        let needsAuth = (!wasEnabled.syncWorkouts && syncWorkouts)
            || (!wasEnabled.syncBodyWeight && syncBodyWeight)
            || (!wasEnabled.countExternalWorkouts && countExternal)

        if needsAuth {
            do {
                try await HealthKitService.requestAuthorization()
            } catch {
                showAuthAlert = true
                isSaving = false
                return
            }
        }

        var settings = authManager.user?.settings ?? .default
        settings.healthKit.syncWorkouts = syncWorkouts
        settings.healthKit.syncBodyWeight = syncBodyWeight
        settings.healthKit.countExternalWorkouts = countExternal

        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }

        // Auto-read weight from HealthKit when body weight sync is newly enabled
        if !wasEnabled.syncBodyWeight && syncBodyWeight {
            await autoReadHealthKitWeight(settings: settings)
        }

        await authManager.refreshUser()
        isSaving = false
        onSaved?()
        dismiss()
    }

    /// Reads the latest body weight from HealthKit and saves it to the profile + weight log.
    private func autoReadHealthKitWeight(settings: UserSettings) async {
        guard let weightKg = await HealthKitService.readLatestBodyWeight(),
              let userId = try? authManager.requireUserId() else { return }

        // Convert to user's preferred unit
        let displayWeight: Double
        let unit = settings.weightUnit
        if unit == "lbs" {
            displayWeight = (weightKg * 2.20462 * 10).rounded() / 10
        } else {
            displayWeight = (weightKg * 10).rounded() / 10
        }

        // Update profile weight
        _ = try? await ProfileService.updateProfile(ProfilePatch(weight: displayWeight))

        // Log a weight entry
        let entry = WeightEntry(
            id: UUID().uuidString.lowercased(),
            userId: userId,
            weight: displayWeight,
            unit: unit,
            source: "healthkit",
            recordedAt: Date()
        )
        _ = try? await WeightEntryService.insert(entry)
    }
}

// MARK: - Privacy Settings Page

private struct PrivacySettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    @State private var lockPhotos = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showAuthFailedAlert = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { lockPhotos },
                        set: { newValue in
                            if !newValue && lockPhotos {
                                // Turning off — require authentication first
                                authenticateToUnlock()
                            } else {
                                lockPhotos = newValue
                            }
                        }
                    )) {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lock Photos")
                                    .font(.system(size: 15))
                                    .foregroundStyle(colors.text)
                                Text("Require Face ID to view photos")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.muted)
                            }
                        }
                    }
                    .tint(colors.accent)
                }
                .listRowBackground(colors.surface)

                Section {
                    Text("When enabled, the Photos tab in Progress will require Face ID or your device passcode to access.")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                }
                .listRowBackground(colors.surface)

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                    }
                    .listRowBackground(colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            let s = authManager.user?.settings ?? .default
            lockPhotos = s.lockPhotos
        }
        .alert("Authentication Failed", isPresented: $showAuthFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not verify your identity. The photo lock will remain enabled.")
        }
    }

    private func authenticateToUnlock() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to disable photo lock"
            ) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        lockPhotos = false
                    } else {
                        showAuthFailedAlert = true
                    }
                }
            }
        } else {
            // No biometrics or passcode available — allow toggle
            lockPhotos = false
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        var settings = authManager.user?.settings ?? .default
        settings.lockPhotos = lockPhotos
        do {
            _ = try await ProfileService.updateSettings(settings)
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return
        }
        await authManager.refreshUser()
        isSaving = false
        onSaved?()
        dismiss()
    }
}

