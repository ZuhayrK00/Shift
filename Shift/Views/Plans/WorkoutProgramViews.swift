import SwiftUI

struct WorkoutProgramCard: View {
    @Environment(\.shiftColors) private var colors

    let program: WorkoutProgramSummary
    let isStarting: Bool
    let onOpen: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: program.source == "ai" ? "sparkles" : "rectangle.stack.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                        .background(colors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(program.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(colors.text)
                                .lineLimit(1)
                            if program.isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(colors.success)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colors.success.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(program.workouts.count)-workout rotation")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let next = program.nextWorkout {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(colors.muted)
                            .tracking(0.7)
                        Text(next.plan.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: onStart) {
                        HStack(spacing: 6) {
                            if isStarting {
                                ProgressView().tint(colors.onAccent).scaleEffect(0.75)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                            }
                            Text("Start")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(colors.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(colors.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                }
                .padding(12)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.border, lineWidth: 1))
    }
}

struct WorkoutProgramDetailView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager
    @State private var program: WorkoutProgramSummary
    let onMakeActive: () -> Void
    let onChanged: () -> Void
    @State private var becameActive = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showAddWorkout = false
    @State private var newWorkoutName = ""
    @State private var removeCandidate: WorkoutPlanWithCount?
    @State private var isWorking = false
    @State private var actionError: String?

    init(
        program: WorkoutProgramSummary,
        onMakeActive: @escaping () -> Void,
        onChanged: @escaping () -> Void = {}
    ) {
        _program = State(initialValue: program)
        self.onMakeActive = onMakeActive
        self.onChanged = onChanged
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !program.isActive && !becameActive {
                        Button {
                            becameActive = true
                            onMakeActive()
                        } label: {
                            Label("Make Active Program", systemImage: "checkmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(colors.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(Array(program.workouts.enumerated()), id: \.element.id) { index, item in
                        ProgramWorkoutManagementRow(
                            item: item,
                            index: index,
                            totalCount: program.workouts.count,
                            isWorking: isWorking,
                            onDuplicate: { Task { await duplicate(item) } },
                            onMoveEarlier: { Task { await move(item, by: -1) } },
                            onMoveLater: { Task { await move(item, by: 1) } },
                            onRemove: { removeCandidate = item }
                        )
                    }

                    Button {
                        newWorkoutName = "Workout \(program.workouts.count + 1)"
                        showAddWorkout = true
                    } label: {
                        Label("Add Workout", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
                .padding(16)
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = program.name
                        showRename = true
                    } label: {
                        Label("Rename Program", systemImage: "pencil")
                    }
                    Button {
                        skipNext()
                    } label: {
                        Label("Skip Next Workout", systemImage: "forward.end")
                    }
                    .disabled(program.workouts.count <= 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Program", isPresented: $showRename) {
            TextField("Program name", text: $renameText)
            Button("Save") { Task { await renameProgram() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add Workout", isPresented: $showAddWorkout) {
            TextField("Workout name", text: $newWorkoutName)
            Button("Add") { Task { await addWorkout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a blank workout in the rotation. Add exercises after opening it.")
        }
        .alert("Remove workout?", isPresented: Binding(
            get: { removeCandidate != nil },
            set: { if !$0 { removeCandidate = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let candidate = removeCandidate else { return }
                removeCandidate = nil
                Task { await remove(candidate) }
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: {
            Text("The saved workout and its exercises will be deleted. Completed workout history is kept.")
        }
        .alert("Couldn't update program", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Please try again.")
        }
    }

    private func renameProgram() async {
        await perform {
            try await PlanService.renameProgram(program.id, name: renameText)
        }
    }

    private func addWorkout() async {
        await perform {
            try await PlanService.addBlankProgramWorkout(
                programID: program.id,
                name: newWorkoutName
            )
        }
    }

    private func duplicate(_ item: WorkoutPlanWithCount) async {
        await perform {
            try await PlanService.duplicateProgramWorkout(
                programID: program.id,
                planID: item.plan.id
            )
        }
    }

    private func remove(_ item: WorkoutPlanWithCount) async {
        await perform {
            try await PlanService.removeProgramWorkout(
                programID: program.id,
                planID: item.plan.id
            )
        }
    }

    private func move(_ item: WorkoutPlanWithCount, by offset: Int) async {
        guard let index = program.workouts.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard program.workouts.indices.contains(destination) else { return }
        var ids = program.workouts.map(\.plan.id)
        ids.swapAt(index, destination)
        await perform {
            try await PlanService.reorderProgram(program.id, planIDs: ids)
        }
    }

    private func skipNext() {
        guard let userID = authManager.currentUserId else { return }
        WorkoutProgramService.skipNextWorkout(in: program, userID: userID)
        Task { await reload() }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            onChanged()
            await reload()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func reload() async {
        guard let userID = authManager.currentUserId else { return }
        let plans = (try? await PlanService.listPlans()) ?? []
        let completed = (try? await SessionRepository.findCompleted(userId: userID)) ?? []
        let summaries = WorkoutProgramService.summaries(
            plans: plans,
            completedSessions: completed,
            userID: userID
        )
        if let refreshed = summaries.programs.first(where: { $0.id == program.id }) {
            program = refreshed
        }
    }
}

private struct ProgramWorkoutManagementRow: View {
    @Environment(\.shiftColors) private var colors

    let item: WorkoutPlanWithCount
    let index: Int
    let totalCount: Int
    let isWorking: Bool
    let onDuplicate: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: item.plan) {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 30, height: 30)
                        .background(colors.accent.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.plan.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(action: onMoveEarlier) {
                    Label("Move Earlier", systemImage: "arrow.up")
                }
                .disabled(index == 0)
                Button(action: onMoveLater) {
                    Label("Move Later", systemImage: "arrow.down")
                }
                .disabled(index == totalCount - 1)
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Program", systemImage: "trash")
                }
                .disabled(totalCount <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .frame(width: 32, height: 32)
            }
            .disabled(isWorking)
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(colors.border, lineWidth: 1))
    }

    private var subtitle: String {
        let exercises = pluralise(item.exerciseCount, "exercise")
        let duration = WorkoutDurationEstimator.formatDuration(minutes: item.estimatedMinutes)
        return "\(exercises) · \(duration)"
    }
}
