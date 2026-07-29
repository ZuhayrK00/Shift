import SwiftUI

struct TrainingScheduleView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors

    let plans: [WorkoutPlan]
    @State private var assignments: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let weekdays: [(id: Int, name: String)] = [
        (1, "Monday"), (2, "Tuesday"), (3, "Wednesday"), (4, "Thursday"),
        (5, "Friday"), (6, "Saturday"), (7, "Sunday")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(weekdays, id: \.id) { day in
                    Picker(
                        day.name,
                        selection: Binding(
                            get: { assignments[String(day.id)] ?? "" },
                            set: { value in
                                assignments[String(day.id)] = value
                            }
                        )
                    ) {
                        Text("Rest day").tag("")
                        ForEach(plans) { plan in
                            Text(plan.name).tag(plan.id)
                        }
                    }
                }
            } header: {
                Text("Weekly schedule")
            } footer: {
                Text("Shift shows the right workout on Today. You can still choose any other workout.")
            }

            if plans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No saved workouts",
                        systemImage: "calendar.badge.plus",
                        description: Text("Create a workout first, then add it to your week.")
                    )
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle("Training Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            assignments = authManager.user?.settings.trainingSchedule.weeklyPlanIDs ?? [:]
        }
    }

    private func save() async {
        isSaving = true
        var settings = authManager.user?.settings ?? .default
        settings.trainingSchedule.weeklyPlanIDs = Dictionary(
            uniqueKeysWithValues: weekdays.map { day in
                (String(day.id), assignments[String(day.id)] ?? "")
            }
        )
        do {
            _ = try await ProfileService.updateSettings(settings)
            await authManager.refreshUser()
            dismiss()
        } catch {
            errorMessage = "Your schedule couldn't be saved. \(error.localizedDescription)"
        }
        isSaving = false
    }
}
