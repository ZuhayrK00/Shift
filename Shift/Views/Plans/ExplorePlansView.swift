import SwiftUI

// MARK: - ExplorePlansView

struct ExplorePlansView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var toastMessage: String?
    @State private var showToast = false

    private var grouped: [(String, [PlanTemplate])] {
        let order = ["3-Day Splits", "4-Day Splits", "5-Day Splits", "6-Day Splits"]
        let dict = Dictionary(grouping: PlanTemplateLibrary.all) { $0.category }
        return order.compactMap { key in
            guard let plans = dict[key] else { return nil }
            return (key, plans)
        }
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Plans")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(colors.text)
                        Text("Browse popular training programs and add them to your library.")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Grouped plans
                    ForEach(grouped, id: \.0) { category, plans in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(colors.muted)
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .padding(.horizontal, 16)

                            ForEach(plans) { template in
                                NavigationLink {
                                    TemplateDetailView(template: template) { planName in
                                        toastMessage = "Added \"\(planName)\""
                                        showToast = true
                                    }
                                } label: {
                                    TemplatePlanCard(template: template)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showToast, let message = toastMessage {
                toastView(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showToast = false
                            }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.4), value: showToast)
    }

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(colors.success)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(colors.surface)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(Capsule().stroke(colors.border, lineWidth: 1))
    }
}

// MARK: - TemplatePlanCard

private struct TemplatePlanCard: View {
    @Environment(\.shiftColors) private var colors
    let template: PlanTemplate

    private var levelColor: Color {
        switch template.level {
        case .beginner: return colors.success
        case .intermediate: return colors.warning
        case .advanced: return colors.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Level badge
            Text(template.level.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(levelColor)
                .kerning(0.5)

            // Name
            Text(template.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(colors.text)
                .lineLimit(1)

            // Description
            Text(template.description)
                .font(.system(size: 13))
                .foregroundStyle(colors.muted)
                .lineLimit(2)

            // Footer
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("\(template.daysPerWeek) days")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(colors.muted)

                HStack(spacing: 4) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 10))
                    let total = template.days.reduce(0) { $0 + $1.exerciseCount }
                    Text("\(total) exercises")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(colors.muted)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }
        }
        .padding(16)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

// MARK: - TemplateDetailView

struct TemplateDetailView: View {
    @Environment(\.shiftColors) private var colors
    let template: PlanTemplate
    var onAdded: ((String) -> Void)?

    @State private var exerciseMap: [String: Exercise] = [:]
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var addedDays: Set<String> = []
    @State private var addedPlanIds: [String: String] = [:]  // dayId → planId
    @State private var expandedDays: Set<String> = []
    @State private var existingPlans: [WorkoutPlanWithCount] = []

