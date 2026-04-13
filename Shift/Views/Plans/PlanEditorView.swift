import SwiftUI

struct PlanEditorView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let plan: WorkoutPlan
    var onDismiss: (_ deleted: Bool) -> Void

    @State private var planName: String
    @State private var exercises: [PlanExercise] = []
    @State private var exerciseMap: [String: Exercise] = [:]
    @State private var isLoading = false
    @State private var showExercisePicker = false
    @State private var showDeleteAlert = false
    @State private var configuring: PlanExercise?
    @State private var showSavedToast = false

    init(plan: WorkoutPlan, onDismiss: @escaping (_ deleted: Bool) -> Void) {
        self.plan = plan
        self.onDismiss = onDismiss
        _planName = State(initialValue: plan.name)
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Plan name field
                TextField("Plan name", text: $planName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .onSubmit { Task { await saveName() } }

                Divider().background(colors.border)

                if isLoading {
                    Spacer()
                    ProgressView().tint(colors.accent)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if exercises.isEmpty {
                                emptyExerciseState
                            } else {
                                exerciseList
                            }

                            // Add exercises button
                            Button {
                                showExercisePicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(colors.accent)
                                    Text("Add exercises")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(colors.accent)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(colors.accent.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(colors.accent.opacity(0.3), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(colors.danger)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task {
                        await saveName()
                        dismiss()
                    }
                }
                .foregroundStyle(colors.accent)
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .task(id: plan.id) { await loadExercises() }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePicker(
                isPresented: $showExercisePicker,
                excludeIds: Set(exercises.map { $0.exerciseId })
            ) { selected, asGroup in
                Task { await addExercises(selected, asGroup: asGroup) }
            }
        }
        .sheet(item: $configuring) { pe in
            PlanExerciseConfigSheet(planExercise: pe, exercise: exerciseMap[pe.exerciseId]) { updated in
                Task { await updateExercise(updated) }
            }
        }
        .alert("Delete Plan", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task { await deletePlan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(plan.name)\" and all its exercises.")
        }
    }

    // MARK: - Exercise list

    /// Group exercises: consecutive runs sharing the same groupId form a superset block.
    private var groupedExercises: [[PlanExercise]] {
        var groups: [[PlanExercise]] = []
        for pe in exercises {
            if let gid = pe.groupId,
               let last = groups.last?.last,
               last.groupId == gid {
                groups[groups.count - 1].append(pe)
            } else {
                groups.append([pe])
            }
        }
        return groups
    }

    @ViewBuilder
    private var exerciseList: some View {
        VStack(spacing: 10) {
            ForEach(groupedExercises, id: \.first!.id) { group in
                if group.count > 1 {
                    // Superset group
                    VStack(spacing: 0) {
                        // Group header
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colors.warning)
                            Text(supersetLabel(group.count))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colors.warning)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.warning.opacity(0.08))

                        ForEach(group) { pe in
                            PlanExerciseRow(
                                planExercise: pe,
                                exercise: exerciseMap[pe.exerciseId]
                            ) {
                                configuring = pe
                            } onDelete: {
                                Task { await removeExercise(pe) }
                            }

                            if pe.id != group.last?.id {
                                Divider()
                                    .background(colors.border)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.warning.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let pe = group.first {
                    // Single exercise
                    VStack(spacing: 0) {
                        PlanExerciseRow(
                            planExercise: pe,
                            exercise: exerciseMap[pe.exerciseId]
                        ) {
                            configuring = pe
                        } onDelete: {
                            Task { await removeExercise(pe) }
                        }
                    }
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func supersetLabel(_ count: Int) -> String {
        switch count {
        case 2: return "Superset"
        case 3: return "Tri-set"
        default: return "Giant set"
        }
    }

    private var emptyExerciseState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 36))
                .foregroundStyle(colors.muted)
            Text("No exercises yet")
                .font(.system(size: 15))
                .foregroundStyle(colors.muted)
            Text("Add exercises to build your plan.")
                .font(.system(size: 13))
                .foregroundStyle(colors.muted.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func loadExercises() async {
        isLoading = true
        let enriched = (try? await PlanService.getPlanWithExercises(plan.id))?.exercises ?? []
        exercises = enriched.map { $0.planExercise }
        exerciseMap = Dictionary(enriched.map { ($0.exercise.id, $0.exercise) }, uniquingKeysWith: { _, last in last })
        isLoading = false
    }

    private func saveName() async {
        let trimmed = planName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? await PlanService.updatePlan(plan.id, name: trimmed, notes: nil)
        onDismiss(false)
    }

    private func addExercises(_ selected: [Exercise], asGroup: Bool) async {
        let ids = selected.map { $0.id }
        guard let added = try? await PlanService.addExercises(
            planId: plan.id,
            exerciseIds: ids,
            asGroup: asGroup
        ) else { return }
        exercises.append(contentsOf: added)
        for ex in selected { exerciseMap[ex.id] = ex }
    }

    private func updateExercise(_ updated: PlanExercise) async {
        let patch = PlanExercisePatch(
            targetSets: updated.targetSets,
            targetRepsMin: updated.targetRepsMin,
            targetRepsMax: updated.targetRepsMax,
            targetWeight: updated.targetWeight,
            restSeconds: updated.restSeconds
        )
        try? await PlanService.updateExercise(updated.id, patch: patch)
        if let idx = exercises.firstIndex(where: { $0.id == updated.id }) {
            exercises[idx] = updated
        }
    }

    private func removeExercise(_ pe: PlanExercise) async {
        try? await PlanService.removeExercise(pe.id)
        exercises.removeAll { $0.id == pe.id }
    }

    private func deletePlan() async {
        try? await PlanService.deletePlan(plan.id)
        onDismiss(true)
        dismiss()
    }
}

// MARK: - PlanExerciseRow

private struct PlanExerciseRow: View {
    @Environment(\.shiftColors) private var colors
    let planExercise: PlanExercise
    let exercise: Exercise?
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Position badge
            Text("\(planExercise.position + 1)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(colors.accent)
                .frame(width: 28, height: 28)
                .background(colors.accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise?.name ?? "Exercise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Text(planExercise.subtitle())
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.danger)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// ExercisePickerSheet and PlanExerciseConfigSheet live in PlanSheets.swift
