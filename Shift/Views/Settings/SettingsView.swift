import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)?

    // About you
    @State private var name = ""
    @State private var ageText = ""
    @State private var weightText = ""

    // Preferences
    @State private var weightUnit = "kg"
    @State private var defaultIncrement = 2.5
    @State private var distanceUnit = "km"
    @State private var weekStartsOn = "monday"
    @State private var theme = "dark"

    // Rest timer
    @State private var restTimerEnabled = true
    @State private var restTimerDuration = 90

    // Sync
    @State private var lastSyncedText = "Never"

    // UI State
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSignOutAlert = false
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?

    private let weightUnits = ["kg", "lbs"]
    private let distanceUnits = ["km", "mi"]
    private let weekDays = ["monday", "sunday"]
    private let themes = ["dark", "light", "system"]
    private let increments = [1.0, 1.25, 2.5, 5.0, 10.0]

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Form {
                avatarSection
                aboutSection
                preferencesSection
                restTimerSection
                syncSection
                signOutSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
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
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authManager.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .onAppear {
            populateFields()
            if let syncDate = SyncService.getLastSyncedAt() {
                lastSyncedText = formatDate(syncDate)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await handlePhotoPick(newItem) }
        }
    }

    // MARK: - Avatar section

    @ViewBuilder
    private var avatarSection: some View {
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
    }

    // MARK: - About section

    @ViewBuilder
    private var aboutSection: some View {
        Section("About You") {
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
            LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField("e.g. 80", text: $weightText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(colors.text)
                    Text(weightUnit)
                        .foregroundStyle(colors.muted)
                        .font(.system(size: 13))
                }
            }
        }
        .listRowBackground(colors.surface)
        .foregroundStyle(colors.text)
    }

    // MARK: - Preferences section

    @ViewBuilder
    private var preferencesSection: some View {
        Section("Preferences") {
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
    }

    // MARK: - Rest timer section

    @ViewBuilder
    private var restTimerSection: some View {
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
    }

    // MARK: - Sync section

    @ViewBuilder
    private var syncSection: some View {
        Section("Sync") {
            HStack {
                Text("Last synced")
                    .foregroundStyle(colors.text)
                Spacer()
                Text(lastSyncedText)
                    .foregroundStyle(colors.muted)
                    .font(.system(size: 13))
            }

            Button {
                Task {
                    try? await SyncService.pullReferenceData()
                    lastSyncedText = formatDate(Date())
                }
            } label: {
                Label("Pull reference data", systemImage: "arrow.down.circle")
                    .foregroundStyle(colors.accent)
            }

            Button {
                Task {
                    SyncService.flushInBackground()
                    lastSyncedText = formatDate(Date())
                }
            } label: {
                Label("Push pending changes", systemImage: "arrow.up.circle")
                    .foregroundStyle(colors.accent)
            }
        }
        .listRowBackground(colors.surface)
    }

    // MARK: - Sign out section

    @ViewBuilder
    private var signOutSection: some View {
        Section {
            if let saveError {
                Text(saveError)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.danger)
            }

            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                HStack {
                    Spacer()
                    Text("Sign out")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
            }
        }
        .listRowBackground(colors.surface)
    }

    // MARK: - Actions

    private func populateFields() {
        guard let user = authManager.user else { return }
        name = user.name ?? ""
        ageText = user.age.map { "\($0)" } ?? ""
        weightText = user.weight.map {
            $0.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", $0) : "\($0)"
        } ?? ""
        let s = user.settings
        weightUnit = s.weightUnit
        defaultIncrement = s.defaultWeightIncrement
        distanceUnit = s.distanceUnit
        weekStartsOn = s.weekStartsOn
        theme = s.theme
        restTimerEnabled = s.restTimer.enabled
        restTimerDuration = s.restTimer.durationSeconds
    }

    private func save() async {
        guard authManager.currentUserId != nil else { return }
        isSaving = true
        saveError = nil

        let settings = UserSettings(
            weightUnit: weightUnit,
            defaultWeightIncrement: defaultIncrement,
            distanceUnit: distanceUnit,
            weekStartsOn: weekStartsOn,
            theme: theme,
            restTimer: RestTimerSettings(
                enabled: restTimerEnabled,
                durationSeconds: restTimerDuration
            )
        )

        var patch = ProfilePatch(
            name: name.isEmpty ? nil : name,
            age: Int(ageText),
            weight: Double(weightText),
            settings: settings
        )

        // Upload avatar first if the user picked a new photo
        if let data = avatarData, let userId = authManager.currentUserId {
            do {
                let url = try await ProfileService.uploadProfilePicture(imageData: data, userId: userId)
                patch.profilePictureUrl = url
            } catch {
                // Avatar upload failed but don't block the rest of the save
            }
        }

        // Save locally — this should always succeed
        do {
            try await ProfileService.updateProfile(patch)
        } catch {
            // Even if enqueue/sync fails, the local write likely succeeded.
            // Don't block the user.
        }

        await authManager.refreshUser()
        isSaving = false
        onSaved?()
        dismiss()
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        avatarData = try? await item.loadTransferable(type: Data.self)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