    private var levelColor: Color {
        switch template.level {
        case .beginner: return colors.success
        case .intermediate: return colors.warning
        case .advanced: return colors.danger
        }
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.level.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(levelColor)
                            .kerning(0.5)

                        Text(template.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(colors.text)

                        Text(template.description)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text("\(template.daysPerWeek) days per week")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(colors.accent)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)

                    // Add all button
                    Button {
                        Task { await addAllDays() }
                    } label: {
                        HStack {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Add All to My Plans")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isAdding || addedDays.count == template.days.count)
                    .opacity(addedDays.count == template.days.count ? 0.5 : 1)
                    .padding(.horizontal, 16)

                    // Day sections
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(colors.accent)
                            Spacer()
                        }
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(template.days) { day in
                                DaySection(
                                    day: day,
                                    exerciseMap: exerciseMap,
                                    isExpanded: expandedDays.contains(day.id),
                                    isAdded: addedDays.contains(day.id),
                                    isAdding: isAdding,
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandedDays.contains(day.id) {
                                                expandedDays.remove(day.id)
                                            } else {
                                                expandedDays.insert(day.id)
                                            }
                                        }
                                    },
                                    onAdd: {
                                        Task { await addSingleDay(day) }
                                    },
                                    onRemove: {
                                        Task { await removeDayPlan(day) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExercises() }
    }

    private func loadExercises() async {
        // Check which template days already exist in the user's library
        existingPlans = (try? await PlanService.listPlans()) ?? []
        let existingNames = Set(existingPlans.map { $0.plan.name })
        for day in template.days {
            if existingNames.contains(day.name) {
                addedDays.insert(day.id)
                // Find the matching plan ID so removal works
                if let match = existingPlans.first(where: { $0.plan.name == day.name }) {
                    addedPlanIds[day.id] = match.plan.id
                }
            }
        }

        // Load all exercises and match using keyword scoring since
        // exercise names/slugs may differ between template definitions
        // and the current ExerciseDB-imported catalogue.
        let allExercises = (try? await ExerciseRepository.findAll()) ?? []

        // Noise words to skip when scoring keyword matches
        let noise: Set<String> = ["with", "the", "a", "an", "on", "of", "full", "range", "motion"]

        var map: [String: Exercise] = [:]
        var usedIds: Set<String> = []   // avoid assigning same exercise twice

        for day in template.days {
            for templateEx in day.exercises {
                // 1. Try exact slug match
                if let match = allExercises.first(where: { $0.slug == templateEx.slug && !usedIds.contains($0.id) }) {
                    map[templateEx.slug] = match
                    usedIds.insert(match.id)
                    continue
                }

                // 2. Try exact name match (slug → name)
                let nameFromSlug = templateEx.slug
                    .replacingOccurrences(of: "-", with: " ")
                    .lowercased()
                if let match = allExercises.first(where: { $0.name.lowercased() == nameFromSlug && !usedIds.contains($0.id) }) {
                    map[templateEx.slug] = match
                    usedIds.insert(match.id)
                    continue
                }

                // 3. Keyword scoring — split slug into keywords, score each
                //    exercise by how many keywords its name contains.
                //    Handles plural forms (e.g. "triceps" matches "tricep")
                //    and word reordering (e.g. "dumbbell incline bench press"
                //    matches keywords ["incline", "dumbbell", "bench", "press"]).
                let keywords = nameFromSlug
                    .split(separator: " ")
                    .map(String.init)
                    .filter { !noise.contains($0) }

                var bestMatch: Exercise?
                var bestScore = 0

                for exercise in allExercises {
                    let exerciseName = exercise.name.lowercased()
                    var score = 0
                    for keyword in keywords {
                        if exerciseName.contains(keyword) {
                            score += 1
                        } else if keyword.hasSuffix("s") && exerciseName.contains(String(keyword.dropLast())) {
                            // singular match: "triceps" → "tricep"
                            score += 1
                        } else if exerciseName.contains(keyword + "s") {
                            // plural match: "tricep" → "triceps"
                            score += 1
                        }
                    }
                    if score > bestScore {
                        bestScore = score
                        bestMatch = exercise
                    }
                }

                // Require at least half the keywords to match
                if let match = bestMatch, bestScore >= max(1, keywords.count / 2) {
                    map[templateEx.slug] = match
                    usedIds.insert(match.id)
                }
            }
        }

        exerciseMap = map
        isLoading = false
    }

    private func addAllDays() async {
        isAdding = true
        for day in template.days {
            if !addedDays.contains(day.id) {
                await addDayToPlan(day)
                addedDays.insert(day.id)
            }
        }
        isAdding = false
        onAdded?(template.name)
    }

    private func addSingleDay(_ day: PlanTemplateDay) async {
        isAdding = true
        await addDayToPlan(day)
        addedDays.insert(day.id)
        isAdding = false
        onAdded?(day.name)
    }

    private func addDayToPlan(_ day: PlanTemplateDay) async {
        do {
            let plan = try await PlanService.createPlan(name: day.name)
            addedPlanIds[day.id] = plan.id

            var position = 0
            var groupTagToId: [String: String] = [:]

            for templateEx in day.exercises {
                guard let exercise = exerciseMap[templateEx.slug] else { continue }

                let groupId: String? = {
                    guard let tag = templateEx.groupTag else { return nil }
                    if let existing = groupTagToId[tag] { return existing }
                    let newId = UUID().uuidString.lowercased()
                    groupTagToId[tag] = newId
                    return newId
                }()

                let peId = UUID().uuidString.lowercased()
                let pe = PlanExercise(
                    id: peId,
                    planId: plan.id,
                    exerciseId: exercise.id,
                    position: position,
                    targetSets: templateEx.sets,
                    targetRepsMin: templateEx.repsMin,
                    targetRepsMax: templateEx.repsMax,
                    restSeconds: templateEx.restSeconds,
                    groupId: groupId
                )
                try await PlanRepository.insertExercise(pe)
                try await MutationQueueRepository.enqueue(
                    table: "plan_exercises",
                    op: "insert",
                    payload: [
                        "id": peId,
                        "plan_id": plan.id,
                        "exercise_id": exercise.id,
                        "position": position,
                        "target_sets": templateEx.sets,
                        "target_reps_min": templateEx.repsMin,
                        "target_reps_max": templateEx.repsMax as Any,
                        "target_weight": NSNull(),
                        "rest_seconds": templateEx.restSeconds,
                        "group_id": groupId.map { $0 as Any } ?? NSNull(),
                    ]
                )
                position += 1
            }
            SyncService.flushInBackground()
            PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            print("Failed to add plan day: \(error)")
        }
    }

    private func removeDayPlan(_ day: PlanTemplateDay) async {
        guard let planId = addedPlanIds[day.id] else { return }
        do {
            try await PlanService.deletePlan(planId)
            addedDays.remove(day.id)
            addedPlanIds.removeValue(forKey: day.id)
        } catch {
            print("Failed to remove plan: \(error)")
        }
    }
}

// MARK: - DaySection

private struct DaySection: View {
    @Environment(\.shiftColors) private var colors
    let day: PlanTemplateDay
    let exerciseMap: [String: Exercise]
    let isExpanded: Bool
    let isAdded: Bool
    let isAdding: Bool
    var onToggle: () -> Void
    var onAdd: () -> Void
    var onRemove: () -> Void

    private var estimatedMinutes: Int {
        let totalSets = day.exercises.reduce(0) { $0 + $1.sets }
        let avgReps = day.exercises.isEmpty ? 10 :
            day.exercises.reduce(0) { $0 + ($1.repsMax ?? $1.repsMin) } / day.exercises.count
        let avgRest = day.exercises.isEmpty ? 90 :
            day.exercises.reduce(0) { $0 + $1.restSeconds } / day.exercises.count
        return WorkoutDurationEstimator.estimate(
            exerciseCount: day.exerciseCount,
            totalSets: totalSets,
            avgReps: avgReps,
            defaultRestSeconds: avgRest
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(colors.text)
                    HStack(spacing: 8) {
                        Text(pluralise(day.exerciseCount, "exercise"))
                        Text("·")
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(WorkoutDurationEstimator.formatDuration(minutes: estimatedMinutes))
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
                }

                Spacer()

                if isAdded {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(colors.success)
                    }
                } else {
                    Button {
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(colors.accent)
                            .frame(width: 30, height: 30)
                            .background(colors.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isAdding)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.muted)
                    .padding(.leading, 4)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            // Exercise list (when expanded)
            if isExpanded {
                Divider()
                    .background(colors.border)

                VStack(spacing: 0) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, templateEx in
                        let exercise = exerciseMap[templateEx.slug]
                        let isSuperset = templateEx.groupTag != nil

                        HStack(spacing: 10) {
                            // Superset indicator
                            if isSuperset {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(colors.warning)
                                    .frame(width: 3, height: 32)
                            }

                            // Exercise image
                            if let url = exercise?.imageUrl.flatMap(URL.init) {
                                CachedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(colors.surface2)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colors.surface2)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "dumbbell")
                                            .font(.system(size: 12))
                                            .foregroundStyle(colors.muted)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise?.displayName ?? templateEx.slug)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.text)
                                    .lineLimit(1)

                                let repsText: String = {
                                    if let max = templateEx.repsMax, max != templateEx.repsMin {
                                        return "\(templateEx.sets) sets \u{00d7} \(templateEx.repsMin)-\(max) reps"
                                    }
                                    return "\(templateEx.sets) sets \u{00d7} \(templateEx.repsMin) reps"
                                }()
                                Text(repsText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(colors.muted)
                            }

                            Spacer()

                            // Rest time
                            HStack(spacing: 2) {
                                Image(systemName: "timer")
                                    .font(.system(size: 9))
                                Text(formatRest(templateEx.restSeconds))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(colors.muted.opacity(0.7))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        if index < day.exercises.count - 1 {
                            Divider()
                                .background(colors.border.opacity(0.5))
                                .padding(.leading, isSuperset ? 27 : 14)
                        }
                    }
                }
            }
        }
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isAdded ? colors.success.opacity(0.3) : colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formatRest(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m\(secs)s" : "\(mins)m"
        }
        return "\(seconds)s"
    }
}
