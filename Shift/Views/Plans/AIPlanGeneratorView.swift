import SwiftUI
import Speech

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Enums

@available(iOS 26, *)
enum AIGoalType: String, CaseIterable, Identifiable {
    case buildMuscle = "Build Muscle"
    case increaseStrength = "Increase Strength"
    case toneAndDefine = "Tone & Define"
    case generalFitness = "General Fitness"
    case improveEndurance = "Improve Endurance"
    case athleticPerformance = "Athletic Performance"
    case rehabilitation = "Return to Training"
    case bodyRecomposition = "Body Recomposition"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .buildMuscle: return "figure.strengthtraining.traditional"
        case .increaseStrength: return "dumbbell.fill"
        case .toneAndDefine: return "figure.mixed.cardio"
        case .generalFitness: return "heart.fill"
        case .improveEndurance: return "figure.run"
        case .athleticPerformance: return "sportscourt.fill"
        case .rehabilitation: return "cross.case.fill"
        case .bodyRecomposition: return "arrow.triangle.2.circlepath"
        }
    }
}

@available(iOS 26, *)
enum AIActivityLevel: String, CaseIterable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
}

@available(iOS 26, *)
enum AIExperienceLevel: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var description: String {
        switch self {
        case .beginner: return "New to the gym or less than 6 months"
        case .intermediate: return "1-3 years of consistent training"
        case .advanced: return "3+ years, comfortable with all movements"
        }
    }
}

// MARK: - Voice Preferences

@available(iOS 26, *)
struct VoicePreferences: Equatable {
    var muscleGroupNames: [String]  // e.g. ["chest", "back"]
    var equipmentNames: [String]    // e.g. ["dumbbell"]
    var timeBudget: Int?            // minutes
    var avoidPatterns: [String]
    var injuryNotes: [String]       // e.g. ["back injury - light", "shoulder recovering"]

    var isEmpty: Bool {
        muscleGroupNames.isEmpty && equipmentNames.isEmpty && timeBudget == nil && avoidPatterns.isEmpty && injuryNotes.isEmpty
    }

    static let empty = VoicePreferences(muscleGroupNames: [], equipmentNames: [], timeBudget: nil, avoidPatterns: [], injuryNotes: [])
}

@available(iOS 26, *)
private struct AIDraftExerciseLocation: Identifiable {
    var dayIndex: Int
    var exerciseIndex: Int
    var id: String { "\(dayIndex)-\(exerciseIndex)" }
}

// MARK: - AIPlanGeneratorView

