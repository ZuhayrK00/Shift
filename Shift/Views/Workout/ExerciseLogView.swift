import SwiftUI

// MARK: - ExerciseLogView

/// Per-exercise logging screen with stepper controls, set timeline, and
/// info/history/progress tabs. The "Log" tab UI lives in ExerciseLogTabView.
struct ExerciseLogView: View {
    let sessionId: String
    let exerciseId: String

    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var exercise: Exercise?
    @State private var sets: [SessionSet]       = []
    @State private var weight: Double           = 0
    @State private var reps: Double             = 0
    @State private var selectedSetId: String?   = nil
    @State private var activeTab: LogTab        = .log
    @State private var restDuration: Int        = 90
    @State private var planExercise: PlanExercise?
    @State private var sessionDate: Date        = Date()
    @State private var isBackfill               = false
    @State private var loading                  = true
    @State private var exerciseNote: String     = ""
    @State private var isSaving                 = false
    @State private var saveError: String?
    @State private var showReplacementPicker = false
    @State private var plateCalculatorRequest: PlateCalculatorRequest?
    @State private var sessionExerciseIds: Set<String> = []
    @State private var sessionIsCompleted = false

    // MARK: - Tab enum

    enum LogTab: String, CaseIterable {
        case log      = "Log"
        case info     = "Info"
        case history  = "History"
        case progress = "Progress"
    }

    // MARK: - Derived

    private var weightIncrement: Double {
        authManager.user?.settings.defaultWeightIncrement ?? 2.5
    }

