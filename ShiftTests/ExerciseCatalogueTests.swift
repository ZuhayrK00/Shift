import XCTest
import GRDB
@testable import Shift

final class ExerciseCatalogueTests: XCTestCase {
    private func exercise(id: String = "new", archived: Bool = false) throws -> Exercise {
        try JSONDecoder().decode(Exercise.self, from: Data("""
        {"id":"\(id)","name":"Bench Press","slug":"bench-press",
         "primary_muscle_id":"chest","secondary_muscle_ids":[],"is_built_in":true,
         "catalogue_source":"repdb","source_id":"bench-press","level":"advanced",
         "primary_muscles":["pectoralis_major"],"secondary_muscles":["triceps_brachii"],
         "equipment":"barbell","secondary_equipment":["flat bench"],
         "form_tips":["Keep your feet planted."],"is_archived":\(archived)}
        """.utf8))
    }

    func testLegacyJSONStillDecodes() throws {
        let item = try JSONDecoder().decode(Exercise.self, from: Data("""
        {"id":"old","name":"Custom curl","slug":"custom-curl","primary_muscle_id":"biceps",
         "secondary_muscle_ids":[],"is_built_in":false}
        """.utf8))
        XCTAssertNil(item.catalogueSource)
        XCTAssertTrue(item.isSelectable)
        XCTAssertEqual(item.allEquipment, ["bodyweight"])
    }

