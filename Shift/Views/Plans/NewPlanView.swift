import SwiftUI

struct NewPlanView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var planName = ""
    @State private var isCreating = false
    @State private var error: String?
    @State private var createdPlan: WorkoutPlan?
    @State private var navigateToPlan = false

    var onCreate: ((WorkoutPlan) -> Void)?
    var onSaved: ((_ planName: String, _ deleted: Bool) -> Void)?

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Plan name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .padding(.bottom, 8)

                TextField("e.g. Push Day, Full Body A", text: $planName)
                    .font(.system(size: 16))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.danger)
                        .padding(.top, 8)
                }

                Spacer()

                Button {
                    Task { await createPlan() }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView().tint(.white).scaleEffect(0.9)
                        } else {
                            Text("Create plan")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(planName.trimmingCharacters(in: .whitespaces).isEmpty ? colors.accent.opacity(0.4) : colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(planName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(24)
        }
        .navigationTitle("New Plan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToPlan) {
            if let plan = createdPlan {
                PlanEditorView(plan: plan) { deleted in
                    onSaved?(plan.name, deleted)
                }
            }
        }
        .onChange(of: navigateToPlan) { _, isActive in
            // When PlanEditorView is dismissed (save or delete), also dismiss NewPlanView
            if !isActive && createdPlan != nil {
                dismiss()
            }
        }
    }

    private func createPlan() async {
        let trimmed = planName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        error = nil
        do {
            let plan = try await PlanService.createPlan(name: trimmed)
            onCreate?(plan)
            createdPlan = plan
            navigateToPlan = true
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