    private var weightUnit: String {
        authManager.user?.settings.weightUnit ?? "kg"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            if loading {
                ProgressView().tint(colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    tabBar
                    tabContent
                }
            }

            if isSaving {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView().tint(colors.accent)
            }
        }
        .navigationTitle(exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sessionIsCompleted {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showReplacementPicker = true
                        } label: {
                            Label("Replace Exercise", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await loadData() }
        .onDisappear {
            RestTimerManager.shared.stop()
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .sheet(isPresented: $showReplacementPicker) {
            if let exercise {
                ContextualExerciseReplacementSheet(
                    current: exercise,
                    excluding: sessionExerciseIds
                ) { replacement in
                    Task { await replaceExercise(with: replacement) }
                }
            }
        }
        .sheet(item: $plateCalculatorRequest) { request in
            PlateCalculatorSheet(
                targetWeight: request.targetWeight,
                unit: request.unit
            )
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(LogTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    Text(tab == .log ? dateLabel : tab.rawValue)
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

    private var dateLabel: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: sessionDate)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .log:
            ExerciseLogTabView(
                sets: sets,
                restDuration: restDuration,
                weightUnit: weightUnit,
                weightIncrement: weightIncrement,
                selectedSetId: selectedSetId,
                isBackfill: isBackfill,
                isBusy: isSaving,
                canLogWarmup: !sessionIsCompleted
                    && !sets.contains(where: {
                        $0.isCompleted && $0.setType != .warmup
                    }),
                canShowPlates: supportsPlateLoading,
                exerciseNote: $exerciseNote,
                weight: $weight,
                reps: $reps,
                onAdd:    { Task { await addSet() } },
                onUpdate: { Task { await updateSelectedSet() } },
                onDelete: { Task { await deleteSelectedSet() } },
                onChangeSetType: { set, type in
                    Task { await changeSetType(set: set, newType: type) }
                },
                onSelectSet: { set in
                    if let s = set {
                        selectedSetId = s.id
                        weight = convertWeight(s.weight ?? 0, to: weightUnit)
                        reps   = Double(s.reps)
                    } else {
                        selectedSetId = nil
                    }
                },
                onSaveNote: { Task { await saveNote() } },
                onLogWarmup: { Task { await logWarmupSet() } },
                onShowPlates: {
                    // Snapshot the current values into the presentation item.
                    // A Boolean sheet can capture the previous render's weight on
                    // its first presentation.
                    plateCalculatorRequest = PlateCalculatorRequest(
                        targetWeight: weight,
                        unit: weightUnit
                    )
                }
            )
        case .info:
            if let ex = exercise { ExerciseDetailView(exercise: ex) }
        case .history:
            ExerciseHistoryView(exerciseId: exerciseId)
        case .progress:
            ExerciseProgressView(exerciseId: exerciseId)
        }
    }

    // MARK: - Data loading

    private func loadData() async {
        loading = true
        defer { loading = false }

        do {
            async let exTask = ExerciseService.getById(exerciseId)
            async let sessTask = WorkoutService.getSession(sessionId)
            async let setsTask = WorkoutService.getSetsFor(
                sessionId: sessionId,
                exerciseId: exerciseId
            )

            let (loadedExercise, loadedSession, allSets) = try await (
                exTask,
                sessTask,
                setsTask
            )
            guard let loadedExercise, let sess = loadedSession else {
                throw ExerciseLogError.dataNotFound
            }
            exercise = loadedExercise
            sessionDate = sess.startedAt
            sessionIsCompleted = sess.endedAt != nil
            sessionExerciseIds = Set(try await WorkoutService.getSessionExerciseIds(sessionId))

            let sessionAge = Date().timeIntervalSince(sess.startedAt)
            isBackfill = sess.endedAt != nil || sessionAge > 12 * 3600
            sets = allSets

            if let planId = sess.planId,
               let planWithExercises = try await PlanService.getPlanWithExercises(planId) {
                planExercise = planWithExercises.exercises
                    .first { $0.exercise.id == exerciseId }?
                    .planExercise
            }

            exerciseNote = try await WorkoutService.getExerciseNote(
                sessionId: sessionId,
                exerciseId: exerciseId
            ) ?? ""
            seedStepperValues(from: allSets)
            restDuration = planExercise?.restSeconds
                ?? authManager.user?.settings.restTimer.durationSeconds
                ?? 90
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var supportsPlateLoading: Bool {
        guard let equipment = exercise?.equipment?.lowercased() else { return false }
        return equipment.contains("barbell")
            || equipment.contains("smith")
            || equipment.contains("olympic")
    }

    private func seedStepperValues(from allSets: [SessionSet]) {
        if let last = allSets.last(where: { $0.isCompleted }) {
            weight = convertWeight(last.weight ?? 0, to: weightUnit)
            reps   = Double(last.reps)
        } else if let plan = planExercise {
            weight = convertWeight(plan.targetWeight ?? 0, to: weightUnit)
            reps   = Double(plan.defaultReps)
        } else {
            weight = 0; reps = 0
        }
    }

    // MARK: - Set actions

    /// Converts the stepper weight (in user's unit) back to kg for storage.
    private var weightInKg: Double? {
        guard weight > 0 else { return nil }
        return convertWeightToKg(weight, from: weightUnit)
    }

    private func addSet() async {
        // Don't log empty sets — require at least 1 rep
        guard Int(reps) > 0 else { return }
        await performSave {
            if sets.contains(where: { !$0.isCompleted && $0.setType == .warmup }) {
                try await WorkoutService.discardPendingWarmupSets(
                    sessionId: sessionId,
                    exerciseId: exerciseId
                )
                try await reloadSets()
            }

            // If there's a placeholder, complete it instead of creating another row.
            let loggedSet: SessionSet?
            if let placeholder = sets.first(where: { !$0.isCompleted }) {
                try await WorkoutService.updateSet(placeholder.id, patch: SetPatch(
                    reps: Int(reps),
                    weight: weightInKg,
                    isCompleted: true
                ))
                loggedSet = placeholder
            } else {
                let newSet = try await WorkoutService.addSet(
                    sessionId: sessionId,
                    exerciseId: exerciseId,
                    reps: Int(reps),
                    weight: weightInKg
                )
                loggedSet = newSet
            }
            try await startRestTimerIfNeeded(after: loggedSet)
            try await reloadSets()
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
        }
    }

    private func changeSetType(set: SessionSet, newType: SetType) async {
        await performSave {
            try await WorkoutService.updateSet(set.id, patch: SetPatch(setType: newType))
            try await reloadSets()
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
        }
    }

    private func updateSelectedSet() async {
        guard let id = selectedSetId else { return }
        await performSave {
            try await WorkoutService.updateSet(id, patch: SetPatch(
                reps: Int(reps),
                weight: weightInKg
            ))
            selectedSetId = nil
            try await reloadSets()
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
        }
    }

    private func deleteSelectedSet() async {
        guard let id = selectedSetId else { return }
        let selectedSet = sets.first(where: { $0.id == id })

        await performSave {
            if selectedSet?.setType == .warmup {
                try await WorkoutService.deleteSet(id)
            } else if let plan = planExercise, sets.count <= plan.targetSets {
                try await WorkoutService.updateSet(id, patch: SetPatch(
                    reps: plan.defaultReps,
                    weight: plan.targetWeight,
                    isCompleted: false
                ))
            } else {
                try await WorkoutService.deleteSet(id)
            }
            selectedSetId = nil
            try await reloadSets()
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
        }
    }

    private func saveNote() async {
        let trimmed = exerciseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        await performSave {
            try await WorkoutService.setExerciseNote(
                sessionId: sessionId,
                exerciseId: exerciseId,
                note: trimmed.isEmpty ? nil : trimmed
            )
        }
    }

    private func reloadSets() async throws {
        try await WorkoutService.normalizeSetOrder(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
        sets = try await WorkoutService.getSetsFor(
            sessionId: sessionId,
            exerciseId: exerciseId
        )
    }

    private func logWarmupSet() async {
        guard Int(reps) > 0 else { return }
        await performSave {
            let loggedSet = try await WorkoutService.logWarmupSet(
                sessionId: sessionId,
                exerciseId: exerciseId,
                reps: Int(reps),
                weight: weightInKg
            )
            try await startRestTimerIfNeeded(after: loggedSet)
            try await reloadSets()
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
        }
    }

    private func startRestTimerIfNeeded(after loggedSet: SessionSet?) async throws {
        let restEnabled = authManager.user?.settings.restTimer.enabled ?? true
        guard restEnabled, !isBackfill else { return }

        if let groupId = loggedSet?.groupId {
            let roundDone = try await WorkoutService.isGroupRoundComplete(
                sessionId: sessionId,
                groupId: groupId
            )
            if roundDone {
                RestTimerManager.shared.start(seconds: restDuration, sessionId: sessionId)
            }
        } else {
            RestTimerManager.shared.start(seconds: restDuration, sessionId: sessionId)
        }
    }

    private func replaceExercise(with replacement: Exercise) async {
        await performSave {
            try await WorkoutService.replaceExercise(
                sessionId: sessionId,
                from: exerciseId,
                to: replacement.id
            )
            PhoneSessionManager.shared.sendWorkoutUpdateToWatch()
            dismiss()
        }
    }

    private func performSave(_ operation: () async throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private enum ExerciseLogError: LocalizedError {
    case dataNotFound

    var errorDescription: String? {
        "This exercise log could not be loaded for the signed-in account."
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExerciseLogView(sessionId: "sess-1", exerciseId: "ex-1")
            .shiftTheme()
            .environment(AuthManager())
    }
    .preferredColorScheme(.dark)
}
