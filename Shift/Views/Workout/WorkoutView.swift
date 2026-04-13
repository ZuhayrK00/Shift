import SwiftUI

// MARK: - ExerciseBlock

/// Groups an exercise with its logged sets inside a workout session.
struct ExerciseBlock: Identifiable {
    var exercise: Exercise
    var sets: [SessionSet]
    /// groupId from sets, used to identify supersets.
    var groupId: String? { sets.first?.groupId }
    var id: String { exercise.id }
}

// MARK: - WorkoutView

/// Active workout overview screen.
struct WorkoutView: View {
    let sessionId: String

    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss)    private var dismiss

    @State private var session: WorkoutSession?
    @State private var blocks: [ExerciseBlock]  = []
    @State private var planExerciseMap: [String: PlanExercise] = [:]
    @State private var pickerOpen               = false
    @State private var loading                  = true
    @State private var showFinishAlert          = false
    @State private var showDiscardAlert         = false

    // True once the session has an endedAt timestamp
    private var isCompleted: Bool { session?.endedAt != nil }

    // Computed stats
    private var exerciseCount: Int { blocks.count }
    private var completedSetCount: Int {
        blocks.flatMap { $0.sets }.filter { $0.isCompleted }.count
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            if loading {
                ProgressView()
                    .tint(colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }
        }
        .navigationTitle(session?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar { toolbarContent }
        .sheet(isPresented: $pickerOpen) {
            ExercisePicker(
                isPresented: $pickerOpen,
                excludeIds: Set(blocks.map { $0.exercise.id })
            ) { exercises, isGroup in
                Task { await addExercises(exercises, asGroup: isGroup) }
            }
        }
        .alert("Finish workout?", isPresented: $showFinishAlert) {
            Button("Finish", role: .none) { Task { await finishWorkout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the session as complete.")
        }
        .alert("Discard workout?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { Task { await discardWorkout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sets will be deleted and this session will be removed.")
        }
        .navigationDestination(for: ExerciseLogRoute.self) { route in
            ExerciseLogView(sessionId: route.sessionId, exerciseId: route.exerciseId)
        }
        .task { await loadData() }
        .onDisappear { Task { await autoDeleteIfEmpty() } }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // Completed banner
                if isCompleted {
                    completedBanner
                }

                // Stats row
                statsRow

                // Exercise blocks — group consecutive same-groupId blocks
                ForEach(groupedBlocks, id: \.id) { group in
                    if group.blocks.count == 1, let block = group.blocks.first {
                        exerciseCardView(block: block)
                    } else {
                        SupersetContainerView(
                            blocks: group.blocks,
                            sessionId: sessionId,
                            planExerciseMap: planExerciseMap,
                            onRemove: { exId in
                                Task { await removeExercise(exerciseId: exId) }
                            },
                            onChangeSetType: { set, type in
                                Task { await changeSetType(set: set, newType: type) }
                            }
                        )
                    }
                }

                // Add exercise button
                addExerciseButton

                // Discard button
                if !isCompleted {
                    discardButton
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Completed banner

    private var completedBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(colors.success)
                .frame(width: 10, height: 10)
            Text("Completed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.success)
            Spacer()
            Button("Edit workout") {
                Task {
                    try? await WorkoutService.resumeSession(sessionId)
                    await loadData()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.success.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 14) {
            statPill(
                value: "\(exerciseCount)",
                label: exerciseCount == 1 ? "Exercise" : "Exercises",
                icon: "dumbbell.fill"
            )
            statPill(
                value: "\(completedSetCount)",
                label: completedSetCount == 1 ? "Set" : "Sets",
                icon: "checkmark.circle.fill"
            )
            Spacer()
        }
    }

    @ViewBuilder
    private func statPill(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(colors.accent)
            Text("\(value) \(label)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Individual exercise card

    @ViewBuilder
    private func exerciseCardView(block: ExerciseBlock) -> some View {
        NavigationLink(value: ExerciseLogRoute(
            sessionId: sessionId,
            exerciseId: block.exercise.id
        )) {
            ExerciseCard(
                exercise: block.exercise,
                sets: block.sets,
                planExercise: planExerciseMap[block.exercise.id],
                onRemove: {
                    Task { await removeExercise(exerciseId: block.exercise.id) }
                },
                onChangeSetType: { set, newType in
                    Task { await changeSetType(set: set, newType: newType) }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add exercise button

    private var addExerciseButton: some View {
        Button {
            pickerOpen = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add exercise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discard button

    private var discardButton: some View {
        Button {
            showDiscardAlert = true
        } label: {
            Text("Discard workout")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isCompleted {
            ToolbarItem(placement: .primaryAction) {
                Button("Finish") {
                    showFinishAlert = true
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.success)
            }
        }
    }

    // MARK: - Grouped blocks helper

    private struct BlockGroup: Identifiable {
        var id: String
        var blocks: [ExerciseBlock]
    }

    /// Groups consecutive blocks that share the same non-nil groupId.
    private var groupedBlocks: [BlockGroup] {
        var result: [BlockGroup] = []
        var currentGroupId: String? = nil
        var buffer: [ExerciseBlock] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            let id = buffer.map { $0.id }.joined(separator: "+")
            result.append(BlockGroup(id: id, blocks: buffer))
            buffer = []
        }

        for block in blocks {
            let gid = block.groupId
            if let gid {
                if gid == currentGroupId {
                    buffer.append(block)
                } else {
                    flush()
                    currentGroupId = gid
                    buffer = [block]
                }
            } else {
                flush()
                currentGroupId = nil
                result.append(BlockGroup(id: block.id, blocks: [block]))
            }
        }
        flush()
        return result
    }

    // MARK: - Actions

    private func loadData() async {
        loading = true
        defer { loading = false }

        guard let sess = try? await WorkoutService.getSession(sessionId) else { return }
        session = sess

        // Load plan exercise templates if this session was started from a plan
        if let planId = sess.planId,
           let planData = try? await PlanService.getPlanWithExercises(planId) {
            var map: [String: PlanExercise] = [:]
            for enriched in planData.exercises {
                map[enriched.exercise.id] = enriched.planExercise
            }
            planExerciseMap = map
        } else {
            planExerciseMap = [:]
        }

        let exerciseIds = (try? await WorkoutService.getSessionExerciseIds(sessionId)) ?? []
        var newBlocks: [ExerciseBlock] = []
        for exId in exerciseIds {
            guard let ex = try? await ExerciseService.getById(exId) else { continue }
            let sets = (try? await WorkoutService.getSetsFor(
                sessionId: sessionId,
                exerciseId: exId
            )) ?? []
            newBlocks.append(ExerciseBlock(exercise: ex, sets: sets))
        }
        blocks = newBlocks
    }

    private func addExercises(_ exercises: [Exercise], asGroup: Bool) async {
        let ids = exercises.map { $0.id }
        try? await WorkoutService.addExercisesToSession(sessionId, exerciseIds: ids, asGroup: asGroup)
        await loadData()
    }

    private func removeExercise(exerciseId: String) async {
        try? await WorkoutService.removeExercise(sessionId: sessionId, exerciseId: exerciseId)
        await loadData()
    }

    private func changeSetType(set: SessionSet, newType: SetType) async {
        try? await WorkoutService.updateSet(set.id, patch: SetPatch(setType: newType))
        await loadData()
    }

    private func finishWorkout() async {
        try? await WorkoutService.finishSession(sessionId)
        await loadData()
    }

    private func discardWorkout() async {
        try? await WorkoutService.deleteSession(sessionId)
        dismiss()
    }

    private func autoDeleteIfEmpty() async {
        guard !isCompleted else { return }
        let ids = (try? await WorkoutService.getSessionExerciseIds(sessionId)) ?? []
        if ids.isEmpty {
            try? await WorkoutService.deleteSession(sessionId)
        }
    }

}

// MARK: - ExerciseLogRoute

/// Hashable value used with .navigationDestination.
struct ExerciseLogRoute: Hashable {
    let sessionId: String
    let exerciseId: String
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorkoutView(sessionId: "preview-session")
            .shiftTheme()
            .environment(AuthManager())
    }
    .preferredColorScheme(.dark)
}
