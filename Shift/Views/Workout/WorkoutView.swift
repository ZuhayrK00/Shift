import SwiftUI

// MARK: - ExerciseBlock

/// Groups an exercise with its logged sets inside a workout session.
struct ExerciseBlock: Identifiable {
    var exercise: Exercise
    var sets: [SessionSet]
    /// groupId from sets, used to identify supersets.
    var groupId: String? { sets.first?.groupId }
    /// Exercise note stored on the first set that has one.
    var note: String? { sets.first(where: { $0.notes != nil && !($0.notes?.isEmpty ?? true) })?.notes }
    var id: String { exercise.id }
}

// MARK: - WorkoutView

/// Active workout overview screen.
struct WorkoutView: View {
    let sessionId: String

    @Environment(\.shiftColors)  private var colors
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme)  private var colorScheme
    @Environment(AuthManager.self) private var authManager

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }
    private var timer: RestTimerManager { .shared }

    @State private var session: WorkoutSession?
    @State private var blocks: [ExerciseBlock]  = []
    @State private var planExerciseMap: [String: PlanExercise] = [:]
    @State private var pickerOpen               = false
    @State private var loading                  = true
    @State private var showFinishAlert          = false
    @State private var showDiscardAlert         = false
    @State private var sessionCalories: Double?
    @State private var sessionAvgHeartRate: Double?
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

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
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                SharePreviewSheet(image: shareImage)
            }
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
                // Completed summary or in-progress stats
                if isCompleted {
                    completedSummary
                } else {
                    // Rest timer (visible when active)
                    if timer.isActive {
                        CompactRestTimerView()
                    }

                    // Stats row
                    statsRow
                }

                // Exercise blocks — group consecutive same-groupId blocks
                ForEach(groupedBlocks, id: \.id) { group in
                    if group.blocks.count == 1, let block = group.blocks.first {
                        if isCompleted {
                            ExerciseCard(
                                exercise: block.exercise,
                                sets: block.sets,
                                planExercise: planExerciseMap[block.exercise.id],
                                weightUnit: weightUnit,
                                note: block.note,
                                readOnly: true
                            )
                        } else {
                            exerciseCardView(block: block)
                        }
                    } else {
                        SupersetContainerView(
                            blocks: group.blocks,
                            sessionId: sessionId,
                            planExerciseMap: planExerciseMap,
                            weightUnit: weightUnit,
                            readOnly: isCompleted,
                            onRemove: { exId in
                                Task { await removeExercise(exerciseId: exId) }
                            },
                            onChangeSetType: { set, type in
                                Task { await changeSetType(set: set, newType: type) }
                            }
                        )
                    }
                }

                // Add exercise + discard only when in progress
                if !isCompleted {
                    addExerciseButton
                    discardButton
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Completed summary

    private var completedSummary: some View {
        VStack(spacing: 16) {
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(colors.success)
                .padding(.top, 4)

            // Duration
            if let start = session?.startedAt, let end = session?.endedAt {
                let duration = end.timeIntervalSince(start)
                let mins = Int(duration) / 60
                Text(formatDuration(mins))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colors.text)
            }

            // Stats
            HStack(spacing: 24) {
                completedStat(
                    value: "\(exerciseCount)",
                    label: exerciseCount == 1 ? "Exercise" : "Exercises",
                    icon: "dumbbell.fill"
                )
                completedStat(
                    value: "\(completedSetCount)",
                    label: completedSetCount == 1 ? "Set" : "Sets",
                    icon: "checkmark.circle"
                )
                completedStat(
                    value: totalVolume,
                    label: weightUnit,
                    icon: "scalemass"
                )
            }

            // HealthKit stats (calories + heart rate)
            if sessionCalories != nil || sessionAvgHeartRate != nil {
                HStack(spacing: 24) {
                    if let cal = sessionCalories, cal > 0 {
                        completedStat(
                            value: "\(Int(cal.rounded()))",
                            label: "kcal",
                            icon: "flame.fill"
                        )
                    }
                    if let bpm = sessionAvgHeartRate, bpm > 0 {
                        completedStat(
                            value: "\(Int(bpm.rounded()))",
                            label: "avg bpm",
                            icon: "heart.fill"
                        )
                    }
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        try? await WorkoutService.resumeSession(sessionId)
                        await loadData()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Edit")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(colors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button { shareWorkout() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Share")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(colors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func completedStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(colors.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(colors.muted)
        }
    }

    private var totalVolume: String {
        let total = blocks.flatMap { $0.sets }
            .filter { $0.isCompleted }
            .reduce(0.0) { $0 + (($1.weight ?? 0) * Double($1.reps)) }
        if total >= 1000 {
            return String(format: "%.1fk", total / 1000)
        }
        return "\(Int(total))"
    }

    private func formatDuration(_ minutes: Int) -> String {
        WorkoutDurationEstimator.formatDuration(minutes: minutes)
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
                weightUnit: weightUnit,
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

        // Fetch HealthKit stats for completed sessions
        if sess.endedAt != nil,
           authManager.user?.settings.healthKit.syncWorkouts == true {
            let start = sess.startedAt
            let end = sess.endedAt ?? Date()
            async let cal = HealthKitService.fetchCalories(from: start, to: end)
            async let hr = HealthKitService.fetchAverageHeartRate(from: start, to: end)
            sessionCalories = await cal
            sessionAvgHeartRate = await hr
        }
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

    @MainActor
    private func shareWorkout() {
        guard let session else { return }
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let mins = Int(end.timeIntervalSince(start)) / 60

        let shareBlocks: [WorkoutShareCard.ShareBlock] = blocks.map { block in
            let shareSets = block.sets.filter { $0.isCompleted }.map { set in
                WorkoutShareCard.ShareSet(
                    id: set.id, weight: set.weight, reps: set.reps, setType: set.setType
                )
            }
            return WorkoutShareCard.ShareBlock(
                id: block.exercise.id,
                name: block.exercise.displayName,
                sets: shareSets,
                note: block.note
            )
        }

        let card = WorkoutShareCard(
            workoutName: session.name,
            date: start,
            durationMinutes: mins,
            exerciseCount: exerciseCount,
            setCount: completedSetCount,
            totalVolume: totalVolume,
            weightUnit: weightUnit,
            blocks: shareBlocks,
            calories: sessionCalories,
            avgHeartRate: sessionAvgHeartRate
        )

        let renderer = ImageRenderer(content: card.environment(\.colorScheme, colorScheme))
        renderer.scale = 2.0
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
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

// MARK: - SharePreviewSheet

/// Shows a full preview of the share card with a Share button at the bottom.
private struct SharePreviewSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    @State private var showActivitySheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    // Card preview
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 32)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                    Spacer()

                    // Share button
                    Button {
                        showActivitySheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Share")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivitySheet(image: image)
            }
        }
    }
}

// MARK: - ActivitySheet

/// Wraps UIActivityViewController for sharing an image.
private struct ActivitySheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
