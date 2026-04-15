import SwiftUI

// MARK: - ExerciseLogTabView
//
// The "Log" tab content of ExerciseLogView: stepper controls, optional rest timer,
// action buttons, and the logged-sets timeline. Extracted to keep ExerciseLogView
// under the 400-line limit.

struct ExerciseLogTabView: View {
    let sets: [SessionSet]
    let restDuration: Int
    let weightUnit: String
    let weightIncrement: Double
    let selectedSetId: String?
    var isBackfill: Bool = false

    @Binding var exerciseNote: String
    @Binding var weight: Double
    @Binding var reps: Double

    var onAdd: () -> Void           = {}
    var onUpdate: () -> Void        = {}
    var onDelete: () -> Void        = {}
    var onChangeSetType: (SessionSet, SetType) -> Void = { _, _ in }
    var onSelectSet: (SessionSet?) -> Void = { _ in }
    var onSaveNote: () -> Void      = {}

    @Environment(\.shiftColors) private var colors
    @FocusState private var noteIsFocused: Bool
    @State private var showNoteField = false

    private var timer: RestTimerManager { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepperRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if timer.isActive && !isBackfill {
                    RestTimerView(duration: restDuration, onDismiss: {})
                        .padding(.horizontal, 16)
                }

                actionButtons
                    .padding(.horizontal, 16)

                notesSection
                    .padding(.horizontal, 16)

                if !sets.isEmpty {
                    setTimeline
                }

                Spacer().frame(height: 24)
            }
        }
    }

    // MARK: - Stepper row

    private var stepperRow: some View {
        HStack(spacing: 16) {
            StepperControl(
                label: "Weight (\(weightUnit))",
                value: $weight,
                step: weightIncrement,
                allowDecimal: true
            )
            .frame(maxWidth: .infinity)

            StepperControl(
                label: "Reps",
                value: $reps,
                step: 1,
                allowDecimal: false
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                selectedSetId != nil ? onUpdate() : onAdd()
            } label: {
                Text(selectedSetId != nil ? "Update" :
                     sets.contains(where: { !$0.isCompleted }) ? "Log set" : "Add set")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if selectedSetId != nil {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.danger)
                        .frame(width: 46, height: 46)
                        .background(colors.danger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Notes section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showNoteField || !exerciseNote.isEmpty {
                // Expanded note editor
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                        Text("Note")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.muted)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()

                        // Done button (dismiss keyboard)
                        if noteIsFocused {
                            Button {
                                noteIsFocused = false
                                onSaveNote()
                            } label: {
                                Text("Done")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.accent)
                            }
                            .buttonStyle(.plain)
                        }

                        // Delete note button
                        if !exerciseNote.isEmpty {
                            Button {
                                exerciseNote = ""
                                noteIsFocused = false
                                showNoteField = false
                                onSaveNote()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.danger)
                                    .padding(6)
                                    .background(colors.danger.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("How did this exercise feel?", text: $exerciseNote, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.text)
                        .lineLimit(1...4)
                        .focused($noteIsFocused)
                        .padding(10)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(noteIsFocused ? colors.accent : colors.border, lineWidth: 1)
                        )
                        .onChange(of: noteIsFocused) {
                            if !noteIsFocused { onSaveNote() }
                        }
                        .onAppear {
                            if showNoteField && exerciseNote.isEmpty {
                                noteIsFocused = true
                            }
                        }
                }
            } else {
                // Collapsed — small "Add note" button
                Button {
                    showNoteField = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add note")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(colors.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colors.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Set timeline

    /// Compute working-set numbers that skip warmup sets.
    /// Warmups show "W", then normal/drop/failure sets count 1, 2, 3...
    private var workingSetNumbers: [String: Int] {
        var map: [String: Int] = [:]
        var counter = 0
        for s in sets where s.isCompleted {
            if s.setType != .warmup {
                counter += 1
                map[s.id] = counter
            }
        }
        return map
    }

    private var setTimeline: some View {
        let completedSets = sets.filter { $0.isCompleted }
        let placeholderSets = sets.filter { !$0.isCompleted }

        return VStack(alignment: .leading, spacing: 0) {
            if !completedSets.isEmpty {
                Text("Logged sets")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                let numbers = workingSetNumbers
                ForEach(completedSets) { set in
                    timelineRow(set, workingNumber: numbers[set.id])
                }
            }

            if !placeholderSets.isEmpty {
                Text("Remaining")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, completedSets.isEmpty ? 0 : 16)
                    .padding(.bottom, 8)

                ForEach(placeholderSets) { set in
                    placeholderRow(set)
                }
            }
        }
    }

    @ViewBuilder
    private func placeholderRow(_ set: SessionSet) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(colors.border.opacity(0.4)).frame(width: 1)
                Circle().stroke(colors.border, lineWidth: 1).frame(width: 8, height: 8)
                Rectangle().fill(colors.border.opacity(0.4)).frame(width: 1)
            }
            .frame(width: 8)
            .padding(.leading, 16)

            Text("Set \(set.setNumber)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.muted)

            Spacer()

            let repsText = set.reps > 0 ? "\(set.reps) reps" : "—"
            let weightText: String = {
                if let w = set.weight, w > 0 {
                    return formatWeight(w, unit: weightUnit)
                }
                return "—"
            }()
            Text("\(weightText) × \(repsText)")
                .font(.system(size: 13))
                .foregroundStyle(colors.muted)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
        .opacity(0.5)
    }

    @ViewBuilder
    private func timelineRow(_ set: SessionSet, workingNumber: Int?) -> some View {
        let isSelected = selectedSetId == set.id
        // Override the set's badgeLabel to use working-set numbering
        let displaySet: SessionSet = {
            var copy = set
            if set.setType == .normal, let num = workingNumber {
                copy.setNumber = num
            }
            return copy
        }()

        Button {
            if isSelected {
                onSelectSet(nil)
            } else {
                onSelectSet(set)
            }
        } label: {
            HStack(spacing: 12) {
                // Vertical line + dot
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(colors.border)
                        .frame(width: 1)
                    Circle()
                        .fill(isSelected ? colors.accent : colors.border)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(colors.border)
                        .frame(width: 1)
                }
                .frame(width: 8)
                .padding(.leading, 16)

                // Set type badge (tappable menu on the number)
                SetTypeMenuButton(set: displaySet) { newType in
                    onChangeSetType(set, newType)
                }

                let weightText: String = {
                    if let w = set.weight {
                        return formatWeight(w, unit: weightUnit)
                    }
                    return "BW"
                }()

                Text(weightText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)

                Text("×")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)

                Text(pluralise(set.reps, "rep"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.text)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                }

                // Three-dot menu
                Menu {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Button {
                            onChangeSetType(set, type)
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 10)
            .background(isSelected ? colors.accent.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
