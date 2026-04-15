import SwiftUI

// MARK: - CreateExerciseView

/// Form for creating or editing a custom exercise.
struct CreateExerciseView: View {
    /// Pass an existing exercise to edit it. Leave nil to create a new one.
    var existingExercise: Exercise? = nil
    var onSave: ((Exercise) -> Void)? = nil

    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedMuscleId: String?
    @State private var selectedEquipment: String?
    @State private var instructions = ""
    @State private var selectedLevel: String?
    @State private var selectedCategory: String?
    @State private var muscles: [MuscleGroup] = []
    @State private var saving = false
    @State private var saveError: String?

    @State private var showMusclePicker = false
    @State private var showEquipmentPicker = false
    @State private var showLevelPicker = false
    @State private var showCategoryPicker = false

    private var isEditing: Bool { existingExercise != nil }

    private let equipmentOptions = [
        "Barbell", "Dumbbell", "Cable", "Machine",
        "Bodyweight", "Kettlebell", "Bands", "Other"
    ]
    private let levelOptions = ["beginner", "intermediate", "expert"]
    private let categoryOptions = ["Strength", "Stretching", "Cardio", "Plyometrics"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedMuscleId != nil
    }

    private var selectedMuscleName: String? {
        guard let id = selectedMuscleId else { return nil }
        return muscles.first { $0.id == id }?.name
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    // Name
                    Section {
                        TextField("Exercise name", text: $name)
                            .font(.system(size: 15))
                            .foregroundStyle(colors.text)
                    } header: {
                        Text("Name *")
                    }
                    .listRowBackground(colors.surface)

                    // Pickers
                    Section {
                        // Primary muscle group
                        pickerRow(
                            label: "Muscle Group",
                            value: selectedMuscleName,
                            required: true
                        ) { showMusclePicker = true }

                        // Equipment
                        pickerRow(
                            label: "Equipment",
                            value: selectedEquipment
                        ) { showEquipmentPicker = true }

                        // Level
                        pickerRow(
                            label: "Level",
                            value: selectedLevel?.capitalized
                        ) { showLevelPicker = true }

                        // Category
                        pickerRow(
                            label: "Category",
                            value: selectedCategory
                        ) { showCategoryPicker = true }
                    } header: {
                        Text("Details")
                    }
                    .listRowBackground(colors.surface)

                    // Instructions
                    Section {
                        TextField("How to perform this exercise…", text: $instructions, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.text)
                            .lineLimit(3...8)
                    } header: {
                        Text("Instructions")
                    }
                    .listRowBackground(colors.surface)

                    // Error
                    if let saveError {
                        Section {
                            Text(saveError)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger)
                        }
                        .listRowBackground(colors.danger.opacity(0.1))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSave ? colors.accent : colors.muted)
                    .disabled(!canSave || saving)
                }
            }
            .task { await loadMuscles() }
            .onAppear { prefill() }
            .sheet(isPresented: $showMusclePicker) {
                FilterPickerSheet(
                    title: "Muscle Group",
                    options: muscles.map { (id: $0.id, label: $0.name) },
                    selected: $selectedMuscleId
                )
            }
            .sheet(isPresented: $showEquipmentPicker) {
                FilterPickerSheet(
                    title: "Equipment",
                    options: equipmentOptions.map { (id: $0, label: $0) },
                    selected: $selectedEquipment
                )
            }
            .sheet(isPresented: $showLevelPicker) {
                FilterPickerSheet(
                    title: "Level",
                    options: levelOptions.map { (id: $0, label: $0.capitalized) },
                    selected: $selectedLevel
                )
            }
            .sheet(isPresented: $showCategoryPicker) {
                FilterPickerSheet(
                    title: "Category",
                    options: categoryOptions.map { (id: $0, label: $0) },
                    selected: $selectedCategory
                )
            }
        }
    }

    // MARK: - Picker row

    @ViewBuilder
    private func pickerRow(label: String, value: String?, required: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label + (required ? " *" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(colors.text)
                Spacer()
                Text(value ?? "None")
                    .font(.system(size: 15))
                    .foregroundStyle(value != nil ? colors.accent : colors.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }
        }
    }

    // MARK: - Data

    private func loadMuscles() async {
        muscles = (try? await ExerciseService.listMuscleGroups()) ?? []
    }

    private func prefill() {
        guard let ex = existingExercise else { return }
        name = ex.name
        selectedMuscleId = ex.primaryMuscleId
        selectedEquipment = ex.equipment
        instructions = ex.instructions ?? ""
        selectedLevel = ex.level
        selectedCategory = ex.category
    }

    private func save() async {
        guard let muscleId = selectedMuscleId else { return }
        saving = true
        saveError = nil
        defer { saving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let existing = existingExercise {
                try await ExerciseService.updateExercise(
                    existing.id,
                    name: trimmedName,
                    primaryMuscleId: muscleId,
                    equipment: selectedEquipment,
                    instructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions,
                    level: selectedLevel,
                    category: selectedCategory,
                    bodyPart: selectedCategory
                )
                // Return updated exercise for caller
                if let updated = try? await ExerciseService.getById(existing.id) {
                    onSave?(updated)
                }
            } else {
                let exercise = try await ExerciseService.createExercise(
                    name: trimmedName,
                    primaryMuscleId: muscleId,
                    equipment: selectedEquipment,
                    instructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions,
                    level: selectedLevel,
                    category: selectedCategory,
                    bodyPart: selectedCategory
                )
                onSave?(exercise)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
