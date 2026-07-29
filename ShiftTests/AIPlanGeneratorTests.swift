import XCTest
@testable import Shift
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AIPlanGeneratorTests: XCTestCase {

    // MARK: - ExerciseMatchingService

    private func makeExercise(id: String, name: String) -> Exercise {
        Exercise(
            id: id,
            name: name,
            slug: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            instructions: nil,
            primaryMuscleId: "m1",
            secondaryMuscleIds: [],
            equipment: nil,
            isBuiltIn: true,
            createdBy: nil,
            imageUrl: nil,
            secondaryImageUrl: nil,
            level: nil,
            force: nil,
            mechanic: nil,
            category: nil,
            instructionsSteps: nil,
            bodyPart: nil,
            description: nil
        )
    }

    func testExerciseMatch_exactMatch() {
        let exercises = [
            makeExercise(id: "1", name: "Bench Press"),
            makeExercise(id: "2", name: "Squat"),
        ]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("Bench Press", against: exercises, usedIds: &usedIds)
        XCTAssertEqual(match?.id, "1")
        XCTAssertTrue(usedIds.contains("1"))
    }

    func testExerciseMatch_caseInsensitive() {
        let exercises = [makeExercise(id: "1", name: "Bench Press")]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("bench press", against: exercises, usedIds: &usedIds)
        XCTAssertEqual(match?.id, "1")
    }

    func testExerciseMatch_keywordScoring() {
        let exercises = [
            makeExercise(id: "1", name: "Incline Dumbbell Press"),
            makeExercise(id: "2", name: "Flat Bench Press"),
        ]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("Incline Press", against: exercises, usedIds: &usedIds)
        XCTAssertEqual(match?.id, "1")
    }

    func testExerciseMatch_skipsUsedIds() {
        let exercises = [
            makeExercise(id: "1", name: "Bench Press"),
            makeExercise(id: "2", name: "Incline Bench Press"),
        ]
        var usedIds: Set<String> = ["1"]
        let match = ExerciseMatchingService.match("Bench Press", against: exercises, usedIds: &usedIds)
        // Should skip id "1" and fall through to keyword matching
        XCTAssertNotEqual(match?.id, "1")
    }

    func testExerciseMatch_pluralHandling() {
        let exercises = [makeExercise(id: "1", name: "Dumbbell Curl")]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("Dumbbell Curls", against: exercises, usedIds: &usedIds)
        XCTAssertEqual(match?.id, "1")
    }

    func testExerciseMatch_noMatch_returnsNil() {
        let exercises = [makeExercise(id: "1", name: "Bench Press")]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("Totally Different Exercise", against: exercises, usedIds: &usedIds)
        XCTAssertNil(match)
    }

    func testExerciseMatch_emptyName_returnsNil() {
        let exercises = [makeExercise(id: "1", name: "Bench Press")]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("", against: exercises, usedIds: &usedIds)
        XCTAssertNil(match)
    }

    func testExerciseMatch_whitespaceName_returnsNil() {
        let exercises = [makeExercise(id: "1", name: "Bench Press")]
        var usedIds: Set<String> = []
        let match = ExerciseMatchingService.match("   ", against: exercises, usedIds: &usedIds)
        XCTAssertNil(match)
    }

    #if canImport(FoundationModels)
    // MARK: - Untrusted draft validation

    @available(iOS 26, *)
    func testPlanValidation_groundsByStableIDAndClampsTargets() {
        let bench = makeExercise(id: "bench-id", name: "Bench Press")
        let row = makeExercise(id: "row-id", name: "Cable Row")
        let proposed = GeneratedPlan(
            planName: "  Upper  ",
            summary: "Balanced upper session.",
            days: [
                GeneratedDay(
                    dayName: "Upper",
                    focus: "Push and pull.",
                    exercises: [
                        GeneratedExercise(
                            exerciseID: bench.id,
                            exerciseName: "Wrong display name",
                            sets: 99,
                            repsMin: -4,
                            repsMax: 100,
                            restSeconds: 2
                        ),
                        GeneratedExercise(
                            exerciseID: row.id,
                            exerciseName: row.name,
                            sets: 3,
                            repsMin: 8,
                            repsMax: 12,
                            restSeconds: 90
                        )
                    ]
                )
            ]
        )

        let result = AIPlanQualityService.validate(
            proposed,
            catalogue: [bench, row],
            expectedDays: 1,
            timeBudgetMinutes: nil
        )

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.plan?.planName, "Upper")
        XCTAssertEqual(result.plan?.days[0].exercises[0].exerciseName, bench.name)
        XCTAssertEqual(result.plan?.days[0].exercises[0].sets, 5)
        XCTAssertEqual(result.plan?.days[0].exercises[0].repsMin, 1)
        XCTAssertEqual(result.plan?.days[0].exercises[0].repsMax, 30)
        XCTAssertEqual(result.plan?.days[0].exercises[0].restSeconds, 30)
        XCTAssertFalse(result.repairs.isEmpty)
    }

    @available(iOS 26, *)
    func testPlanValidation_rejectsWrongDayCount() {
        let proposed = GeneratedPlan(planName: "Program", summary: "", days: [])
        let result = AIPlanQualityService.validate(
            proposed,
            catalogue: [makeExercise(id: "1", name: "Squat")],
            expectedDays: 3,
            timeBudgetMinutes: nil
        )
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.plan)
        XCTAssertFalse(result.errors.isEmpty)
    }

    @available(iOS 26, *)
    func testPlanValidation_rejectsHallucinatedExercises() {
        let proposed = GeneratedPlan(
            planName: "Workout",
            summary: "",
            days: [
                GeneratedDay(
                    dayName: "Day 1",
                    focus: "",
                    exercises: [
                        GeneratedExercise(
                            exerciseID: "made-up",
                            exerciseName: "Imaginary Lift",
                            sets: 3,
                            repsMin: 8,
                            repsMax: 10,
                            restSeconds: 60
                        )
                    ]
                )
            ]
        )
        let result = AIPlanQualityService.validate(
            proposed,
            catalogue: [makeExercise(id: "1", name: "Squat")],
            expectedDays: 1,
            timeBudgetMinutes: nil
        )
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.plan)
    }

    #if compiler(>=6.4)
    @available(iOS 27, *)
    func testUnsupportedReasoningCapabilityUsesStandardGenerationFallback() {
        let error = LanguageModelError.unsupportedCapability(
            .init(
                capability: .reasoning,
                debugDescription: "Reasoning is unavailable on this model."
            )
        )

        XCTAssertTrue(
            AppleIntelligencePlanService.shouldRetryWithoutEnhancedReasoning(error)
        )
    }
    #endif
    #endif

    // MARK: - Avoid pattern extraction

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    func testExtractAvoidPatterns_findsAvoidKeywords() {
        let notes = "avoid overhead pressing, no deadlifts"
        let patterns = AIPlanGeneratorView.extractAvoidPatterns(from: notes)
        XCTAssertTrue(patterns.contains(where: { $0.contains("overhead") }))
        XCTAssertTrue(patterns.contains(where: { $0.contains("deadlift") }))
    }

    @available(iOS 26, *)
    func testExtractAvoidPatterns_emptyNotes() {
        let patterns = AIPlanGeneratorView.extractAvoidPatterns(from: "")
        XCTAssertTrue(patterns.isEmpty)
    }

    @available(iOS 26, *)
    func testExtractAvoidPatterns_noAvoidKeywords() {
        let patterns = AIPlanGeneratorView.extractAvoidPatterns(from: "i want to focus on chest and back")
        XCTAssertTrue(patterns.isEmpty)
    }

    // MARK: - Movement tags

    @available(iOS 26, *)
    func testMovementTag_compound() {
        var ex = makeExercise(id: "1", name: "Bench Press")
        ex.mechanic = "compound"
        ex.force = "push"
        let tag = AIPlanGeneratorView.movementTag(for: ex)
        XCTAssertEqual(tag, "C/push")
    }

    @available(iOS 26, *)
    func testMovementTag_isolation() {
        var ex = makeExercise(id: "1", name: "Bicep Curl")
        ex.mechanic = "isolation"
        ex.force = "pull"
        let tag = AIPlanGeneratorView.movementTag(for: ex)
        XCTAssertEqual(tag, "I/pull")
    }

    @available(iOS 26, *)
    func testMovementTag_noData() {
        let ex = makeExercise(id: "1", name: "Some Exercise")
        let tag = AIPlanGeneratorView.movementTag(for: ex)
        XCTAssertEqual(tag, "")
    }

    // MARK: - Rep scheme

    @available(iOS 26, *)
    func testRepScheme_allGoalsCovered() {
        for goal in AIGoalType.allCases {
            let scheme = AIPlanGeneratorView.repScheme(for: goal)
            XCTAssertFalse(scheme.isEmpty, "Goal '\(goal.rawValue)' returned empty rep scheme")
            XCTAssertTrue(scheme.contains("sets"), "Rep scheme for '\(goal.rawValue)' should mention sets")
        }
    }

    @available(iOS 26, *)
    func testRepScheme_nilGoal() {
        let scheme = AIPlanGeneratorView.repScheme(for: nil)
        XCTAssertFalse(scheme.isEmpty)
    }

    // MARK: - Time budget parsing

    @available(iOS 26, *)
    func testExtractTimeBudget_minutes() {
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "I only have 30 minutes"), 30)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "about 45 min session"), 45)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "60 mins tops"), 60)
    }

    @available(iOS 26, *)
    func testExtractTimeBudget_hours() {
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "I spend 2 hours at the gym"), 120)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "1.5 hours"), 90)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "1 hour workout"), 60)
    }

    @available(iOS 26, *)
    func testExtractTimeBudget_naturalPhrases() {
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "I only have half an hour"), 30)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "an hour and a half"), 90)
        XCTAssertEqual(AIPlanGeneratorView.extractTimeBudget(from: "about an hour"), 60)
    }

    @available(iOS 26, *)
    func testExtractTimeBudget_noMention() {
        XCTAssertNil(AIPlanGeneratorView.extractTimeBudget(from: "focus on chest and back"))
        XCTAssertNil(AIPlanGeneratorView.extractTimeBudget(from: ""))
        XCTAssertNil(AIPlanGeneratorView.extractTimeBudget(from: "avoid overhead pressing"))
    }

    @available(iOS 26, *)
    func testMaxExercisesForBudget_30min() {
        let max = AIPlanGeneratorView.maxExercisesForBudget(minutes: 30)
        XCTAssertGreaterThanOrEqual(max, 2)
        XCTAssertLessThanOrEqual(max, 5)
    }

    @available(iOS 26, *)
    func testMaxExercisesForBudget_60min() {
        let max60 = AIPlanGeneratorView.maxExercisesForBudget(minutes: 60)
        let max30 = AIPlanGeneratorView.maxExercisesForBudget(minutes: 30)
        XCTAssertGreaterThan(max60, max30)
    }

    @available(iOS 26, *)
    func testMaxExercisesForBudget_120min() {
        let max = AIPlanGeneratorView.maxExercisesForBudget(minutes: 120)
        XCTAssertGreaterThanOrEqual(max, 8)
    }

    @available(iOS 26, *)
    func testMaxExercisesForBudget_minimumFloor() {
        // Even a very short budget should return at least 2
        let max = AIPlanGeneratorView.maxExercisesForBudget(minutes: 5)
        XCTAssertEqual(max, 2)
    }

    // MARK: - Equipment parsing

    @available(iOS 26, *)
    func testExtractEquipment_dumbbells() {
        let equip = AIPlanGeneratorView.extractEquipment(from: "I only have dumbbells", available: ["dumbbell", "barbell", "cable", "machine"])
        XCTAssertEqual(equip, ["dumbbell"])
    }

    @available(iOS 26, *)
    func testExtractEquipment_multiple() {
        let equip = AIPlanGeneratorView.extractEquipment(from: "I have a barbell and dumbbells at home", available: ["dumbbell", "barbell", "cable", "machine"])
        XCTAssertTrue(equip.contains("dumbbell"))
        XCTAssertTrue(equip.contains("barbell"))
        XCTAssertEqual(equip.count, 2)
    }

    @available(iOS 26, *)
    func testExtractEquipment_bodyweight() {
        let equip = AIPlanGeneratorView.extractEquipment(from: "just bodyweight exercises", available: ["dumbbell", "barbell", "body only"])
        XCTAssertEqual(equip, ["body only"])
    }

    @available(iOS 26, *)
    func testExtractEquipment_noMention() {
        let equip = AIPlanGeneratorView.extractEquipment(from: "focus on chest and back", available: ["dumbbell", "barbell", "cable"])
        XCTAssertTrue(equip.isEmpty)
    }

    // MARK: - Muscle group parsing

    @available(iOS 26, *)
    func testExtractMuscleGroups_single() {
        let groups = [
            MuscleGroup(id: "1", name: "Chest", slug: "chest"),
            MuscleGroup(id: "2", name: "Back", slug: "back"),
            MuscleGroup(id: "3", name: "Shoulders", slug: "shoulders"),
        ]
        let result = AIPlanGeneratorView.extractMuscleGroups(from: "I only want to work on my chest", available: groups)
        XCTAssertEqual(result, ["Chest"])
    }

    @available(iOS 26, *)
    func testExtractMuscleGroups_multiple() {
        let groups = [
            MuscleGroup(id: "1", name: "Chest", slug: "chest"),
            MuscleGroup(id: "2", name: "Back", slug: "back"),
            MuscleGroup(id: "3", name: "Shoulders", slug: "shoulders"),
        ]
        let result = AIPlanGeneratorView.extractMuscleGroups(from: "chest and shoulders today", available: groups)
        XCTAssertTrue(result.contains("Chest"))
        XCTAssertTrue(result.contains("Shoulders"))
    }

    @available(iOS 26, *)
    func testExtractMuscleGroups_aliases() {
        let groups = [
            MuscleGroup(id: "1", name: "Chest", slug: "chest"),
            MuscleGroup(id: "2", name: "Biceps", slug: "biceps"),
        ]
        let result = AIPlanGeneratorView.extractMuscleGroups(from: "hit my pecs and bicep today", available: groups)
        XCTAssertTrue(result.contains("Chest"))
        XCTAssertTrue(result.contains("Biceps"))
    }

    @available(iOS 26, *)
    func testExtractMuscleGroups_noMention() {
        let groups = [MuscleGroup(id: "1", name: "Chest", slug: "chest")]
        let result = AIPlanGeneratorView.extractMuscleGroups(from: "I want a quick workout", available: groups)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Injury notes parsing

    @available(iOS 26, *)
    func testExtractInjuryNotes_recoveryLight() {
        let groups = [MuscleGroup(id: "1", name: "Back", slug: "back")]
        let result = AIPlanGeneratorView.extractInjuryNotes(from: "I'm recovering from a back injury and want to take it very light", muscleGroups: groups)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.first?.contains("back") == true)
        XCTAssertTrue(result.first?.contains("light") == true || result.first?.contains("recovery") == true)
    }

    @available(iOS 26, *)
    func testExtractInjuryNotes_sore() {
        let groups = [MuscleGroup(id: "1", name: "Shoulders", slug: "shoulders")]
        let result = AIPlanGeneratorView.extractInjuryNotes(from: "my shoulder is sore from yesterday", muscleGroups: groups)
        XCTAssertFalse(result.isEmpty)
    }

    @available(iOS 26, *)
    func testExtractInjuryNotes_noInjury() {
        let groups = [MuscleGroup(id: "1", name: "Chest", slug: "chest")]
        let result = AIPlanGeneratorView.extractInjuryNotes(from: "I want to focus on chest today", muscleGroups: groups)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Full voice preferences parsing

    @available(iOS 26, *)
    func testParseVoicePreferences_fullSentence() {
        let groups = [
            MuscleGroup(id: "1", name: "Chest", slug: "chest"),
            MuscleGroup(id: "2", name: "Back", slug: "back"),
        ]
        let equip = ["dumbbell", "barbell", "cable"]
        let prefs = AIPlanGeneratorView.parseVoicePreferences(
            from: "I only have dumbbells and want to work on chest for 30 minutes",
            muscleGroups: groups,
            equipment: equip
        )
        XCTAssertEqual(prefs.muscleGroupNames, ["Chest"])
        XCTAssertEqual(prefs.equipmentNames, ["dumbbell"])
        XCTAssertEqual(prefs.timeBudget, 30)
    }

    @available(iOS 26, *)
    func testParseVoicePreferences_empty() {
        let prefs = AIPlanGeneratorView.parseVoicePreferences(from: "", muscleGroups: [], equipment: [])
        XCTAssertTrue(prefs.isEmpty)
    }
    #endif
}
