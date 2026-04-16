import SwiftUI

// MARK: - ExerciseLogView

/// Per-exercise logging screen with stepper controls, set timeline, and
/// info/history/progress tabs. The "Log" tab UI lives in ExerciseLogTabView.
struct ExerciseLogView: View {
    let sessionId: String
    let exerciseId: String

    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

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
        }
        .navigationTitle(exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .onDisappear {
            RestTimerManager.shared.stop()
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
                onSaveNote: { Task { await saveNote() } }
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

        async let exTask   = ExerciseService.getById(exerciseId)
        async let sessTask = WorkoutService.getSession(sessionId)
        async let setsTask = WorkoutService.getSetsFor(sessionId: sessionId, exerciseId: exerciseId)

        exercise    = (try? await exTask)   ?? nil
        let sess    = (try? await sessTask) ?? nil
        sessionDate = sess?.startedAt ?? Date()

        // A session is a backfill if it's already ended OR started more than 12 hours ago
        let sessionAge = Date().timeIntervalSince(sess?.startedAt ?? Date())
        isBackfill = sess?.endedAt != nil || sessionAge > 12 * 3600

        let allSets = (try? await setsTask) ?? []
        sets = allSets

        // Load plan exercise data BEFORE seeding stepper so defaults are available
        if let planId = sess?.planId,
           let planWithExercises = try? await PlanService.getPlanWithExercises(planId) {
            planExercise = planWithExercises.exercises
                .first { $0.exercise.id == exerciseId }?
                .planExercise
        }

        // Load exercise note
        exerciseNote = (try? await WorkoutService.getExerciseNote(
            sessionId: sessionId, exerciseId: exerciseId)) ?? ""

        seedStepperValues(from: allSets)

        // Per-exercise rest duration takes priority over global setting
        restDuration = planExercise?.restSeconds
            ?? authManager.user?.settings.restTimer.durationSeconds
            ?? 90
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

        // If there's a placeholder (incomplete) set, complete it instead of creating a new one
        let loggedSet: SessionSet?
        if let placeholder = sets.first(where: { !$0.isCompleted }) {
            try? await WorkoutService.updateSet(placeholder.id, patch: SetPatch(
                reps: Int(reps),
                weight: weightInKg,
                isCompleted: true
            ))
            loggedSet = placeholder
        } else {
            let newSet = try? await WorkoutService.addSet(sessionId: sessionId, exerciseId: exerciseId)
            if let s = newSet {
                try? await WorkoutService.updateSet(s.id, patch: SetPatch(
                    reps: Int(reps),
                    weight: weightInKg
                ))
            }
            loggedSet = newSet
        }
        // Start rest timer after logging — but not when backfilling old sessions
        let restEnabled = authManager.user?.settings.restTimer.enabled ?? true
        if restEnabled && !isBackfill {
            if let gid = loggedSet?.groupId {
                let roundDone = (try? await WorkoutService.isGroupRoundComplete(
                    sessionId: sessionId, groupId: gid)) ?? false
                if roundDone {
                    RestTimerManager.shared.start(seconds: restDuration)
                }
            } else {
                RestTimerManager.shared.start(seconds: restDuration)
            }
        }
        await reloadSets()
    }

    private func changeSetType(set: SessionSet, newType: SetType) async {
        try? await WorkoutService.updateSet(set.id, patch: SetPatch(setType: newType))
        await reloadSets()
    }

    private func updateSelectedSet() async {
        guard let id = selectedSetId else { return }
        try? await WorkoutService.updateSet(id, patch: SetPatch(
            reps: Int(reps),
            weight: weightInKg
        ))
        selectedSetId = nil
        await reloadSets()
    }

    private func deleteSelectedSet() async {
        guard let id = selectedSetId else { return }

        // If this set is a plan template placeholder, revert to incomplete instead of deleting
        if let plan = planExercise, sets.count <= plan.targetSets {
            try? await WorkoutService.updateSet(id, patch: SetPatch(
                reps: plan.defaultReps,
                weight: plan.targetWeight,
                isCompleted: false
            ))
        } else {
            try? await WorkoutService.deleteSet(id)
        }

        selectedSetId = nil
        await reloadSets()
    }

    private func saveNote() async {
        let trimmed = exerciseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await WorkoutService.setExerciseNote(
            sessionId: sessionId, exerciseId: exerciseId, note: trimmed.isEmpty ? nil : trimmed
        )
    }

    private func reloadSets() async {
        let allSets = (try? await WorkoutService.getSetsFor(
            sessionId: sessionId, exerciseId: exerciseId)) ?? []

        // Renumber: completed first, then placeholders, sequential from 1
        let completed = allSets.filter { $0.isCompleted }
        let placeholders = allSets.filter { !$0.isCompleted }
        var ordered = completed + placeholders

        for i in ordered.indices {
            let correctNumber = i + 1
            if ordered[i].setNumber != correctNumber {
                try? await WorkoutService.updateSet(ordered[i].id, patch: SetPatch(setNumber: correctNumber))
                ordered[i].setNumber = correctNumber
            }
        }

        sets = ordered
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
