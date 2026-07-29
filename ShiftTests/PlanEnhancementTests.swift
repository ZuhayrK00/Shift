import XCTest
@testable import Shift

final class PlanEnhancementTests: XCTestCase {
    func testPlanNotesCodec_roundTripsProgramMetadataAndNotes() {
        let metadata = WorkoutProgramMetadata(
            id: "program-1",
            name: "Upper Lower",
            dayIndex: 2,
            totalDays: 4,
            source: "ai"
        )
        let encoded = PlanNotesCodec.encode(metadata: metadata, userNotes: "Focus on controlled reps.")
        let decoded = PlanNotesCodec.decode(encoded)

        XCTAssertEqual(decoded.metadata, metadata)
        XCTAssertEqual(decoded.userNotes, "Focus on controlled reps.")
    }

    func testPlanNotesCodec_preservesLegacyPlainNotes() {
        let decoded = PlanNotesCodec.decode("Existing user note")
        XCTAssertNil(decoded.metadata)
        XCTAssertEqual(decoded.userNotes, "Existing user note")
    }

    func testProgramSummary_advancesToWorkoutAfterMostRecentCompletion() {
        let first = planItem(id: "day-1", name: "Upper", dayIndex: 0)
        let second = planItem(id: "day-2", name: "Lower", dayIndex: 1)
        let completed = WorkoutSession(
            id: "session",
            userId: "user",
            planId: first.plan.id,
            name: first.plan.name,
            startedAt: Date(),
            endedAt: Date()
        )

        let result = WorkoutProgramService.summaries(
            plans: [second, first],
            completedSessions: [completed],
            userID: "user"
        )

        XCTAssertEqual(result.programs.count, 1)
        XCTAssertEqual(result.programs[0].workouts.map(\.plan.id), ["day-1", "day-2"])
        XCTAssertEqual(result.programs[0].nextWorkout?.plan.id, "day-2")
        XCTAssertTrue(result.standalone.isEmpty)
    }

    func testExerciseSubstitutions_prioritizeMatchingMovement() {
        let original = exercise(id: "original", muscle: "chest", equipment: "barbell", mechanic: "compound")
        let close = exercise(id: "close", muscle: "chest", equipment: "barbell", mechanic: "compound")
        let distant = exercise(id: "distant", muscle: "legs", equipment: "machine", mechanic: "isolation")

        let suggestions = ExerciseSubstitutionService.suggestions(
            for: original,
            from: [distant, close],
            excluding: []
        )

        XCTAssertEqual(suggestions.first?.id, close.id)
    }

    func testDefaultGymPreference_prioritizesCommercialGymEquipment() {
        let bodyweight = exercise(
            id: "bodyweight",
            muscle: "chest",
            equipment: "body only",
            mechanic: "compound"
        )
        let cable = exercise(
            id: "cable",
            muscle: "chest",
            equipment: "cable",
            mechanic: "isolation"
        )
        let barbell = exercise(
            id: "barbell",
            muscle: "chest",
            equipment: "barbell",
            mechanic: "compound"
        )

        let sorted = GymExercisePreferenceService.sorted([bodyweight, cable, barbell])

        XCTAssertEqual(sorted.map(\.id), ["barbell", "cable", "bodyweight"])
    }

