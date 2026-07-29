import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
struct AIPlanValidationResult {
    var plan: GeneratedPlan?
    var repairs: [String]
    var errors: [String]

    var isValid: Bool { plan != nil && errors.isEmpty }
}

/// Treats model output as an untrusted draft. Only catalogue-backed, bounded
/// exercises are allowed to reach persistence.
@available(iOS 26, *)
enum AIPlanQualityService {
    static func maximumExerciseCount(for minutes: Int) -> Int {
        let secondsPerSet = 45 + 90
        let secondsPerExercise = secondsPerSet * 3
        let availableSeconds = max(0, (minutes * 60) - 300)
        return max(2, availableSeconds / secondsPerExercise)
    }

    static func validate(
        _ proposed: GeneratedPlan,
        catalogue: [Exercise],
        expectedDays: Int,
        timeBudgetMinutes: Int?
    ) -> AIPlanValidationResult {
        guard proposed.days.count == expectedDays else {
            return AIPlanValidationResult(
                plan: nil,
                repairs: [],
                errors: ["Expected \(expectedDays) workout days, but Apple Intelligence returned \(proposed.days.count)."]
            )
        }

        let byID = Dictionary(catalogue.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(catalogue.map { (normalized($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        let maximumExercises = timeBudgetMinutes.map {
            min(10, maximumExerciseCount(for: $0))
        } ?? 8

        var seenExerciseIDs: Set<String> = []
        var repairs: [String] = []
        var validatedDays: [GeneratedDay] = []

        for (dayIndex, day) in proposed.days.enumerated() {
            let originalExercises = Array(day.exercises.prefix(maximumExercises))
            if originalExercises.count < day.exercises.count {
                repairs.append("Trimmed \(day.dayName) to fit the session time.")
            }

            var validatedExercises: [GeneratedExercise] = []
            for item in originalExercises {
                let exercise = byID[item.exerciseID.lowercased()] ?? byName[normalized(item.exerciseName)]
                guard let exercise else {
                    repairs.append("Removed an exercise that was not in your catalogue.")
                    continue
                }
                guard seenExerciseIDs.insert(exercise.id).inserted else {
                    repairs.append("Removed duplicate \(exercise.name).")
                    continue
                }

                let sets = item.sets.clamped(to: 2...5)
                let repsMin = item.repsMin.clamped(to: 1...30)
                let repsMax = max(repsMin, item.repsMax.clamped(to: 1...30))
                let rest = item.restSeconds.clamped(to: 30...300)

                if item.exerciseID != exercise.id || item.exerciseName != exercise.name
                    || sets != item.sets || repsMin != item.repsMin
                    || repsMax != item.repsMax || rest != item.restSeconds {
                    repairs.append("Corrected \(exercise.name)'s catalogue details or targets.")
                }

                validatedExercises.append(
                    GeneratedExercise(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        sets: sets,
                        repsMin: repsMin,
                        repsMax: repsMax,
                        restSeconds: rest
                    )
                )
            }

            guard validatedExercises.count >= 2 else {
                return AIPlanValidationResult(
                    plan: nil,
                    repairs: repairs,
                    errors: ["\(day.dayName.isEmpty ? "Day \(dayIndex + 1)" : day.dayName) did not contain enough valid exercises."]
                )
            }

            let name = clean(day.dayName, fallback: expectedDays == 1 ? "Quick Workout" : "Day \(dayIndex + 1)")
            let focus = clean(day.focus, fallback: "A balanced session based on your selected goal and preferences.")
            validatedDays.append(GeneratedDay(dayName: name, focus: focus, exercises: validatedExercises))
        }

        let plan = GeneratedPlan(
            planName: clean(proposed.planName, fallback: expectedDays == 1 ? "Quick Workout" : "My Program"),
            summary: clean(
                proposed.summary,
                fallback: "A balanced program built from exercises in your Shift catalogue."
            ),
            days: validatedDays
        )
        return AIPlanValidationResult(plan: plan, repairs: Array(Set(repairs)).sorted(), errors: [])
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(120))
    }
}

@available(iOS 26, *)
enum AIPlanFallbackBuilder {
    static func build(_ request: AIPlanGenerationRequest) -> AIPlanValidationResult {
        guard request.injuryNotes.isEmpty,
              !request.goal.localizedCaseInsensitiveContains("return to training") else {
            return AIPlanValidationResult(
                plan: nil,
                repairs: [],
                errors: ["The basic fallback can't safely account for injury or return-to-training needs. Adjust the draft manually or try Apple Intelligence again."]
            )
        }
        let ordered = request.catalogue.sorted {
            let lhsFamiliar = request.familiarExerciseIDs.contains($0.id)
            let rhsFamiliar = request.familiarExerciseIDs.contains($1.id)
            if lhsFamiliar != rhsFamiliar { return lhsFamiliar }
            let lhsCompound = $0.mechanic?.lowercased() == "compound"
            let rhsCompound = $1.mechanic?.lowercased() == "compound"
            if lhsCompound != rhsCompound { return lhsCompound }
            return $0.name < $1.name
        }
        let availablePerDay = max(2, ordered.count / max(1, request.days))
        let budgetLimit = request.timeBudgetMinutes.map(AIPlanQualityService.maximumExerciseCount) ?? 6
        let perDay = min(6, budgetLimit, availablePerDay)
        let needed = min(ordered.count, request.days * perDay)
        let selected = Array(ordered.prefix(needed))

        var buckets = Array(repeating: [Exercise](), count: request.days)
        for (index, exercise) in selected.enumerated() {
            buckets[index % request.days].append(exercise)
        }
        guard buckets.allSatisfy({ $0.count >= 2 }) else {
            return AIPlanValidationResult(
                plan: nil,
                repairs: [],
                errors: ["There aren't enough matching exercises to build this program."]
            )
        }

        let scheme = targets(for: request.goal)
        let days = buckets.enumerated().map { index, exercises in
            GeneratedDay(
                dayName: request.days == 1 ? "Quick Workout" : "Workout \(index + 1)",
                focus: "A balanced session using your selected muscles, equipment, and experience level.",
                exercises: exercises.map {
                    GeneratedExercise(
                        exerciseID: $0.id,
                        exerciseName: $0.name,
                        sets: scheme.sets,
                        repsMin: scheme.repsMin,
                        repsMax: scheme.repsMax,
                        restSeconds: scheme.rest
                    )
                }
            )
        }
        let proposed = GeneratedPlan(
            planName: request.days == 1 ? "Quick Workout" : "\(request.goal) Program",
            summary: "A reliable catalogue-based draft built from your preferences. You can adjust any exercise before saving.",
            days: days
        )
        return AIPlanQualityService.validate(
            proposed,
            catalogue: request.catalogue,
            expectedDays: request.days,
            timeBudgetMinutes: request.timeBudgetMinutes
        )
    }

    private static func targets(for goal: String) -> (sets: Int, repsMin: Int, repsMax: Int, rest: Int) {
        let value = goal.lowercased()
        if value.contains("strength") { return (4, 4, 6, 150) }
        if value.contains("endurance") { return (3, 15, 20, 45) }
        if value.contains("muscle") { return (3, 8, 12, 90) }
        return (3, 8, 12, 75)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
