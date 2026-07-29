import SwiftUI

#if canImport(FoundationModels)
@available(iOS 26, *)
struct NaturalLanguagePlanEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors

    let plan: WorkoutPlan
    let exercises: [PlanExercise]
    let exerciseMap: [String: Exercise]
    let onApplied: () -> Void

    @State private var instruction = ""
    @State private var proposal: ConfirmedPlanEdit?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let proposal {
                        proposalView(proposal)
                    } else {
                        requestView
                    }
                }
                .padding(20)
            }
            .background(colors.bg)
            .navigationTitle("Edit with Apple Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't prepare changes", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var requestView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should change?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(colors.text)
            Text("For example: “Make this a 45-minute workout, replace barbell squats with a machine option, and use 8–12 reps.”")
                .font(.system(size: 13))
                .foregroundStyle(colors.muted)

            TextEditor(text: $instruction)
                .frame(minHeight: 130)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))

            Label(
                "Nothing changes until you review and confirm the proposal.",
                systemImage: "checkmark.shield"
            )
            .font(.system(size: 12))
            .foregroundStyle(colors.muted)

            Button {
                Task { await generate() }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(colors.onAccent) }
                    Text(isWorking ? "Preparing changes…" : "Review changes")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isWorking || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func proposalView(_ proposal: ConfirmedPlanEdit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review before applying")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(colors.text)
            Text(proposal.summary)
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)

            if let planName = proposal.planName {
                changeCard(
                    title: "Rename workout",
                    detail: planName,
                    symbol: "text.cursor"
                )
            }
            ForEach(proposal.exerciseEdits) { edit in
                changeCard(
                    title: title(for: edit),
                    detail: detail(for: edit),
                    symbol: symbol(for: edit)
                )
            }

            HStack(spacing: 10) {
                Button("Change request") {
                    self.proposal = nil
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await apply(proposal) }
                } label: {
                    HStack {
                        if isWorking { ProgressView().tint(colors.onAccent) }
                        Text(isWorking ? "Applying…" : "Apply changes")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isWorking)
            }
        }
    }

    private func changeCard(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
    }

    private func title(for edit: ConfirmedPlanExerciseEdit) -> String {
        switch edit.action {
        case .update: return "Adjust \(edit.exerciseName)"
        case .remove: return "Remove \(edit.exerciseName)"
        case .replace: return "Replace with \(edit.exerciseName)"
        case .add: return "Add \(edit.exerciseName)"
        }
    }

    private func detail(for edit: ConfirmedPlanExerciseEdit) -> String {
        if edit.action == .remove { return edit.explanation }
        return "\(edit.sets) sets · \(edit.repsMin)–\(edit.repsMax) reps · \(edit.restSeconds)s rest"
            + (edit.explanation.isEmpty ? "" : "\n\(edit.explanation)")
    }

    private func symbol(for edit: ConfirmedPlanExerciseEdit) -> String {
        switch edit.action {
        case .update: return "slider.horizontal.3"
        case .remove: return "minus.circle"
        case .replace: return "arrow.triangle.2.circlepath"
        case .add: return "plus.circle"
        }
    }

    private func generate() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let catalogue = (try? await ExerciseService.listExercises()) ?? Array(exerciseMap.values)
            proposal = try await NaturalLanguagePlanEditorService.propose(
                instruction: instruction,
                plan: plan,
                exercises: exercises,
                catalogue: catalogue
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ proposal: ConfirmedPlanEdit) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await PlanService.applyConfirmedEdit(
                planID: plan.id,
                planName: proposal.planName,
                edits: proposal.exerciseEdits
            )
            PhoneSessionManager.shared.sendContextToWatch()
            onApplied()
            dismiss()
        } catch {
            errorMessage = "The changes couldn't be saved. \(error.localizedDescription)"
        }
    }
}
#endif