    func testDefaultGymPreference_stillAllowsBodyweightCatalogue() {
        let pushUp = exercise(
            id: "push-up",
            muscle: "chest",
            equipment: "body only",
            mechanic: "compound"
        )
        let dip = exercise(
            id: "dip",
            muscle: "chest",
            equipment: "body only",
            mechanic: "compound"
        )

        let sorted = GymExercisePreferenceService.sorted([pushUp, dip])

        XCTAssertEqual(Set(sorted.map(\.id)), ["push-up", "dip"])
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    func testFallbackSelectionBalancesRequestedMuscleGroups() {
        let exercises = [
            exercise(id: "chest-1", muscle: "chest", equipment: "barbell", mechanic: "compound"),
            exercise(id: "chest-2", muscle: "chest", equipment: "dumbbell", mechanic: "compound"),
            exercise(id: "back-1", muscle: "back", equipment: "cable", mechanic: "compound"),
            exercise(id: "back-2", muscle: "back", equipment: "machine", mechanic: "compound"),
            exercise(id: "legs-1", muscle: "legs", equipment: "barbell", mechanic: "compound"),
            exercise(id: "legs-2", muscle: "legs", equipment: "machine", mechanic: "compound")
        ]

        let selected = AIPlanFallbackBuilder.balancedSelection(from: exercises, limit: 3)

        XCTAssertEqual(Set(selected.map(\.primaryMuscleId)), ["chest", "back", "legs"])
    }
    #endif

    func testProgressionRecommendation_increasesOnlyAfterComfortableTopRange() {
        let comfortable = [
            SessionSet(
                id: "1",
                sessionId: "s",
                exerciseId: "bench",
                setNumber: 1,
                reps: 10,
                weight: 50,
                rpe: 7,
                isCompleted: true
            ),
            SessionSet(
                id: "2",
                sessionId: "s",
                exerciseId: "bench",
                setNumber: 2,
                reps: 10,
                weight: 50,
                rpe: 8,
                isCompleted: true
            )
        ]
        let result = ProgressionRecommendationService.recommendations(
            latestSets: ["bench": comfortable],
            targets: ["bench": (repsMin: 8, repsMax: 10)],
            increment: 2.5
        )

        XCTAssertEqual(result["bench"]?.weight, 52.5)
        XCTAssertEqual(result["bench"]?.isIncrease, true)
    }

    func testProgressionRecommendation_holdsWeightWhenEffortIsHigh() {
        let hard = [
            SessionSet(
                id: "1",
                sessionId: "s",
                exerciseId: "squat",
                setNumber: 1,
                reps: 10,
                weight: 100,
                rpe: 9.5,
                isCompleted: true
            )
        ]
        let result = ProgressionRecommendationService.recommendations(
            latestSets: ["squat": hard],
            targets: ["squat": (repsMin: 8, repsMax: 10)],
            increment: 5
        )

        XCTAssertEqual(result["squat"]?.weight, 100)
        XCTAssertEqual(result["squat"]?.isIncrease, false)
    }

    func testProgressionRecommendation_doesNotOfferZeroIncrement() {
        let completed = [
            SessionSet(
                id: "1",
                sessionId: "s",
                exerciseId: "row",
                setNumber: 1,
                reps: 12,
                weight: 30,
                isCompleted: true
            )
        ]
        let result = ProgressionRecommendationService.recommendations(
            latestSets: ["row": completed],
            targets: ["row": (repsMin: 10, repsMax: 12)],
            increment: 0
        )

        XCTAssertEqual(result["row"]?.weight, 30)
        XCTAssertEqual(result["row"]?.isIncrease, false)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    func testFallbackBuilder_producesGroundedUniqueDraft() {
        let catalogue = (0..<12).map {
            exercise(
                id: "exercise-\($0)",
                muscle: $0.isMultiple(of: 2) ? "upper" : "lower",
                equipment: "dumbbell",
                mechanic: $0 < 4 ? "compound" : "isolation"
            )
        }
        let request = AIPlanGenerationRequest(
            days: 3,
            goal: "General Fitness",
            experience: "Beginner",
            split: "Full body",
            targetScheme: "3 sets",
            timeBudgetMinutes: 45,
            notes: "",
            injuryNotes: [],
            catalogue: catalogue,
            familiarExerciseIDs: []
        )

        let result = AIPlanFallbackBuilder.build(request)
        let ids = result.plan?.days.flatMap(\.exercises).map(\.exerciseID) ?? []

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.plan?.days.count, 3)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isSubset(of: Set(catalogue.map(\.id))))
    }
    #endif

    private func planItem(id: String, name: String, dayIndex: Int) -> WorkoutPlanWithCount {
        let metadata = WorkoutProgramMetadata(
            id: "program",
            name: "Program",
            dayIndex: dayIndex,
            totalDays: 2,
            source: "ai"
        )
        let plan = WorkoutPlan(
            id: id,
            userId: "user",
            name: name,
            notes: PlanNotesCodec.encode(metadata: metadata, userNotes: nil),
            createdAt: Date()
        )
        return WorkoutPlanWithCount(
            plan: plan,
            exerciseCount: 4,
            muscleGroups: [],
            exerciseImageUrls: [],
            estimatedMinutes: 45
        )
    }

    private func exercise(
        id: String,
        muscle: String,
        equipment: String,
        mechanic: String
    ) -> Exercise {
        Exercise(
            id: id,
            name: id,
            slug: id,
            instructions: nil,
            primaryMuscleId: muscle,
            secondaryMuscleIds: [],
            equipment: equipment,
            isBuiltIn: true,
            createdBy: nil,
            imageUrl: nil,
            secondaryImageUrl: nil,
            level: "beginner",
            force: "push",
            mechanic: mechanic,
            category: nil,
            instructionsSteps: nil,
            bodyPart: muscle,
            description: nil
        )
    }
}
