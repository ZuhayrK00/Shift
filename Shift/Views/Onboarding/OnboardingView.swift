import SwiftUI
import PhotosUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var step = 0
    @State private var animateIn = false

    // Profile
    @State private var name = ""
    @State private var ageText = ""
    @State private var weightText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?

    // Preferences
    @State private var weightUnit = "kg"
    @State private var distanceUnit = "km"
    @State private var measurementUnit = "cm"
    @State private var defaultIncrement = 2.5
    @State private var theme = "dark"
    @State private var weekStartsOn = "monday"

    // Goals & Workout
    @State private var weeklyGoal: Int? = nil
    @State private var stepGoal: Int? = nil
    @State private var targetWeightText = ""
    @State private var targetWeightDeadline: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var restTimerEnabled = true
    @State private var restTimerDuration = 90

    // Integrations
    @State private var syncWorkouts = false
    @State private var syncBodyWeight = false
    @State private var countExternal = false
    @State private var exerciseGoalReminders = true
    @State private var frequencyReminders = true
    @State private var stepGoalReminders = true
    @State private var progressReminders = true
    @State private var lockPhotos = false

    // Plan
    @State private var planName = ""
    @State private var showExercisePicker = false
    @State private var selectedExercises: [Exercise] = []

    // Saving
    @State private var isSaving = false
    @State private var savedSettings: UserSettings?

    private let totalSteps = 8

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 && step < totalSteps - 1 {
                    progressBar
                        .padding(.top, 8)
                }

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: appTourStep
                    case 2: profileStep
                    case 3: preferencesStep
                    case 4: goalsStep
                    case 5: integrationsStep
                    case 6: planStep
                    default: allSetStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { animateIn = true }
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await handlePhotoPick(newItem) }
        }
        .onChange(of: theme) { _, newTheme in
            // Apply theme instantly without saving
            if var user = authManager.user {
                user.settings.theme = newTheme
                authManager.user = user
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1..<totalSteps - 1, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? colors.accent : colors.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image("ShiftLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .scaleEffect(animateIn ? 1 : 0.5)
                    .opacity(animateIn ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Welcome to Shift")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(colors.text)

                    Text("Your personal workout companion.\nLet's get you set up in a few steps.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }

            Spacer()

            continueButton("Get Started") { step = 1 }

                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(animateIn ? 1 : 0)
        }
    }

    // MARK: - Step 1: App Tour

    private var appTourStep: some View {
        stepLayout(continueTitle: "Continue", onContinue: { step = 2 }) {
            stepHeader(
                icon: "sparkles",
                title: "How Shift Works",
                subtitle: "Here's a quick look at what you can do."
            )

            VStack(spacing: 12) {
                tourCard(
                    icon: "house.fill",
                    color: colors.accent,
                    title: "Today",
                    description: "Your daily hub. See your schedule, start a workout from scratch or from a plan, and track your activity."
                )

                tourCard(
                    icon: "list.bullet.rectangle.fill",
                    color: .orange,
                    title: "Plans",
                    description: "Build reusable workout plans like \"Push Day\" or \"Full Body\". Add exercises, set targets, and organize your routine."
                )

                tourCard(
                    icon: "dumbbell.fill",
                    color: .purple,
                    title: "Exercises",
                    description: "Browse hundreds of exercises by muscle group, equipment, or difficulty. Create custom exercises too."
                )

                tourCard(
                    icon: "person.fill",
                    color: .green,
                    title: "Profile",
                    description: "Track your progress with weight logs, body measurements, and photos. Set goals and customize your settings."
                )
            }
        }
    }

    private func tourCard(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.text)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.muted)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Step 2: Profile

    private var profileStep: some View {
        stepLayout(continueTitle: "Continue", onContinue: { step = 3 }, skipAction: { step = 3 }) {
            stepHeader(
                icon: "person.fill",
                title: "About You",
                subtitle: "Tell us a bit about yourself to personalize your experience."
            )

            // Avatar
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let data = avatarData, let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(colors.surface2)
                                .frame(width: 90, height: 90)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(colors.muted)
                                )
                        }

                        Circle()
                            .fill(colors.accent)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                Spacer()
            }

            VStack(spacing: 16) {
                onboardingField(label: "Name", placeholder: "Your name", text: $name)
                onboardingField(label: "Age", placeholder: "e.g. 25", text: $ageText, keyboard: .numberPad)
                onboardingField(label: "Weight", placeholder: "e.g. 75", text: $weightText, keyboard: .decimalPad, suffix: weightUnit)
            }
        }
    }

    // MARK: - Step 3: Preferences

    private var preferencesStep: some View {
        stepLayout(continueTitle: "Continue", onContinue: { step = 4 }) {
            stepHeader(
                icon: "slider.horizontal.3",
                title: "Preferences",
                subtitle: "Choose your preferred units and display settings."
            )

            VStack(spacing: 20) {
                segmentRow(label: "Weight Unit", options: ["kg", "lbs"], selection: $weightUnit)
                segmentRow(label: "Distance Unit", options: ["km", "mi"], selection: $distanceUnit)
                segmentRow(label: "Measurement Unit", options: ["cm", "in"], selection: $measurementUnit)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Increment")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.text)
                    Picker("", selection: $defaultIncrement) {
                        ForEach([1.0, 1.25, 2.5, 5.0, 10.0], id: \.self) { inc in
                            Text(inc == 1.0 || inc == 5.0 || inc == 10.0
                                 ? String(format: "%.0f", inc)
                                 : String(format: "%.2f", inc))
                                .tag(inc)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                segmentRow(label: "Theme", options: ["dark", "light", "system"], selection: $theme, capitalized: true)
                segmentRow(label: "Week Starts On", options: ["monday", "sunday"], selection: $weekStartsOn, capitalized: true)
            }
        }
    }

    // MARK: - Step 4: Goals & Workout

    private var goalsStep: some View {
        stepLayout(continueTitle: "Continue", onContinue: { step = 5 }, skipAction: { step = 5 }) {
            stepHeader(
                icon: "target",
                title: "Goals & Workout",
                subtitle: "Set your training targets and workout preferences."
            )

            // Weekly frequency
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Workout Goal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.text)
                Text("How many days per week do you want to train?")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                weeklyGoal = weeklyGoal == day ? nil : day
                            }
                        } label: {
                            Text("\(day)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(weeklyGoal == day ? .white : colors.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(weeklyGoal == day ? colors.accent : colors.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(weeklyGoal == day ? colors.accent : colors.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Daily steps
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Step Goal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.text)

                let stepOptions = [5000, 7500, 10000, 12500, 15000]
                HStack(spacing: 8) {
                    ForEach(stepOptions, id: \.self) { val in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                stepGoal = stepGoal == val ? nil : val
                            }
                        } label: {
                            Text(val >= 10000 ? "\(val / 1000)k" : "\(val / 1000).5k")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(stepGoal == val ? .white : colors.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(stepGoal == val ? colors.accent : colors.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(stepGoal == val ? colors.accent : colors.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Weight goal
            VStack(alignment: .leading, spacing: 12) {
                Text("Weight Goal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.text)
                Text("Optional — set a target weight to work towards.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        TextField("e.g. 75", text: $targetWeightText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(colors.text)
                        Text(weightUnit)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    DatePicker("", selection: $targetWeightDeadline,
                               in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...,
                               displayedComponents: .date)
                        .labelsHidden()
                        .tint(colors.accent)
                }
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Rest timer
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Rest Timer")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.text)
                    Spacer()
                    Toggle("", isOn: $restTimerEnabled)
                        .tint(colors.accent)
                        .labelsHidden()
                }

                if restTimerEnabled {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
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
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Step 5: Integrations

    private var integrationsStep: some View {
        stepLayout(continueTitle: "Continue", onContinue: { step = 6 }, skipAction: { step = 6 }) {
            stepHeader(
                icon: "gearshape.2.fill",
                title: "Integrations & Privacy",
                subtitle: "Connect services and set up your privacy preferences."
            )

            // Health
            if HealthKitService.isAvailable {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.text)

                    toggleRow(icon: "figure.strengthtraining.traditional", label: "Save workouts to Health", isOn: $syncWorkouts)
                    toggleRow(icon: "scalemass", label: "Sync body weight", isOn: $syncBodyWeight)
                    toggleRow(icon: "arrow.triangle.2.circlepath", label: "Count external workouts", isOn: $countExternal)
                }
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Notifications
            VStack(alignment: .leading, spacing: 12) {
                Label("Notifications", systemImage: "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)

                toggleRow(icon: "dumbbell.fill", label: "Exercise goal reminders", isOn: $exerciseGoalReminders)
                toggleRow(icon: "flame.fill", label: "Frequency reminders", isOn: $frequencyReminders)
                toggleRow(icon: "figure.walk", label: "Step goal reminders", isOn: $stepGoalReminders)
                toggleRow(icon: "chart.line.uptrend.xyaxis", label: "Progress reminders", isOn: $progressReminders)
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Privacy
            VStack(alignment: .leading, spacing: 12) {
                Label("Privacy", systemImage: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)

                toggleRow(icon: "faceid", label: "Lock progress photos", isOn: $lockPhotos)
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Step 6: First Plan

    private var planStep: some View {
        stepLayout(
            continueTitle: planName.isEmpty ? "Skip" : "Create Plan",
            onContinue: { Task { await finishOnboarding() } },
            skipAction: !planName.isEmpty ? {
                planName = ""
                selectedExercises = []
                Task { await finishOnboarding() }
            } : nil
        ) {
            stepHeader(
                icon: "list.bullet.rectangle.fill",
                title: "Your First Plan",
                subtitle: "Create a workout plan to get started. You can always change this later."
            )

            VStack(spacing: 16) {
                onboardingField(label: "Plan Name", placeholder: "e.g. Push Day, Full Body A", text: $planName)

                // Selected exercises
                if !selectedExercises.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercises (\(selectedExercises.count))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.text)

                        ForEach(selectedExercises, id: \.id) { exercise in
                            HStack(spacing: 12) {
                                AnimatedExerciseImage(imageUrl: exercise.imageUrl, exerciseName: exercise.name)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(colors.text)
                                        .lineLimit(1)
                                    if let muscle = exercise.bodyPart ?? exercise.category {
                                        Text(muscle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(colors.muted)
                                    }
                                }

                                Spacer()

                                Button {
                                    selectedExercises.removeAll { $0.id == exercise.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(colors.muted)
                                        .frame(width: 28, height: 28)
                                        .background(colors.surface2)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Add exercises button
                Button {
                    showExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text(selectedExercises.isEmpty ? "Add Exercises" : "Add More Exercises")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(colors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePicker(isPresented: $showExercisePicker) { exercises, _ in
                for ex in exercises where !selectedExercises.contains(where: { $0.id == ex.id }) {
                    selectedExercises.append(ex)
                }
            }
        }
    }

    // MARK: - Step 7: All Set

    private var allSetStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(colors.success.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(colors.success)
                }

                VStack(spacing: 8) {
                    Text("You're All Set!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(colors.text)

                    Text("Your workspace is ready.\nTime to start training.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            continueButton("Start Training") {
                Task { await completeOnboarding() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Shared Components

    private func stepLayout(
        continueTitle: String,
        onContinue: @escaping () -> Void,
        skipAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            VStack(spacing: 0) {
                Divider()
                    .overlay(colors.border)

                VStack(spacing: 4) {
                    continueButton(continueTitle, action: onContinue)

                    if let skipAction {
                        skipButton(action: skipAction)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(colors.bg)
        }
    }

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(colors.accent)
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(colors.text)

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(colors.muted)
                .lineSpacing(3)
        }
    }

    private func onboardingField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        suffix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.text)

            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .font(.system(size: 16))
                    .foregroundStyle(colors.text)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.muted)
                }
            }
            .padding(14)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }

    private func segmentRow(label: String, options: [String], selection: Binding<String>, capitalized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.text)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) {
                    Text(capitalized ? $0.capitalized : $0)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(colors.accent)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(colors.accent)
                .labelsHidden()
        }
    }

    private func continueButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [colors.accent, colors.accent.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func skipButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text("Skip")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        avatarData = jpegData
    }

    // MARK: - Save & Finish

    private func finishOnboarding() async {
        isSaving = true

        // Build settings
        var settings = authManager.user?.settings ?? .default
        settings.weightUnit = weightUnit
        settings.defaultWeightIncrement = defaultIncrement
        settings.distanceUnit = distanceUnit
        settings.measurementUnit = measurementUnit
        settings.weekStartsOn = weekStartsOn
        settings.theme = theme
        settings.restTimer = RestTimerSettings(enabled: restTimerEnabled, durationSeconds: restTimerDuration)
        settings.weeklyFrequencyGoal = weeklyGoal
        settings.dailyStepGoal = stepGoal
        settings.notifications = {
            var n = NotificationSettings()
            n.exerciseGoalReminders = exerciseGoalReminders
            n.frequencyReminders = frequencyReminders
            n.stepGoalReminders = stepGoalReminders
            n.progressReminders = progressReminders
            return n
        }()
        settings.healthKit = HealthKitSettings(
            syncWorkouts: syncWorkouts,
            syncBodyWeight: syncBodyWeight,
            countExternalWorkouts: countExternal
        )
        settings.lockPhotos = lockPhotos

        // Request HealthKit authorization if any toggle enabled
        if syncWorkouts || syncBodyWeight || countExternal {
            _ = try? await HealthKitService.requestAuthorization()
        }

        // Save profile
        // Save weight goal to settings if provided
        if let tw = Double(targetWeightText), tw > 0 {
            settings.targetWeight = tw
            settings.targetWeightDeadline = ISO8601DateFormatter.shared.string(from: targetWeightDeadline)
        }

        let parsedAge = Int(ageText)
        let parsedWeight = Double(weightText)
        var patch = ProfilePatch(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
            age: parsedAge.flatMap { (1...120).contains($0) ? $0 : nil },
            weight: parsedWeight.flatMap { $0 > 0 ? $0 : nil },
            settings: settings
        )

        // Upload avatar
        if let data = avatarData, let userId = authManager.currentUserId {
            let url = try? await ProfileService.uploadProfilePicture(imageData: data, userId: userId)
            patch.profilePictureUrl = url
        }

        _ = try? await ProfileService.updateProfile(patch)
        savedSettings = settings

        // Create plan if name provided
        if !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let plan = try? await PlanService.createPlan(name: planName.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if !selectedExercises.isEmpty {
                    _ = try? await PlanService.addExercises(
                        planId: plan.id,
                        exerciseIds: selectedExercises.map(\.id)
                    )
                }
            }
        }

        // Schedule notifications
        Task { await GoalNotificationService.scheduleAllNotifications() }

        isSaving = false
        step = totalSteps - 1
    }

    private func completeOnboarding() async {
        var settings = savedSettings ?? authManager.user?.settings ?? .default
        settings.hasCompletedOnboarding = true
        _ = try? await ProfileService.updateSettings(settings)
        await authManager.refreshUser()
    }
}
