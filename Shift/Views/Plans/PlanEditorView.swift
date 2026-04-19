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
    @State private var errorMessage: String?

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
                } else if exercises.isEmpty {
                    ScrollView {
                        emptyExerciseState
                        addExercisesButton
                    }
                } else {
                    List {
                        ForEach(exercises) { pe in
                            PlanExerciseRow(
                                planExercise: pe,
                                exercise: exerciseMap[pe.exerciseId],
                                position: exercises.firstIndex(where: { $0.id == pe.id }).map { $0 + 1 } ?? 0
                            ) {
                                configuring = pe
                            } onDelete: {
                                Task { await removeExercise(pe) }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { source, destination in
                            exercises.move(fromOffsets: source, toOffset: destination)
                            Task { await saveExerciseOrder() }
                        }

                        addExercisesButton
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 32, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
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
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var addExercisesButton: some View {
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
        do {
            try await PlanService.updatePlan(plan.id, name: trimmed, notes: nil)
        } catch {
            errorMessage = "Failed to save plan name: \(error.localizedDescription)"
            return
        }
        PhoneSessionManager.shared.sendContextToWatch()
        onDismiss(false)
    }

    private func addExercises(_ selected: [Exercise], asGroup: Bool) async {
        let ids = selected.map { $0.id }
        do {
            let added = try await PlanService.addExercises(
                planId: plan.id,
                exerciseIds: ids,
                asGroup: asGroup
            )
            exercises.append(contentsOf: added)
            for ex in selected { exerciseMap[ex.id] = ex }
            PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            errorMessage = "Failed to add exercises: \(error.localizedDescription)"
        }
    }

    private func updateExercise(_ updated: PlanExercise) async {
        let patch = PlanExercisePatch(
            targetSets: updated.targetSets,
            targetRepsMin: updated.targetRepsMin,
            targetRepsMax: updated.targetRepsMax,
            targetWeight: updated.targetWeight,
            restSeconds: updated.restSeconds
        )
        do {
            try await PlanService.updateExercise(updated.id, patch: patch)
            if let idx = exercises.firstIndex(where: { $0.id == updated.id }) {
                exercises[idx] = updated
            }
            PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            errorMessage = "Failed to update exercise: \(error.localizedDescription)"
        }
    }

    private func removeExercise(_ pe: PlanExercise) async {
        do {
            try await PlanService.removeExercise(pe.id)
            exercises.removeAll { $0.id == pe.id }
            PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            errorMessage = "Failed to remove exercise: \(error.localizedDescription)"
        }
    }

    private func saveExerciseOrder() async {
        do {
            try await PlanService.reorderExercises(
                planId: plan.id,
                exerciseIds: exercises.map { $0.id }
            )
            // Update local position values
            for i in exercises.indices {
                exercises[i].position = i
            }
            PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            errorMessage = "Failed to reorder exercises: \(error.localizedDescription)"
        }
    }

    private func deletePlan() async {
        do {
            try await PlanService.deletePlan(plan.id)
            PhoneSessionManager.shared.sendContextToWatch()
            onDismiss(true)
            dismiss()
        } catch {
            errorMessage = "Failed to delete plan: \(error.localizedDescription)"
        }
    }
}

// MARK: - PlanExerciseRow

private struct PlanExerciseRow: View {
    @Environment(\.shiftColors) private var colors
    let planExercise: PlanExercise
    let exercise: Exercise?
    var position: Int = 0
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Position badge
            Text("\(position)")
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// ExercisePickerSheet and PlanExerciseConfigSheet live in PlanSheets.swift