@available(iOS 26, *)
struct AIPlanGeneratorView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var quickSession: Bool = false
    var onSaved: ((Int) -> Void)?

    @State private var currentStep = 0
    @State private var goalType: AIGoalType? = nil
    @State private var daysPerWeek = 4
    @State private var activityLevel: AIActivityLevel = .moderatelyActive
    @State private var experienceLevel: AIExperienceLevel = .intermediate
    @State private var muscleGroups: [MuscleGroup] = []
    @State private var selectedMuscleGroupIds: Set<String> = []
    @State private var allExercises: [Exercise] = []
    @State private var allEquipmentTypes: [String] = []
    @State private var selectedEquipment: Set<String> = []
    @State private var recentExerciseIds: Set<String> = []
    @State private var timeBudgetMinutes: Int? = nil
    @State private var personalNotes = ""
    @State private var parsedVoicePrefs: VoicePreferences = .empty
    @State private var showManualFilters = false
    @State private var generatedPlan: GeneratedPlan?
    @State private var generationRepairs: [String] = []
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var planName = ""
    @State private var isRecording = false
    @State private var audioEngine = AVAudioEngine()
    @State private var speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var editingDraftExercise: AIDraftExerciseLocation?
    @State private var replacingDraftExercise: AIDraftExerciseLocation?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationAttemptID: UUID?
    @State private var pendingDraft: AIPlanDraftSnapshot?
    @State private var showRestoreDraft = false
    @State private var lastGenerationRequest: AIPlanGenerationRequest?
    @State private var progressionRecommendations: [String: ProgressionRecommendation] = [:]
    @State private var useProgressionRecommendations = false

    private let totalSteps = 5

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    let progress = Double(currentStep) / Double(totalSteps - 1)
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(colors.border)
                            .frame(height: 3)
                        Rectangle()
                            .fill(colors.accent)
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .frame(height: 3)

                // Content
                Group {
                    switch currentStep {
                    case 0: goalStep
                    case 1: scheduleStep
                    case 2: focusStep
                    case 3: generatingStep
                    case 4: reviewStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                // Sticky continue/generate button
                if currentStep < 3 && (!quickSession || currentStep >= 2) {
                    VStack(spacing: 0) {
                        Divider().foregroundStyle(colors.border)
                        continueButton(
                            label: currentStep == 2 ? (quickSession ? "Build Workout" : "Build Program") : "Continue",
                            disabled: currentStep == 2 && selectedMuscleGroupIds.isEmpty && parsedVoicePrefs.muscleGroupNames.isEmpty
                        ) {
                            if currentStep == 2 {
                                if isRecording { stopRecording() }
                                parseCurrentVoicePrefs()
                                currentStep = 3
                                startGeneration()
                            } else {
                                currentStep += 1
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                    .background(colors.bg)
                }
            }
        }
        .navigationTitle(quickSession ? "Quick Workout" : "Build a Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if currentStep > (quickSession ? 2 : 0) && currentStep < 3 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .foregroundStyle(colors.muted)
                }
            }
        }
        .task {
            muscleGroups = (try? await MuscleGroupRepository.findAll()) ?? []
            selectedMuscleGroupIds = Set(muscleGroups.map(\.id))
            allExercises = (try? await ExerciseRepository.findAll()) ?? []

            // Equipment types
            allEquipmentTypes = Array(Set(allExercises.compactMap(\.equipment))).sorted()
            selectedEquipment = Set(allEquipmentTypes)

            // Recently used exercises for history-aware selection
            if let userId = authManager.user?.id {
                recentExerciseIds = Set((try? await SessionSetRepository.findRecentlyUsedExerciseIds(userId: userId)) ?? [])
            }

            if quickSession {
                daysPerWeek = 1
                currentStep = 2
            }
            if let userID = authManager.currentUserId,
               let snapshot = AIPlanDraftStore.load(userID: userID, quickSession: quickSession) {
                pendingDraft = snapshot
                showRestoreDraft = true
            }
        }
        .onDisappear {
            generationAttemptID = nil
            generationTask?.cancel()
            if isRecording { stopRecording() }
        }
        .alert("Continue your draft?", isPresented: $showRestoreDraft) {
            Button("Continue") {
                if let snapshot = pendingDraft {
                    generatedPlan = snapshot.plan
                    planName = snapshot.plan.planName
                    currentStep = 4
                    Task { await loadProgressionRecommendations() }
                }
                pendingDraft = nil
            }
            Button("Discard", role: .destructive) {
                clearCachedDraft()
                pendingDraft = nil
            }
        } message: {
            Text("Shift kept the unsaved draft from your previous visit.")
        }
        .sheet(item: $editingDraftExercise) { location in
            if let exercise = generatedExercise(at: location) {
                AIDraftTargetsSheet(exercise: exercise) { updated in
                    updateGeneratedExercise(updated, at: location)
                }
            }
        }
        .sheet(item: $replacingDraftExercise) { location in
            if let generated = generatedExercise(at: location),
               let current = allExercises.first(where: { $0.id == generated.exerciseID }) {
                AIExerciseReplacementSheet(
                    current: current,
                    suggestions: replacementSuggestions(for: current)
                ) { replacement in
                    replaceGeneratedExercise(at: location, with: replacement)
                }
            }
        }
    }

    // MARK: - Step 0: Goal

    private var goalStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHeader(icon: "target", title: "Your Goal", subtitle: "What are you working towards?")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(AIGoalType.allCases) { goal in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                goalType = goalType == goal ? nil : goal
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: goal.icon)
                                    .font(.system(size: 22))
                                Text(goal.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(goalType == goal ? colors.onAccent : colors.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)
                            .background(goalType == goal ? colors.accent : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(goalType == goal ? colors.accent : colors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .padding(20)
        }
    }

    // MARK: - Step 1: Schedule & Experience

    private var scheduleStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHeader(icon: "calendar", title: "Schedule & Experience", subtitle: "How often can you train?")

                // Days per week
                VStack(alignment: .leading, spacing: 12) {
                    Text("Training Days Per Week")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.text)
                    HStack(spacing: 8) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    daysPerWeek = day
                                }
                            } label: {
                                Text("\(day)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(daysPerWeek == day ? colors.onAccent : colors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(daysPerWeek == day ? colors.accent : colors.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(daysPerWeek == day ? colors.accent : colors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Activity level
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Level")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.text)
                    VStack(spacing: 8) {
                        ForEach(AIActivityLevel.allCases, id: \.self) { level in
                            optionButton(
                                title: level.rawValue,
                                isSelected: activityLevel == level
                            ) { activityLevel = level }
                        }
                    }
                }
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Experience level
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gym Experience")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colors.text)
                    VStack(spacing: 8) {
                        ForEach(AIExperienceLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    experienceLevel = level
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(level.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                        Spacer()
                                        if experienceLevel == level {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                    }
                                    Text(level.description)
                                        .font(.system(size: 12))
                                        .opacity(0.7)
                                }
                                .foregroundStyle(experienceLevel == level ? colors.onAccent : colors.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(experienceLevel == level ? colors.accent : colors.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(experienceLevel == level ? colors.accent : colors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            }
            .padding(20)
        }
    }

    // MARK: - Step 2: Focus Areas & Personalization

    private var focusStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHeader(
                    icon: quickSession ? "bolt.fill" : "figure.strengthtraining.traditional",
                    title: quickSession ? "Quick Session" : "Focus & Preferences",
                    subtitle: quickSession
                        ? "Tell your trainer what to focus on, any injuries, equipment you have, and how long you've got."
                        : "Tell your AI trainer exactly what you need."
                )

                // Voice input — always first and prominent
                voiceInputSection

                // Parsed preferences summary
                if !parsedVoicePrefs.isEmpty {
                    parsedPreferencesView
                }

                // Manual filters — collapsed by default in quick session, shown in full program
                if quickSession {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showManualFilters.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13))
                            Text("Manual Filters")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Image(systemName: showManualFilters ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(colors.muted)
                        .padding(14)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    if showManualFilters {
                        muscleGroupChips
                        equipmentChips
                    }
                } else {
                    muscleGroupChips
                    equipmentChips
                }
            }
            .padding(20)
        }
    }

    // MARK: - Voice Input Section

    private var voiceInputSection: some View {
        VStack(spacing: quickSession ? 20 : 16) {
            if quickSession {
                Text("Type or say something like “chest, dumbbells, 30 minutes”.")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(colors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                Text("Type or speak any injuries, preferences, equipment, or areas to focus on.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
            }

            // Mic button
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                VStack(spacing: 10) {
                    ZStack {
                        if isRecording {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 80, height: 80)
                                .scaleEffect(isRecording ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        }
                        Circle()
                            .fill(isRecording ? Color.red : colors.accent)
                            .frame(width: 64, height: 64)
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isRecording ? Color.white : colors.onAccent)
                    }
                    Text(isRecording ? "Tap to stop" : "Tap to speak")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.muted)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preferences")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.muted)
                    Spacer()
                    if !personalNotes.isEmpty {
                        Button {
                            personalNotes = ""
                            parsedVoicePrefs = .empty
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(colors.muted)
                        }
                    }
                }
                TextField(
                    "e.g. avoid overhead press; dumbbells only; 45 minutes",
                    text: $personalNotes,
                    axis: .vertical
                )
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
                .lineLimit(2...4)
                .onChange(of: personalNotes) { _, _ in
                    parseCurrentVoicePrefs()
                }
            }
            .padding(12)
            .background(colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Parsed Preferences View

    private var parsedPreferencesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.accent)
                Text("Understood")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.accent)
            }

            if !parsedVoicePrefs.muscleGroupNames.isEmpty {
                prefRow(icon: "figure.strengthtraining.traditional", label: "Muscles", value: parsedVoicePrefs.muscleGroupNames.joined(separator: ", "))
            }
            if !parsedVoicePrefs.equipmentNames.isEmpty {
                prefRow(icon: "dumbbell", label: "Equipment", value: parsedVoicePrefs.equipmentNames.map(\.capitalized).joined(separator: ", "))
            }
            if let time = parsedVoicePrefs.timeBudget {
                prefRow(icon: "timer", label: "Time", value: WorkoutDurationEstimator.formatDuration(minutes: time))
            }
            if !parsedVoicePrefs.avoidPatterns.isEmpty {
                prefRow(icon: "xmark.circle", label: "Avoid", value: parsedVoicePrefs.avoidPatterns.joined(separator: ", "))
            }
            if !parsedVoicePrefs.injuryNotes.isEmpty {
                prefRow(icon: "cross.case", label: "Injury", value: parsedVoicePrefs.injuryNotes.joined(separator: ", "))
            }
        }
        .padding(14)
        .background(colors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func prefRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(colors.accent)
                .frame(width: 16)
                .padding(.top, 2)
            Text(label + ":")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.text)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Manual Filter Chips

    private var muscleGroupChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Muscle Groups")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.text)
                Spacer()
                Button(selectedMuscleGroupIds.count == muscleGroups.count ? "Clear" : "All") {
                    if selectedMuscleGroupIds.count == muscleGroups.count {
                        selectedMuscleGroupIds.removeAll()
                    } else {
                        selectedMuscleGroupIds = Set(muscleGroups.map(\.id))
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.accent)
            }

            if !parsedVoicePrefs.muscleGroupNames.isEmpty {
                Text("Voice selection will override these")
                    .font(.system(size: 11))
                    .foregroundStyle(colors.muted)
            }

            AIFlowLayout(spacing: 8) {
                ForEach(muscleGroups) { group in
                    let isSelected = selectedMuscleGroupIds.contains(group.id)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isSelected {
                                selectedMuscleGroupIds.remove(group.id)
                            } else {
                                selectedMuscleGroupIds.insert(group.id)
                            }
                        }
                    } label: {
                        Text(group.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? colors.onAccent : colors.text)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isSelected ? colors.accent : colors.surface2)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? colors.accent : colors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var equipmentChips: some View {
        Group {
            if !allEquipmentTypes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Available Equipment")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.text)
                        Spacer()
                        Button(selectedEquipment.count == allEquipmentTypes.count ? "Clear" : "All") {
                            if selectedEquipment.count == allEquipmentTypes.count {
                                selectedEquipment.removeAll()
                            } else {
                                selectedEquipment = Set(allEquipmentTypes)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.accent)
                    }

                    if !parsedVoicePrefs.equipmentNames.isEmpty {
                        Text("Voice selection will override these")
                            .font(.system(size: 11))
                            .foregroundStyle(colors.muted)
                    }

                    AIFlowLayout(spacing: 8) {
                        ForEach(allEquipmentTypes, id: \.self) { equip in
                            let isSelected = selectedEquipment.contains(equip)
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isSelected {
                                        selectedEquipment.remove(equip)
                                    } else {
                                        selectedEquipment.insert(equip)
                                    }
                                }
                            } label: {
                                Text(equip.capitalized)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? colors.onAccent : colors.text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? colors.accent.opacity(0.8) : colors.surface2)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? colors.accent : colors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Step 3: Generating

    private var generatingStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if isGenerating {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(colors.accent)
                    .padding(.bottom, 8)

                Text(quickSession ? "Building your workout…" : "Designing your program…")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.text)

                Text("Apple Intelligence is reasoning over your preferences and Shift exercise catalogue. You'll review everything before it is saved.")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Cancel") {
                    generationAttemptID = nil
                    generationTask?.cancel()
                    generationTask = nil
                    isGenerating = false
                    withAnimation { currentStep = 2 }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.muted)
            } else if let error = generationError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(colors.warning)

                Text("Couldn't build a valid draft")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.text)

                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                HStack(spacing: 12) {
                    Button("Try Again") {
                        startGeneration()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(colors.accent)
                    .clipShape(Capsule())

                    Button("Back") {
                        withAnimation { currentStep = 2 }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(colors.surface)
                    .clipShape(Capsule())
                }

                Button("Build a reliable basic draft") {
                    buildFallbackDraft()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.accent)
            }

            Spacer()
        }
    }

    // MARK: - Step 4: Review & Save

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader(
                    icon: "checkmark.shield.fill",
                    title: planName.isEmpty ? "Your Draft" : planName,
                    subtitle: "Catalogue-checked and ready for your review. Nothing is saved yet."
                )

                if let plan = generatedPlan {
                    // AI summary
                    if !plan.summary.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundStyle(colors.accent)
                                .padding(.top, 2)
                            Text(plan.summary)
                                .font(.system(size: 14))
                                .foregroundStyle(colors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(colors.success)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Checked before saving")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.text)
                            Text(
                                generationRepairs.isEmpty
                                    ? "Every exercise matches your Shift catalogue and all targets are within safe app limits."
                                    : "Shift corrected \(generationRepairs.count) model detail\(generationRepairs.count == 1 ? "" : "s") before showing this draft."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(colors.success.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if !progressionRecommendations.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(colors.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Use suggested starting weights", isOn: $useProgressionRecommendations)
                                    .font(.system(size: 13, weight: .semibold))
                                    .tint(colors.accent)
                                Text("Based on your latest completed sets. You can change these during the workout.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(colors.muted)
                            }
                        }
                        .padding(12)
                        .background(colors.accent.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Time budget indicator
                    if let budget = timeBudgetMinutes {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.accent)
                            Text("Time budget: \(WorkoutDurationEstimator.formatDuration(minutes: budget)) per session")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(colors.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Muscle coverage
                    let coverage = muscleCoverage()
                    if !coverage.covered.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.accent)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Muscle Coverage")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.text)
                                Text(coverage.covered.sorted().joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(colors.accent.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Days preview
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { dayIndex, day in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(day.dayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(colors.text)
                                Spacer()
                                Label(estimatedDuration(for: day), systemImage: "clock")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(colors.muted)
                            }

                            if !day.focus.isEmpty {
                                Text(day.focus)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(Array(day.exercises.enumerated()), id: \.offset) { idx, genExercise in
                                HStack(spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(colors.accent)
                                        .frame(width: 24, height: 24)
                                        .background(colors.accent.opacity(0.15))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(genExercise.exerciseName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(colors.text)
                                            .lineLimit(1)
                                        Text("\(genExercise.sets) sets × \(genExercise.repsMin)-\(genExercise.repsMax) reps · \(genExercise.restSeconds)s rest")
                                            .font(.system(size: 12))
                                            .foregroundStyle(colors.muted)
                                        if useProgressionRecommendations,
                                           let recommendation = progressionRecommendations[genExercise.exerciseID] {
                                            Text("Start at \(formatWeight(recommendation.weight)) \(authManager.user?.settings.weightUnit ?? "kg")")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(colors.accent)
                                        }
                                    }
                                    Spacer()
                                    Menu {
                                        Button {
                                            editingDraftExercise = AIDraftExerciseLocation(
                                                dayIndex: dayIndex,
                                                exerciseIndex: idx
                                            )
                                        } label: {
                                            Label("Edit Targets", systemImage: "slider.horizontal.3")
                                        }
                                        Button {
                                            replacingDraftExercise = AIDraftExerciseLocation(
                                                dayIndex: dayIndex,
                                                exerciseIndex: idx
                                            )
                                        } label: {
                                            Label("Replace Exercise", systemImage: "arrow.triangle.2.circlepath")
                                        }
                                        if idx > 0 {
                                            Button {
                                                moveGeneratedExercise(dayIndex: dayIndex, from: idx, to: idx - 1)
                                            } label: {
                                                Label("Move Up", systemImage: "arrow.up")
                                            }
                                        }
                                        if idx + 1 < day.exercises.count {
                                            Button {
                                                moveGeneratedExercise(dayIndex: dayIndex, from: idx, to: idx + 1)
                                            } label: {
                                                Label("Move Down", systemImage: "arrow.down")
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            removeGeneratedExercise(dayIndex: dayIndex, exerciseIndex: idx)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                        .disabled(day.exercises.count <= 2)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(colors.muted)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colors.border, lineWidth: 1)
                        )
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Menu {
                            Button {
                                applyDraftAdjustment(.shorter)
                            } label: {
                                Label("Shorter Workouts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            }
                            Button {
                                applyDraftAdjustment(.lessVolume)
                            } label: {
                                Label("Reduce Volume", systemImage: "minus.circle")
                            }
                            Button {
                                applyDraftAdjustment(.moreRecovery)
                            } label: {
                                Label("More Recovery", systemImage: "timer")
                            }
                        } label: {
                            Label("Quick Adjustments", systemImage: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                        }

                        Button {
                            Task { await savePlan() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(colors.onAccent)
                                } else {
                                    Image(systemName: "checkmark")
                                    Text(quickSession ? "Save Workout" : "Save \(plan.days.count) Workouts")
                                }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(colors.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isSaving)

                        if let saveError {
                            Text(saveError)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger)
                                .multilineTextAlignment(.center)
                        }

                        Button("Regenerate") {
                            generatedPlan = nil
                            currentStep = 3
                            startGeneration()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(colors.muted)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Shared Components

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(colors.accent)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(colors.text)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private func optionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(isSelected ? colors.onAccent : colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? colors.accent : colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? colors.accent : colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func continueButton(label: String = "Continue", disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(disabled ? colors.text : colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(disabled ? colors.muted : colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(disabled)
    }

    // MARK: - Speech Recognition

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }

            DispatchQueue.main.async {
                do {
                    recognitionTask?.cancel()
                    recognitionTask = nil

                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    recognitionRequest = request

                    let inputNode = audioEngine.inputNode
                    recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
                        if let result = result {
                            personalNotes = result.bestTranscription.formattedString
                        }
                        if result?.isFinal ?? false {
                            stopRecording()
                        }
                    }

                    let format = inputNode.outputFormat(forBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.append(buffer)
                    }

                    audioEngine.prepare()
                    try audioEngine.start()
                    isRecording = true
                } catch {
                    print("Speech recognition failed to start: \(error)")
                }
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        // Don't cancel the task — let it finish delivering the final transcription
        recognitionTask = nil

        // Parse voice preferences from whatever was transcribed
        parseCurrentVoicePrefs()
    }

    private func parseCurrentVoicePrefs() {
        parsedVoicePrefs = Self.parseVoicePreferences(
            from: personalNotes,
            muscleGroups: muscleGroups,
            equipment: allEquipmentTypes
        )
    }

    // MARK: - AI Generation

    /// Pre-filters exercises based on experience level, user notes, and selected muscle groups.
    /// Returns exercises tagged with their movement pattern for smarter prompting.
    private func buildSmartExerciseList() -> (exerciseString: String, filtered: [Exercise]) {
        let muscleGroupMap = Dictionary(muscleGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
        let reverseMuscleMap = Dictionary(muscleGroups.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { _, last in last })

        // 1. Filter by muscle groups — voice overrides UI if specific groups mentioned
        let effectiveMuscleIds: Set<String>
        if !parsedVoicePrefs.muscleGroupNames.isEmpty {
            effectiveMuscleIds = Set(parsedVoicePrefs.muscleGroupNames.compactMap { reverseMuscleMap[$0.lowercased()] })
        } else {
            effectiveMuscleIds = selectedMuscleGroupIds
        }
        var filtered = allExercises.filter { effectiveMuscleIds.contains($0.primaryMuscleId) }

        // 2. Filter by equipment — voice overrides UI if specific equipment mentioned
        let effectiveEquipment: Set<String>
        if !parsedVoicePrefs.equipmentNames.isEmpty {
            effectiveEquipment = Set(parsedVoicePrefs.equipmentNames.map { $0.lowercased() })
        } else if selectedEquipment.count < allEquipmentTypes.count {
            effectiveEquipment = Set(selectedEquipment.map { $0.lowercased() })
        } else {
            effectiveEquipment = Set(allEquipmentTypes.map { $0.lowercased() })
        }

        if effectiveEquipment.count < allEquipmentTypes.count {
            filtered = filtered.filter { exercise in
                guard let equip = exercise.equipment?.lowercased() else { return false }
                return effectiveEquipment.contains(equip)
            }
        }

        // 3. Filter by experience level — don't give beginners expert exercises
        let allowedLevels: Set<String> = {
            switch experienceLevel {
            case .beginner: return ["beginner"]
            case .intermediate: return ["beginner", "intermediate"]
            case .advanced: return ["beginner", "intermediate", "expert"]
            }
        }()
        filtered = filtered.filter { exercise in
            guard let level = exercise.level?.lowercased() else { return true }
            return allowedLevels.contains(level)
        }

        // 4. Filter out exercises mentioned negatively in user notes
        let avoidPatterns = parsedVoicePrefs.avoidPatterns.isEmpty
            ? Self.extractAvoidPatterns(from: personalNotes.lowercased())
            : parsedVoicePrefs.avoidPatterns
        if !avoidPatterns.isEmpty {
            filtered = filtered.filter { exercise in
                let nameLower = exercise.name.lowercased()
                return !avoidPatterns.contains(where: { nameLower.contains($0) })
            }
        }

        // 5. For unrestricted requests, lead with equipment found in modern
        // commercial gyms. An explicit bodyweight-only filter still works
        // because only bodyweight exercises reach this sorting step.
        filtered = GymExercisePreferenceService.sorted(
            filtered,
            familiarExerciseIDs: recentExerciseIds
        )

        // 6. Group by muscle group with movement pattern tags + familiarity tag, cap per group
        var grouped: [String: [String]] = [:]
        for exercise in filtered {
            let groupName = muscleGroupMap[exercise.primaryMuscleId] ?? "Other"
            let movTag = Self.movementTag(for: exercise)
            let familiar = recentExerciseIds.contains(exercise.id)
            var tags: [String] = []
            if !movTag.isEmpty { tags.append(movTag) }
            if familiar { tags.append("F") }
            let entry = tags.isEmpty ? exercise.name : "\(exercise.name) [\(tags.joined(separator: ","))]"
            grouped[groupName, default: []].append(entry)
        }

        // Cap per group — more for selected focus areas, fewer for others
        let maxPerGroup = filtered.count > 100 ? 12 : 18
        for (key, names) in grouped {
            grouped[key] = Array(names.prefix(maxPerGroup))
        }

        let exerciseString = grouped
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.joined(separator: ", "))" }
            .joined(separator: "\n")

        // Keep the structured generation context small enough for the on-device
        // model while preserving choices across every selected muscle group.
        let orderedGroups = Dictionary(grouping: filtered, by: \.primaryMuscleId)
            .sorted { lhs, rhs in
                let lhsName = muscleGroupMap[lhs.key] ?? lhs.key
                let rhsName = muscleGroupMap[rhs.key] ?? rhs.key
                return lhsName < rhsName
            }
            .map { _, exercises in Array(exercises.prefix(12)) }
        var groundedCatalogue: [Exercise] = []
        for index in 0..<12 {
            for exercises in orderedGroups where index < exercises.count {
                groundedCatalogue.append(exercises[index])
                if groundedCatalogue.count == 60 { break }
            }
            if groundedCatalogue.count == 60 { break }
        }

        return (exerciseString, groundedCatalogue)
    }

    /// Extracts exercise names/types the user wants to avoid from their notes.
    static func extractAvoidPatterns(from notes: String) -> [String] {
        var patterns: [String] = []
        let avoidPhrases = ["avoid", "no ", "skip", "can't do", "cant do", "don't do", "dont do", "stay away from", "not "]
        for phrase in avoidPhrases {
            var searchRange = notes.startIndex..<notes.endIndex
            while let range = notes.range(of: phrase, range: searchRange) {
                let after = notes[range.upperBound...]
                let words = after.prefix(60).split(separator: " ").prefix(4)
                let extracted = words.joined(separator: " ")
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                if !extracted.isEmpty && extracted.count > 2 {
                    patterns.append(extracted)
                }
                searchRange = range.upperBound..<notes.endIndex
            }
        }
        return patterns
    }

    /// Creates a movement pattern tag for an exercise based on its properties.
    static func movementTag(for exercise: Exercise) -> String {
        var parts: [String] = []
        if let mechanic = exercise.mechanic?.lowercased() {
            parts.append(mechanic == "compound" ? "C" : "I")
        }
        if let force = exercise.force?.lowercased() {
            parts.append(force)
        }
        return parts.joined(separator: "/")
    }

    /// Provides specific rep/set/rest ranges per goal so the model has concrete numbers.
    static func repScheme(for goal: AIGoalType?) -> String {
        guard let goal = goal else { return "3 sets, 8-12 reps, 60-90 seconds rest" }
        switch goal {
        case .buildMuscle: return "3-4 sets, 8-12 reps, 60-90 seconds rest"
        case .increaseStrength: return "4-5 sets, 3-6 reps, 120-180 seconds rest"
        case .toneAndDefine: return "3 sets, 12-15 reps, 45-60 seconds rest"
        case .generalFitness: return "3 sets, 8-12 reps, 60-90 seconds rest"
        case .improveEndurance: return "2-3 sets, 15-20 reps, 30-45 seconds rest"
        case .athleticPerformance: return "4 sets, 5-8 reps, 90-120 seconds rest"
        case .rehabilitation: return "2-3 sets, 12-15 reps, 60-90 seconds rest"
        case .bodyRecomposition: return "3-4 sets, 10-15 reps, 60 seconds rest"
        }
    }

    /// Parses a time budget from the user's voice notes.
    /// Recognizes patterns like "30 minutes", "1.5 hours", "an hour", "2 hours", "half an hour", "45 min".
    static func extractTimeBudget(from notes: String) -> Int? {
        let lower = notes.lowercased()

        // "half an hour" / "half hour"
        if lower.contains("half an hour") || lower.contains("half hour") {
            return 30
        }

        // "an hour and a half" / "hour and a half"
        if lower.contains("an hour and a half") || lower.contains("hour and a half") {
            return 90
        }

        // "an hour" (but not "an hour and")
        if lower.contains("an hour") && !lower.contains("an hour and") {
            return 60
        }

        // "X.X hours" or "X hours"
        guard let hourPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*hours?"#) else { return nil }
        if let match = hourPattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(match.range(at: 1), in: lower),
           let hours = Double(lower[numRange]) {
            return Int(hours * 60)
        }

        // "X minutes" / "X mins" / "X min"
        guard let minPattern = try? NSRegularExpression(pattern: #"(\d+)\s*(?:minutes?|mins?)"#) else { return nil }
        if let match = minPattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(match.range(at: 1), in: lower),
           let mins = Int(lower[numRange]) {
            return mins
        }

        return nil
    }

    /// Calculates the maximum number of exercises that fit in the time budget.
    /// Uses average set duration (including rest) to estimate.
    static func maxExercisesForBudget(minutes: Int, setsPerExercise: Int = 3, avgRestSeconds: Int = 90) -> Int {
        if setsPerExercise == 3 && avgRestSeconds == 90 {
            return AIPlanQualityService.maximumExerciseCount(for: minutes)
        }
        let secondsPerSet = 45 + avgRestSeconds // ~45s working + rest
        let secondsPerExercise = secondsPerSet * setsPerExercise
        let warmupSeconds = 300 // 5 min warmup
        let availableSeconds = max(0, (minutes * 60) - warmupSeconds)
        return max(2, availableSeconds / secondsPerExercise)
    }

    /// Parses voice input to extract muscle group preferences.
    static func extractMuscleGroups(from notes: String, available: [MuscleGroup]) -> [String] {
        let lower = notes.lowercased()
        let aliases: [String: [String]] = [
            "chest": ["chest", "pecs", "pec"],
            "back": ["back", "lats", "lat"],
            "shoulders": ["shoulders", "shoulder", "delts", "delt"],
            "biceps": ["biceps", "bicep"],
            "triceps": ["triceps", "tricep"],
            "legs": ["legs", "leg", "quads", "quad", "hamstrings", "hamstring", "glutes", "glute"],
            "core": ["core", "abs", "abdominals"],
            "forearms": ["forearms", "forearm", "grip"],
            "calves": ["calves", "calf"],
            "traps": ["traps", "trap", "trapezius"],
            "neck": ["neck"],
        ]

        var matched: [String] = []
        for group in available {
            let groupLower = group.name.lowercased()
            if lower.contains(groupLower) {
                matched.append(group.name)
                continue
            }
            // Check aliases that map to this group name
            if let aliasList = aliases[groupLower], aliasList.contains(where: { lower.contains($0) }) {
                matched.append(group.name)
            }
        }
        return matched
    }

    /// Parses voice input to extract equipment preferences.
    static func extractEquipment(from notes: String, available: [String]) -> [String] {
        let lower = notes.lowercased()
        let aliases: [String: [String]] = [
            "dumbbell": ["dumbbell", "dumbbells", "dumb bell", "dumb bells"],
            "barbell": ["barbell", "barbells", "bar bell", "bar bells"],
            "cable": ["cable", "cables"],
            "machine": ["machine", "machines"],
            "body only": ["bodyweight", "body weight", "no equipment", "just my body"],
            "kettlebell": ["kettlebell", "kettlebells", "kettle bell"],
            "bands": ["bands", "band", "resistance band"],
            "e-z curl bar": ["ez bar", "ez curl", "curl bar"],
            "smith machine": ["smith machine"],
        ]

        var matched: [String] = []
        for equip in available {
            let equipLower = equip.lowercased()
            if lower.contains(equipLower) {
                matched.append(equip)
                continue
            }
            if let aliasList = aliases[equipLower], aliasList.contains(where: { lower.contains($0) }) {
                matched.append(equip)
            }
        }
        return matched
    }

    /// Extracts injury/recovery context from voice notes.
    /// Detects patterns like "recovering from X injury", "X is injured", "take it light on X",
    /// "bad X", "sore X", "hurt my X" and returns descriptive notes for the prompt.
    static func extractInjuryNotes(from notes: String, muscleGroups: [MuscleGroup]) -> [String] {
        let lower = notes.lowercased()
        let bodyParts = muscleGroups.map { $0.name.lowercased() }
            + ["back", "shoulder", "knee", "hip", "wrist", "elbow", "ankle", "neck", "lower back"]

        let injuryPhrases = [
            "injur", "recovering", "recovery", "take it light", "take it easy",
            "very light", "go light", "go easy", "sore", "hurt", "bad ",
            "pain in", "pain with", "tender", "strain", "pulled",
        ]

        var results: [String] = []
        for phrase in injuryPhrases {
            if lower.contains(phrase) {
                for part in bodyParts {
                    if lower.contains(part) {
                        // Determine severity/context
                        let isLight = lower.contains("light") || lower.contains("easy")
                            || lower.contains("recovering") || lower.contains("recovery")
                        let modifier = isLight ? "light/recovery intensity" : "injured - be careful"
                        let note = "\(part) — \(modifier)"
                        if !results.contains(note) {
                            results.append(note)
                        }
                    }
                }
                break
            }
        }
        return results
    }

    /// Parses all preferences from voice notes in one pass.
    static func parseVoicePreferences(from notes: String, muscleGroups: [MuscleGroup], equipment: [String]) -> VoicePreferences {
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        return VoicePreferences(
            muscleGroupNames: extractMuscleGroups(from: notes, available: muscleGroups),
            equipmentNames: extractEquipment(from: notes, available: equipment),
            timeBudget: extractTimeBudget(from: notes),
            avoidPatterns: extractAvoidPatterns(from: notes.lowercased()),
            injuryNotes: extractInjuryNotes(from: notes, muscleGroups: muscleGroups)
        )
    }

    /// Suggests a split strategy based on days per week for the prompt.
    private func splitStrategy() -> String {
        switch daysPerWeek {
        case 1: return "Full-body session covering all selected categories."
        case 2: return "Upper/Lower split, or Push-Pull split."
        case 3: return "Push/Pull/Legs split, or Full body 3x with varied emphasis."
        case 4: return "Upper/Lower split 2x each, or Push/Pull/Legs + Full body."
        case 5: return "Push/Pull/Legs + Upper/Lower, or body-part split."
        case 6...7: return "Body-part split or Push/Pull/Legs 2x."
        default: return "Distribute categories evenly across sessions."
        }
    }

    private func generate(attemptID: UUID) async {
        // Ensure voice prefs are parsed (safety net)
        if parsedVoicePrefs.isEmpty && !personalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parseCurrentVoicePrefs()
        }

        let (_, filteredExercises) = buildSmartExerciseList()

        // Use time budget from voice prefs
        if let parsed = parsedVoicePrefs.timeBudget {
            timeBudgetMinutes = parsed
        }

        guard filteredExercises.count >= max(2, daysPerWeek * 2) else {
            generationError = "There aren't enough matching exercises for those filters. Add equipment or select more muscle groups."
            isGenerating = false
            return
        }

        do {
            let request = AIPlanGenerationRequest(
                days: daysPerWeek,
                goal: goalType?.rawValue ?? "General Fitness",
                experience: "\(experienceLevel.rawValue); \(activityLevel.rawValue) outside training",
                split: splitStrategy(),
                targetScheme: Self.repScheme(for: goalType),
                timeBudgetMinutes: timeBudgetMinutes,
                notes: personalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                injuryNotes: parsedVoicePrefs.injuryNotes,
                catalogue: filteredExercises,
                familiarExerciseIDs: recentExerciseIds
            )
            lastGenerationRequest = request
            let result = try await AppleIntelligencePlanService.generate(request)
            guard generationAttemptID == attemptID, !Task.isCancelled else { return }
            guard let plan = result.plan, result.errors.isEmpty else {
                throw AIPlanGenerationError.invalidDraft(result.errors)
            }
            let recommendations = await progressionRecommendations(for: plan)
            guard generationAttemptID == attemptID, !Task.isCancelled else { return }
            generatedPlan = plan
            generationRepairs = result.repairs
            planName = plan.planName
            progressionRecommendations = recommendations
            cacheCurrentDraft()
            withAnimation { currentStep = 4 }
        } catch {
            guard generationAttemptID == attemptID else { return }
            if error is CancellationError || Task.isCancelled {
                isGenerating = false
                return
            }
            generationError = error.localizedDescription
        }
        if generationAttemptID == attemptID {
            isGenerating = false
        }
    }

    private func startGeneration() {
        generationTask?.cancel()
        let attemptID = UUID()
        generationAttemptID = attemptID
        isGenerating = true
        generationError = nil
        generationRepairs = []
        generationTask = Task {
            await generate(attemptID: attemptID)
            if generationAttemptID == attemptID {
                generationTask = nil
            }
        }
    }

    private func buildFallbackDraft() {
        let request: AIPlanGenerationRequest
        if let lastGenerationRequest {
            request = lastGenerationRequest
        } else {
            if parsedVoicePrefs.isEmpty
                && !personalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parseCurrentVoicePrefs()
            }
            let (_, filteredExercises) = buildSmartExerciseList()
            request = AIPlanGenerationRequest(
                days: daysPerWeek,
                goal: goalType?.rawValue ?? "General Fitness",
                experience: "\(experienceLevel.rawValue); \(activityLevel.rawValue) outside training",
                split: splitStrategy(),
                targetScheme: Self.repScheme(for: goalType),
                timeBudgetMinutes: parsedVoicePrefs.timeBudget ?? timeBudgetMinutes,
                notes: personalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                injuryNotes: parsedVoicePrefs.injuryNotes,
                catalogue: filteredExercises,
                familiarExerciseIDs: recentExerciseIds
            )
            lastGenerationRequest = request
        }

        let result = AIPlanFallbackBuilder.build(request)
        guard let plan = result.plan else {
            generationError = result.errors.joined(separator: " ")
            return
        }
        generatedPlan = plan
        generationRepairs = ["Used Shift's catalogue-based fallback because Apple Intelligence was unavailable."]
        planName = plan.planName
        cacheCurrentDraft()
        Task { await loadProgressionRecommendations() }
        withAnimation { currentStep = 4 }
    }

    private func cacheCurrentDraft() {
        guard let plan = generatedPlan, let userID = authManager.currentUserId else { return }
        AIPlanDraftStore.save(plan, userID: userID, quickSession: quickSession)
    }

    private func clearCachedDraft() {
        guard let userID = authManager.currentUserId else { return }
        AIPlanDraftStore.clear(userID: userID, quickSession: quickSession)
    }

    /// Analyzes which muscle groups are covered as primary/secondary across the plan.
    /// Returns groups that are missing coverage so the user can see gaps.
    private func muscleCoverage() -> (covered: Set<String>, missing: [String]) {
        guard let plan = generatedPlan else { return ([], []) }
        let muscleGroupMap = Dictionary(muscleGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
        var coveredIds: Set<String> = []

        for day in plan.days {
            for genEx in day.exercises {
                var usedIds: Set<String> = []
                if let matched = ExerciseMatchingService.match(genEx.exerciseName, against: allExercises, usedIds: &usedIds) {
                    coveredIds.insert(matched.primaryMuscleId)
                    for secId in matched.secondaryMuscleIds {
                        coveredIds.insert(secId)
                    }
                }
            }
        }

        let coveredNames = Set(coveredIds.compactMap { muscleGroupMap[$0] })
        let selectedNames = Set(selectedMuscleGroupIds.compactMap { muscleGroupMap[$0] })
        let missing = selectedNames.subtracting(coveredNames).sorted()
        return (coveredNames, missing)
    }

    /// Estimates workout duration for a generated day using WorkoutDurationEstimator.
    private func estimatedDuration(for day: GeneratedDay) -> String {
        guard !day.exercises.isEmpty else { return "—" }
        let totalSets = day.exercises.reduce(0) { $0 + $1.sets }
        let avgReps = day.exercises.reduce(0) { $0 + ($1.repsMin + $1.repsMax) / 2 } / day.exercises.count
        let avgRest = day.exercises.reduce(0) { $0 + $1.restSeconds } / day.exercises.count
        let minutes = WorkoutDurationEstimator.estimate(
            exerciseCount: day.exercises.count,
            totalSets: totalSets,
            avgReps: avgReps,
            defaultRestSeconds: avgRest
        )
        return WorkoutDurationEstimator.formatDuration(minutes: minutes)
    }

    private func generatedExercise(at location: AIDraftExerciseLocation) -> GeneratedExercise? {
        guard let plan = generatedPlan,
              plan.days.indices.contains(location.dayIndex),
              plan.days[location.dayIndex].exercises.indices.contains(location.exerciseIndex) else {
            return nil
        }
        return plan.days[location.dayIndex].exercises[location.exerciseIndex]
    }

    private func updateGeneratedExercise(
        _ exercise: GeneratedExercise,
        at location: AIDraftExerciseLocation
    ) {
        guard var plan = generatedPlan,
              plan.days.indices.contains(location.dayIndex),
              plan.days[location.dayIndex].exercises.indices.contains(location.exerciseIndex) else {
            return
        }
        plan.days[location.dayIndex].exercises[location.exerciseIndex] = exercise
        generatedPlan = plan
        cacheCurrentDraft()
    }

    private func replaceGeneratedExercise(
        at location: AIDraftExerciseLocation,
        with replacement: Exercise
    ) {
        guard var item = generatedExercise(at: location) else { return }
        item.exerciseID = replacement.id
        item.exerciseName = replacement.name
        updateGeneratedExercise(item, at: location)
        Task { await loadProgressionRecommendations() }
    }

    private func removeGeneratedExercise(dayIndex: Int, exerciseIndex: Int) {
        guard var plan = generatedPlan,
              plan.days.indices.contains(dayIndex),
              plan.days[dayIndex].exercises.count > 2,
              plan.days[dayIndex].exercises.indices.contains(exerciseIndex) else { return }
        plan.days[dayIndex].exercises.remove(at: exerciseIndex)
        generatedPlan = plan
        cacheCurrentDraft()
    }

    private func moveGeneratedExercise(dayIndex: Int, from source: Int, to destination: Int) {
        guard var plan = generatedPlan,
              plan.days.indices.contains(dayIndex),
              plan.days[dayIndex].exercises.indices.contains(source),
              plan.days[dayIndex].exercises.indices.contains(destination) else { return }
        let item = plan.days[dayIndex].exercises.remove(at: source)
        plan.days[dayIndex].exercises.insert(item, at: destination)
        generatedPlan = plan
        cacheCurrentDraft()
    }

    private func replacementSuggestions(for exercise: Exercise) -> [Exercise] {
        let selectedIDs = Set(
            generatedPlan?.days.flatMap(\.exercises).map(\.exerciseID) ?? []
        )
        return ExerciseSubstitutionService.suggestions(
            for: exercise,
            from: allExercises,
            excluding: selectedIDs
        )
    }

    private enum DraftAdjustment {
        case shorter
        case lessVolume
        case moreRecovery
    }

    private func applyDraftAdjustment(_ adjustment: DraftAdjustment) {
        guard var plan = generatedPlan else { return }
        for dayIndex in plan.days.indices {
            switch adjustment {
            case .shorter:
                while plan.days[dayIndex].exercises.count > 4 {
                    plan.days[dayIndex].exercises.removeLast()
                }
            case .lessVolume:
                for exerciseIndex in plan.days[dayIndex].exercises.indices {
                    plan.days[dayIndex].exercises[exerciseIndex].sets = max(
                        2,
                        plan.days[dayIndex].exercises[exerciseIndex].sets - 1
                    )
                }
            case .moreRecovery:
                for exerciseIndex in plan.days[dayIndex].exercises.indices {
                    plan.days[dayIndex].exercises[exerciseIndex].restSeconds = min(
                        300,
                        plan.days[dayIndex].exercises[exerciseIndex].restSeconds + 30
                    )
                }
            }
        }
        generatedPlan = plan
        cacheCurrentDraft()
        Task { await loadProgressionRecommendations() }
    }

    private func loadProgressionRecommendations() async {
        guard let plan = generatedPlan, let userID = authManager.currentUserId else {
            progressionRecommendations = [:]
            return
        }
        progressionRecommendations = await progressionRecommendations(for: plan, userID: userID)
    }

    private func progressionRecommendations(
        for plan: GeneratedPlan,
        userID explicitUserID: String? = nil
    ) async -> [String: ProgressionRecommendation] {
        guard let userID = explicitUserID ?? authManager.currentUserId else { return [:] }
        let exercises = plan.days.flatMap(\.exercises)
        let targets = Dictionary(
            exercises.map { ($0.exerciseID, (repsMin: $0.repsMin, repsMax: $0.repsMax)) },
            uniquingKeysWith: { first, _ in first }
        )
        do {
            let latest = try await SessionSetRepository.findLatestCompletedSets(
                userId: userID,
                exerciseIds: Array(targets.keys)
            )
            return ProgressionRecommendationService.recommendations(
                latestSets: latest,
                targets: targets,
                increment: authManager.user?.settings.defaultWeightIncrement ?? 2.5
            )
        } catch {
            return [:]
        }
    }

    // MARK: - Save Plan

    private func savePlan() async {
        guard let plan = generatedPlan else { return }
        isSaving = true
        saveError = nil

        let catalogueIDs = Set(allExercises.map(\.id))
        let drafts = plan.days.map { day in
            PlanDraftDay(
                name: day.dayName,
                notes: [plan.summary, day.focus].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                exercises: day.exercises.compactMap { item in
                    guard catalogueIDs.contains(item.exerciseID) else { return nil }
                    return PlanExercise(
                        id: UUID().uuidString.lowercased(),
                        planId: "",
                        exerciseId: item.exerciseID,
                        position: 0,
                        targetSets: item.sets,
                        targetRepsMin: item.repsMin,
                        targetRepsMax: item.repsMax,
                        targetWeight: useProgressionRecommendations
                            ? progressionRecommendations[item.exerciseID]?.weight
                            : nil,
                        restSeconds: item.restSeconds
                    )
                }
            )
        }

        do {
            _ = try await PlanService.createProgram(
                drafts,
                programName: plan.days.count > 1 ? plan.planName : nil,
                source: "ai"
            )
            clearCachedDraft()
            PhoneSessionManager.shared.sendContextToWatch()
            onSaved?(plan.days.count)
            isSaving = false
            dismiss()
        } catch {
            saveError = "Nothing was saved. \(error.localizedDescription)"
            isSaving = false
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

}

// MARK: - AIFlowLayout

@available(iOS 26, *)
private struct AIFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, containerWidth: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, containerWidth: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func layout(subviews: Subviews, containerWidth: CGFloat) -> (positions: [CGPoint], width: CGFloat, height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > containerWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (positions, maxWidth, y + rowHeight)
    }
}
#endif
