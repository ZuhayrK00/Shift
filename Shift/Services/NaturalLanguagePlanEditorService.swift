import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
enum NaturalLanguagePlanEditorService {
    static func propose(
        instruction: String,
        plan: WorkoutPlan,
        exercises: [PlanExercise],
        catalogue: [Exercise]
    ) async throws -> ConfirmedPlanEdit {
        guard AppleIntelligencePlanService.availability == .available else {
            throw AIPlanGenerationError.unavailable(AppleIntelligencePlanService.availability)
        }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlanEditError.invalid("Describe what you want to change first.")
        }

        let catalogueByID = Dictionary(
            catalogue.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentLines = exercises.compactMap { item -> String? in
            guard let exercise = catalogueByID[item.exerciseId] else { return nil }
            return """
            PLAN_EXERCISE_ID=\(item.id) | EXERCISE_ID=\(exercise.id) | NAME=\(exercise.name) | \
            SETS=\(item.targetSets) | REPS=\(item.targetRepsMin ?? item.defaultReps)-\(item.targetRepsMax ?? item.defaultReps) | \
            REST=\(item.restSeconds ?? 90)
            """
        }.joined(separator: "\n")
        let candidates = candidateCatalogue(
            for: trimmed,
            existing: exercises,
            from: catalogue
        )
        let catalogueLines = candidates.map {
            "ID=\($0.id) | NAME=\($0.name) | MUSCLE=\($0.primaryMuscleId) | EQUIPMENT=\($0.equipment ?? "none")"
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: """
            You edit an existing Shift workout. Return a small, reviewable set of structured changes.
            Never apply changes yourself and never invent IDs.
            """
        )
        #if compiler(>=6.4)
        let options = GenerationOptions(samplingMode: .greedy, temperature: 0.15)
        #else
        let options = GenerationOptions(sampling: .greedy, temperature: 0.15)
        #endif
        let generated = try await session.respond(
            to: """
            CURRENT PLAN: \(plan.name)
            USER REQUEST: \(String(trimmed.prefix(600)))

            RULES:
            - Use only exact IDs below.
            - Use update for target changes, replace to swap an existing exercise, remove to delete, add to append.
            - For update/remove/replace, PLAN_EXERCISE_ID must be an existing exact ID.
            - For replace/add, EXERCISE_ID must be an exact catalogue ID.
            - Keep changes minimal. Do not change unrelated exercises.
            - A general gym request should favor common free weights, cables and machines over bodyweight.
            - Return at most 12 changes.

            CURRENT EXERCISES:
            \(currentLines)

            CATALOGUE:
            \(catalogueLines)
            """,
            generating: GeneratedPlanEdit.self,
            options: options
        ).content

        return try validate(
            generated,
            existing: exercises,
            catalogueByID: catalogueByID
        )
    }

    /// Keeps the on-device model prompt focused enough to remain responsive while
    /// retaining direct name matches and useful alternatives for the current workout.
    private static func candidateCatalogue(
        for instruction: String,
        existing: [PlanExercise],
        from catalogue: [Exercise]
    ) -> [Exercise] {
        let tokens = Set(
            instruction
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
        let existingExerciseIDs = Set(existing.map(\.exerciseId))
        let currentMuscles = Set(
            catalogue
                .filter { existingExerciseIDs.contains($0.id) }
                .map { $0.primaryMuscleId.lowercased() }
        )
        let commonEquipment = [
            "barbell", "dumbbell", "cable", "machine", "smith",
            "kettlebell", "ez curl"
        ]

        return catalogue
            .map { exercise -> (Exercise, Int) in
                let name = exercise.name.lowercased()
                let equipment = exercise.equipment?.lowercased() ?? ""
                let muscle = exercise.primaryMuscleId.lowercased()
                var score = existingExerciseIDs.contains(exercise.id) ? 100 : 0
                score += tokens.reduce(into: 0) { result, token in
                    if name.contains(token) {
                        result += 30
                    } else if equipment.contains(token) || muscle.contains(token) {
                        result += 12
                    }
                }
                if currentMuscles.contains(muscle) { score += 8 }
                if commonEquipment.contains(where: equipment.contains) { score += 3 }
                return (exercise, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(120)
            .map(\.0)
    }

    private static func validate(
        _ generated: GeneratedPlanEdit,
        existing: [PlanExercise],
        catalogueByID: [String: Exercise]
    ) throws -> ConfirmedPlanEdit {
        let existingIDs = Set(existing.map(\.id))
        var seenExisting: Set<String> = []
        var edits: [ConfirmedPlanExerciseEdit] = []

        for item in generated.exerciseEdits.prefix(12) {
            guard let action = ConfirmedPlanExerciseEdit.Action(
                rawValue: item.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ) else { continue }
            let existingID = item.planExerciseID.trimmingCharacters(in: .whitespacesAndNewlines)
            let exerciseID = item.exerciseID.trimmingCharacters(in: .whitespacesAndNewlines)

            if action != .add {
                guard existingIDs.contains(existingID), seenExisting.insert(existingID).inserted
                else { continue }
            }
            let replacement: Exercise?
            if action == .add || action == .replace {
                guard let exercise = catalogueByID[exerciseID] else { continue }
                replacement = exercise
            } else {
                replacement = nil
            }
            let current = existing.first { $0.id == existingID }
            let currentExercise = current.flatMap { catalogueByID[$0.exerciseId] }
            edits.append(
                ConfirmedPlanExerciseEdit(
                    action: action,
                    planExerciseID: action == .add ? nil : existingID,
                    exerciseID: replacement?.id,
                    exerciseName: replacement?.name ?? currentExercise?.name ?? "Exercise",
                    sets: min(max(item.sets, 2), 8),
                    repsMin: min(max(item.repsMin, 1), 30),
                    repsMax: min(max(item.repsMax, max(item.repsMin, 1)), 30),
                    restSeconds: min(max(item.restSeconds, 30), 300),
                    explanation: String(item.explanation.prefix(160))
                )
            )
        }

        guard !edits.isEmpty || !generated.planName.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw PlanEditError.invalid("The model couldn't produce a valid change. Try a more specific request.")
        }
        let removals = edits.filter { $0.action == .remove }.count
        let additions = edits.filter { $0.action == .add }.count
        guard existing.count - removals + additions > 0 else {
            throw PlanEditError.invalid("A plan needs at least one exercise.")
        }

        let name = generated.planName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfirmedPlanEdit(
            summary: String(generated.summary.prefix(220)),
            planName: name.isEmpty ? nil : String(name.prefix(80)),
            exerciseEdits: edits
        )
    }
}

@available(iOS 26, *)
enum PlanEditError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
#endif