    func testMetadataRoundTripsThroughSQLite() throws {
        let store = try AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("catalogue-\(UUID()).db"))
        let item = try exercise()
        try store.dbPool.write { db in
            try item.save(db)
            let result = try XCTUnwrap(Exercise.fetchOne(db, key: item.id))
            XCTAssertEqual(result, item)
            XCTAssertEqual(result.difficultyLabel, "Advanced")
            XCTAssertEqual(result.allEquipment, ["barbell", "flat bench"])
        }
    }

    func testHistoryOnlyEntriesCannotBeSuggested() throws {
        let original = try exercise(id: "original")
        let archived = try exercise(id: "archived", archived: true)
        let current = try exercise()
        XCTAssertFalse(archived.isSelectable)
        XCTAssertEqual(ExerciseSubstitutionService.suggestions(for: original, from: [archived,current], excluding: []).map(\.id), ["new"])
    }

    func testPlateCalculatorUsesLoadableBarsNotFixedWeightEquipment() throws {
        var item = try exercise()
        for equipment in ["barbell", "ez bar", "EZ curl bar", "smith machine", "trap bar"] {
            item.equipment = equipment
            XCTAssertTrue(item.supportsPlateLoading, equipment)
        }
        for equipment in ["dumbbell", "kettlebell", "cable", "leg press", "bodyweight"] {
            item.equipment = equipment
            XCTAssertFalse(item.supportsPlateLoading, equipment)
        }
        item.equipment = "barbell"
        item.isArchived = true
        XCTAssertFalse(item.supportsPlateLoading)
    }

    func testFocusMatchesEveryPrimaryTargetButNotSupportingMuscles() throws {
        var item = try exercise()
        item.primaryMuscles = ["gluteus_maximus", "quadriceps"]
        item.secondaryMuscles = ["hamstrings"]
        XCTAssertTrue(item.primarilyTargets(MuscleGroup(id: "quads", name: "Quads", slug: "quads")))
        XCTAssertTrue(item.primarilyTargets(MuscleGroup(id: "glutes", name: "Glutes", slug: "glutes")))
        XCTAssertFalse(item.primarilyTargets(MuscleGroup(id: "hamstrings", name: "Hamstrings", slug: "hamstrings")))
    }

    func testAtomicImportRemapsPlansHistoryGoalsAndOfflinePayloads() throws {
        let store = try AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("redirect-\(UUID()).db"))
        let old = try exercise(id: "OLD-ID")
        let new = try exercise()
        var custom = try exercise(id: "custom")
        custom.isBuiltIn = false
        custom.createdBy = "user"
        try store.dbPool.write { db in
            try old.save(db)
            try custom.save(db)
            try db.execute(sql: "INSERT INTO plan_exercises(id,plan_id,exercise_id,target_sets,target_weight) VALUES('p','plan','OLD-ID',4,80)")
            try db.execute(sql: "INSERT INTO session_sets(id,session_id,exercise_id,set_number,reps,weight,is_completed) VALUES('s','session','OLD-ID',1,8,80,1)")
            try db.execute(sql: "INSERT INTO exercise_goals(id,user_id,exercise_id,target_weight_increase,baseline_weight,deadline,created_at) VALUES('g','user','OLD-ID',10,80,'2026-12-01','2026-09-29')")
            for table in ["plan_exercises","session_sets","exercise_goals"] {
                try db.execute(sql: "INSERT INTO mutation_queue(table_name,op,payload,created_at) VALUES(?,'upsert',?,'2026-09-29')", arguments: [table,"{\"exercise_id\":\"OLD-ID\",\"weight\":80}"])
            }
            try db.execute(sql: "INSERT INTO mutation_queue(table_name,op,payload,created_at) VALUES('profiles','upsert','{\"name\":\"Unrelated\"}','2026-09-29')")
            let redirect = ExerciseRepository.CatalogueRedirect(oldId: "old-id", newId: "new")
            try ExerciseRepository.applyBuiltIn([new], redirects: [redirect], in: db)
            XCTAssertEqual(try ExerciseRepository.resolveId("OLD-ID", in: db), "new")
            // Applying a snapshot twice is safe and does not duplicate user data.
            try ExerciseRepository.applyBuiltIn([new], redirects: [redirect], in: db)
            for table in ["plan_exercises","session_sets","exercise_goals"] {
                XCTAssertEqual(try String.fetchOne(db, sql: "SELECT exercise_id FROM \(table)"), "new")
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 1)
            }
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT weight FROM session_sets"), 80)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT reps FROM session_sets"), 8)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mutation_queue WHERE json_extract(payload,'$.exercise_id')='new'"), 3)
            XCTAssertNotNil(try Exercise.fetchOne(db, key: "custom"))
            XCTAssertNil(try Exercise.fetchOne(db, key: "OLD-ID"))
        }
    }

    func testTemplatesResolveToReviewedCatalogueSlugs() {
        let available: Set<String> = ["bench-press","barbell-row","deadlift","front-squat","squat","romanian-deadlift","upright-row","ez-bar-lying-tricep-extension","face-pull","seated-cable-row","dips","bicep-curl","hammer-curl","incline-db-press","lateral-raise","reverse-lunge","db-sumo-squat","leg-curl","tricep-pushdown","cable-crunch","cable-fly","dumbbell-shoulder-press","hanging-leg-raise","lat-pulldown","leg-extension","leg-press","pull-up","push-up","seated-calf-raise","barbell-curl"]
        for template in PlanTemplateLibrary.all {
            for day in template.days {
                XCTAssertFalse(day.exercises.isEmpty)
                for item in day.exercises { XCTAssertTrue(available.contains(item.slug), "Missing \(item.slug) in \(template.name)") }
            }
        }
    }

    func testPlanReplacementPreservesProgrammingAndHistoryButClearsOldLoad() throws {
        let store = try AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("replacement-\(UUID()).db"))
        let old = try exercise(id: "old", archived: true)
        let current = try exercise()
        try store.dbPool.write { db in
            try old.save(db); try current.save(db)
            try db.execute(sql: "INSERT INTO workout_plans(id,user_id,name,created_at) VALUES('plan','owner','Upper','2026-09-29')")
            try db.execute(sql: "INSERT INTO plan_exercises(id,plan_id,exercise_id,target_sets,target_reps_min,target_weight,rest_seconds,group_id) VALUES('p','plan','old',4,8,80,90,'superset')")
            try db.execute(sql: "INSERT INTO session_sets(id,session_id,exercise_id,set_number,reps,weight,is_completed) VALUES('s','session','old',1,8,80,1)")
            XCTAssertThrowsError(try PlanService.applyExerciseReplacement("p", with: "new", owner: "someone-else", in: db))
            XCTAssertThrowsError(try PlanService.applyExerciseReplacement("p", with: "old", owner: "owner", in: db))
            try PlanService.applyExerciseReplacement("p", with: "new", owner: "owner", in: db)
            let item = try XCTUnwrap(PlanExercise.fetchOne(db, key: "p"))
            XCTAssertEqual(item.exerciseId, "new")
            XCTAssertEqual(item.targetSets, 4)
            XCTAssertEqual(item.targetRepsMin, 8)
            XCTAssertEqual(item.restSeconds, 90)
            XCTAssertEqual(item.groupId, "superset")
            XCTAssertNil(item.targetWeight)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT exercise_id FROM session_sets"), "old")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT weight FROM session_sets"), 80)
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    func testNewEquipmentVocabularyUnderstandsBodyweightAndGymMachines() {
        let types = ["dumbbell", "bodyweight", "leg press", "seated calf raise machine", "cable"]
        XCTAssertEqual(AIPlanGeneratorView.extractEquipment(from: "just bodyweight", available: types), ["bodyweight"])
        XCTAssertEqual(AIPlanGeneratorView.extractEquipment(from: "only machines", available: types), ["leg press", "seated calf raise machine"])
    }
    #endif
}
