import SwiftUI

struct ExercisesView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var exercises: [Exercise] = []
    @State private var muscles: [MuscleGroup] = []
    @State private var recentIds: [String] = []
    @State private var searchQuery = ""
    @State private var activeMuscleId: String?
    @State private var activeEquipment: String?
    @State private var activeLevel: String?
    @State private var showMyExercises = false
    @State private var isLoading = false
    @State private var showMuscleFilter = false
    @State private var showEquipmentFilter = false
    @State private var showLevelFilter = false
    @State private var showCreateSheet = false

    private let levels = ["beginner", "intermediate", "expert"]

    private var availableEquipment: [String] {
        let all = exercises.compactMap { $0.equipment }.filter { !$0.isEmpty }
        return Array(Set(all)).sorted()
    }

    private var hasActiveFilters: Bool {
        !searchQuery.isEmpty || activeMuscleId != nil || activeEquipment != nil || activeLevel != nil || showMyExercises
    }

    private func applyFilters(_ list: [Exercise]) -> [Exercise] {
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespaces)
        return list.filter { ex in
            let matchesSearch = trimmedSearch.isEmpty
                || ex.name.localizedCaseInsensitiveContains(trimmedSearch)
            let matchesMuscle = activeMuscleId == nil
                || ex.primaryMuscleId == activeMuscleId
            let matchesEquipment = activeEquipment == nil
                || ex.equipment == activeEquipment
            let matchesLevel = activeLevel == nil
                || ex.level == activeLevel
            let matchesMine = !showMyExercises || !ex.isBuiltIn
            return matchesSearch && matchesMuscle && matchesEquipment && matchesLevel && matchesMine
        }
    }

    private var recentExercises: [Exercise] {
        guard !hasActiveFilters else { return [] }
        let recentSet = Set(recentIds)
        let map = Dictionary(uniqueKeysWithValues: exercises.filter { recentSet.contains($0.id) }.map { ($0.id, $0) })
        return recentIds.compactMap { map[$0] }
    }

    private var filtered: [Exercise] {
        let all = applyFilters(exercises)
        if hasActiveFilters { return all }
        let recentSet = Set(recentIds)
        return all.filter { !recentSet.contains($0.id) }
    }

    private func muscleName(for id: String) -> String {
        muscles.first { $0.id == id }?.name ?? id
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.muted)
                    TextField("Search exercises...", text: $searchQuery)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: "My Exercises",
                            icon: "person.fill",
                            isActive: showMyExercises
                        ) { showMyExercises.toggle() }

                        FilterChip(
                            label: activeMuscleId.flatMap { id in muscles.first { $0.id == id }?.name } ?? "Muscle",
                            icon: "figure.strengthtraining.traditional",
                            isActive: activeMuscleId != nil
                        ) { showMuscleFilter = true }

                        FilterChip(
                            label: activeEquipment ?? "Equipment",
                            icon: "dumbbell.fill",
                            isActive: activeEquipment != nil
                        ) { showEquipmentFilter = true }

                        FilterChip(
                            label: activeLevel.map { $0.capitalized } ?? "Level",
                            icon: "chart.bar.fill",
                            isActive: activeLevel != nil
                        ) { showLevelFilter = true }

                        if activeMuscleId != nil || activeEquipment != nil || activeLevel != nil || showMyExercises {
                            Button {
                                activeMuscleId = nil
                                activeEquipment = nil
                                activeLevel = nil
                                showMyExercises = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Clear")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(colors.danger.opacity(0.85))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)

                // Exercise list
                if isLoading {
                    Spacer()
                    ProgressView().tint(colors.accent)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(colors.muted)
                        Text("No exercises found")
                            .font(.system(size: 15))
                            .foregroundStyle(colors.muted)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Recent section
                            if !recentExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recent")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(colors.muted)
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                        .padding(.horizontal, 20)

                                    LazyVStack(spacing: 0) {
                                        ForEach(recentExercises) { exercise in
                                            NavigationLink(value: exercise) {
                                                ExerciseRow(
                                                    exercise: exercise,
                                                    muscleName: muscleName(for: exercise.primaryMuscleId)
                                                )
                                            }
                                            .buttonStyle(.plain)

                                            if exercise.id != recentExercises.last?.id {
                                                Divider()
                                                    .background(colors.border)
                                                    .padding(.leading, 80)
                                            }
                                        }
                                    }
                                    .background(colors.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(colors.border, lineWidth: 1)
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }

                            // All exercises
                            VStack(alignment: .leading, spacing: 8) {
                                if !recentExercises.isEmpty {
                                    Text("All Exercises")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(colors.muted)
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                        .padding(.horizontal, 20)
                                }

                                LazyVStack(spacing: 0) {
                                    ForEach(filtered) { exercise in
                                        NavigationLink(value: exercise) {
                                            ExerciseRow(
                                                exercise: exercise,
                                                muscleName: muscleName(for: exercise.primaryMuscleId)
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        Divider()
                                            .background(colors.border)
                                            .padding(.leading, 80)
                                    }
                                }
                                .background(colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
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
        .navigationDestination(for: Exercise.self) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .task { await loadData() }
        .sheet(isPresented: $showCreateSheet) {
            CreateExerciseView { _ in
                Task { await loadData() }
            }
        }
        .sheet(isPresented: $showMuscleFilter) {
            FilterPickerSheet(
                title: "Muscle Group",
                options: muscles.map { (id: $0.id, label: $0.name) },
                selected: $activeMuscleId
            )
        }
        .sheet(isPresented: $showEquipmentFilter) {
            FilterPickerSheet(
                title: "Equipment",
                options: availableEquipment.map { (id: $0, label: $0.capitalized) },
                selected: $activeEquipment
            )
        }
        .sheet(isPresented: $showLevelFilter) {
            FilterPickerSheet(
                title: "Level",
                options: levels.map { (id: $0, label: $0.capitalized) },
                selected: $activeLevel
            )
        }
    }

    private func loadData() async {
        isLoading = true
        async let muscleResult = ExerciseService.listMuscleGroups()
        async let exerciseResult = ExerciseService.listExercises()
        async let recentResult = ExerciseService.getRecentlyUsedExerciseIds()
        muscles = (try? await muscleResult) ?? []
        exercises = (try? await exerciseResult) ?? []
        recentIds = (try? await recentResult) ?? []
        isLoading = false
    }
}

// MARK: - ExerciseRow

struct ExerciseRow: View {
    @Environment(\.shiftColors) private var colors
    let exercise: Exercise
    let muscleName: String

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let urlString = exercise.imageUrl, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            initialsCircle
                        }
                    }
                } else {
                    initialsCircle
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Labels
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.text)
                        .lineLimit(1)
                    if !exercise.isBuiltIn {
                        Text("Custom")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(muscleName.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.muted)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var initialsCircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.surface2)
            Text(String(exercise.name.prefix(1)).uppercased())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colors.accent)
        }
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    @Environment(\.shiftColors) private var colors
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
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
                    : AnyShapeStyle(colors.surface)
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

// MARK: - FilterPickerSheet

struct FilterPickerSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [(id: String, label: String)]
    @Binding var selected: String?

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                List {
                    Button {
                        selected = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("All")
                                .foregroundStyle(colors.text)
                            Spacer()
                            if selected == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .listRowBackground(colors.surface)

                    ForEach(options, id: \.id) { option in
                        Button {
                            selected = option.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(colors.text)
                                Spacer()
                                if selected == option.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                        .listRowBackground(colors.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
        }
    }
}
