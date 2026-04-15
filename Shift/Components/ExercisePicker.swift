import SwiftUI

// MARK: - ExercisePicker

/// Full-screen sheet for selecting one or more exercises to add to a workout.
struct ExercisePicker: View {
    @Binding var isPresented: Bool
    var excludeIds: Set<String> = []
    /// Called when the user taps "Add". Provides selected exercises and whether
    /// they should be grouped into a superset.
    var onAdd: ([Exercise], Bool) -> Void = { _, _ in }

    @Environment(\.shiftColors) private var colors

    // MARK: - State

    @State private var searchText    = ""
    @State private var muscleFilter  = "All"
    @State private var equipFilter   = "All"
    @State private var levelFilter   = "All"
    @State private var allExercises: [Exercise] = []
    @State private var recentIds: [String]      = []
    @State private var selectedIds: [String]    = []  // ordered
    @State private var showMyExercises = false
    @State private var loading = true
    @State private var showCreateSheet = false

    // MARK: - Derived

    private var muscles: [String] {
        let all = allExercises.compactMap { $0.bodyPart ?? $0.category }
        return ["All"] + Array(Set(all)).sorted()
    }
    private var equipment: [String] {
        let all = allExercises.compactMap { $0.equipment }
        return ["All"] + Array(Set(all)).sorted()
    }
    private var levels: [String] {
        let all = allExercises.compactMap { $0.level }
        return ["All"] + Array(Set(all)).sorted()
    }

    private var filtered: [Exercise] {
        allExercises.filter { ex in
            // Muscle
            let muscleOk = muscleFilter == "All"
                || ex.bodyPart == muscleFilter
                || ex.category  == muscleFilter
            // Equipment
            let equipOk = equipFilter == "All"
                || ex.equipment == equipFilter
            // Level
            let levelOk = levelFilter == "All"
                || ex.level == levelFilter
            // Search
            let searchOk = searchText.isEmpty
                || ex.name.localizedCaseInsensitiveContains(searchText)
            // My exercises
            let mineOk = !showMyExercises || !ex.isBuiltIn
            return muscleOk && equipOk && levelOk && searchOk && mineOk
        }
    }

    private var recentExercises: [Exercise] {
        recentIds.compactMap { id in filtered.first { $0.id == id } }
    }

    private var otherExercises: [Exercise] {
        let recentSet = Set(recentIds)
        return filtered
            .filter { !recentSet.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    private var groupLabel: String {
        switch selectedIds.count {
        case 2:  return "Superset"
        case 3:  return "Tri-set"
        default: return selectedIds.count >= 4 ? "Giant set" : "Superset"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.muted)
                    TextField("Search exercises", text: $searchText)
                        .foregroundStyle(colors.text)
                        .tint(colors.accent)
                }
                .padding(10)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Filter pills row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TogglePill(label: "My Exercises", icon: "person.fill", isActive: $showMyExercises, colors: colors)
                        FilterPill(label: "Muscle", icon: "figure.strengthtraining.traditional", selected: $muscleFilter, options: muscles, colors: colors)
                        FilterPill(label: "Equipment", icon: "dumbbell.fill", selected: $equipFilter, options: equipment, colors: colors)
                        FilterPill(label: "Level", icon: "chart.bar.fill", selected: $levelFilter, options: levels, colors: colors)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().background(colors.border)

                // Exercise list
                if loading {
                    Spacer()
                    ProgressView().tint(colors.accent)
                    Spacer()
                } else {
                    exerciseList
                }

                // Bottom action bar
                if !selectedIds.isEmpty {
                    bottomBar
                }
            }
            .background(colors.bg)
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateExerciseView { newExercise in
                    allExercises.append(newExercise)
                    selectedIds.append(newExercise.id)
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Exercise list

    private var exerciseList: some View {
        List {
            if !recentExercises.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(recentExercises) { ex in
                        exerciseRow(ex)
                    }
                } header: {
                    sectionHeader("Recently used")
                }
                .listRowBackground(colors.surface)
                .listRowSeparatorTint(colors.border)
            }

            Section {
                ForEach(otherExercises) { ex in
                    exerciseRow(ex)
                }
            } header: {
                sectionHeader(searchText.isEmpty ? "All exercises" : "Results")
            }
            .listRowBackground(colors.surface)
            .listRowSeparatorTint(colors.border)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
    }

    // MARK: - Exercise row

    @ViewBuilder
    private func exerciseRow(_ ex: Exercise) -> some View {
        let isExcluded  = excludeIds.contains(ex.id)
        let selIdx      = selectedIds.firstIndex(of: ex.id)
        let isSelected  = selIdx != nil

        Button {
            guard !isExcluded else { return }
            if isSelected {
                selectedIds.removeAll { $0 == ex.id }
            } else {
                selectedIds.append(ex.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let url = ex.imageUrl.flatMap(URL.init) {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                thumbnailPlaceholder
                            }
                        }
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ex.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isExcluded ? colors.muted : colors.text)
                        if !ex.isBuiltIn {
                            Text("Custom")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(colors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colors.accent.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    if let bp = ex.bodyPart ?? ex.category {
                        Text(bp)
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                }

                Spacer()

                // Selection indicator
                if isExcluded {
                    Text("Added")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.muted)
                } else if let idx = selIdx {
                    ZStack {
                        Circle().fill(colors.accent)
                            .frame(width: 26, height: 26)
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Circle()
                        .stroke(colors.border, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // MARK: - Bottom action bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if selectedIds.count >= 2 {
                Button {
                    confirm(asGroup: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(groupLabel)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(colors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Button {
                confirm(asGroup: false)
            } label: {
                Text("Add (\(selectedIds.count))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.surface)
        .overlay(alignment: .top) {
            Divider().background(colors.border)
        }
    }

    // MARK: - Helpers

    private var thumbnailPlaceholder: some View {
        ZStack {
            colors.surface2
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 16))
                .foregroundStyle(colors.muted)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.muted)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func confirm(asGroup: Bool) {
        let exercises = selectedIds.compactMap { id in
            allExercises.first { $0.id == id }
        }
        isPresented = false
        onAdd(exercises, asGroup)
    }

    private func loadData() async {
        loading = true
        defer { loading = false }
        // ExerciseService is a static service — load all exercises
        if let exercises = try? await ExerciseService.listExercises() {
            allExercises = exercises
        }
        if let recent = try? await ExerciseService.getRecentlyUsedExerciseIds() {
            recentIds = Array(recent.prefix(10))
        }
    }
}

// MARK: - TogglePill

private struct TogglePill: View {
    let label: String
    let icon: String
    @Binding var isActive: Bool
    let colors: ShiftColors

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isActive ? .white : colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isActive
                    ? AnyShapeStyle(LinearGradient(
                        colors: [colors.accent, colors.accent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      ))
                    : AnyShapeStyle(colors.surface2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? .clear : colors.border.opacity(0.6), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FilterPill

private struct FilterPill: View {
    let label: String
    let icon: String
    @Binding var selected: String
    let options: [String]
    let colors: ShiftColors

    @State private var showPicker = false

    var isActive: Bool { selected != "All" }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(isActive ? selected : label)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isActive
                    ? AnyShapeStyle(LinearGradient(
                        colors: [colors.accent, colors.accent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      ))
                    : AnyShapeStyle(colors.surface2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? .clear : colors.border.opacity(0.6), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .confirmationDialog(label, isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selected = opt }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
