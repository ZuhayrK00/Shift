import Foundation
@preconcurrency import GRDB

// MARK: - Supporting types

struct WorkoutPlanWithCount: Identifiable {
    var plan: WorkoutPlan
    var exerciseCount: Int
    var muscleGroups: [String]       // unique muscle group names
    var exerciseImageUrls: [String]  // first few exercise image URLs
    var estimatedMinutes: Int        // estimated workout duration
    var id: String { plan.id }
}

struct PlanExercisePatch {
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetWeight: Double?
    var restSeconds: Int?
}

// MARK: - PlanRepository

struct PlanRepository {

    // MARK: - Plans

    static func findPlansWithCount(userId: String) async throws -> [WorkoutPlanWithCount] {
        try await AppDatabase.shared.dbPool.read { db in
            // First get plans with counts
            let planSql = """
                SELECT wp.*, COUNT(pe.id) AS exercise_count
                FROM workout_plans wp
                LEFT JOIN plan_exercises pe ON pe.plan_id = wp.id
                WHERE wp.user_id = ?
                GROUP BY wp.id
                ORDER BY wp.position ASC, wp.created_at ASC
                """
            let planRows = try Row.fetchAll(db, sql: planSql, arguments: [userId])

            // For each plan, get muscle groups and image URLs
            let detailSql = """
                SELECT mg.name AS muscle_group, e.image_url
                FROM plan_exercises pe
                JOIN exercises e ON e.id = pe.exercise_id
                JOIN muscle_groups mg ON mg.id = e.primary_muscle_id
                WHERE pe.plan_id = ?
                ORDER BY pe.position ASC
                """

            return try planRows.map { row in
                let plan = try WorkoutPlan(row: row)
                let exerciseCount: Int = row["exercise_count"] ?? 0

                let detailRows = try Row.fetchAll(db, sql: detailSql, arguments: [plan.id])

                var seenGroups = Set<String>()
                var muscleGroups: [String] = []
                var imageUrls: [String] = []

                for detailRow in detailRows {
                    if let group: String = detailRow["muscle_group"], seenGroups.insert(group).inserted {
                        muscleGroups.append(group)
                    }
                    if let url: String = detailRow["image_url"], imageUrls.count < 4 {
                        imageUrls.append(url)
                    }
                }

                // Fetch plan exercises for duration estimate
                let planExercises = try PlanExercise
                    .filter(Column("plan_id") == plan.id)
                    .fetchAll(db)
                let estimatedMinutes = WorkoutDurationEstimator.estimate(exercises: planExercises)

                return WorkoutPlanWithCount(
                    plan: plan,
                    exerciseCount: exerciseCount,
                    muscleGroups: muscleGroups,
                    exerciseImageUrls: imageUrls,
                    estimatedMinutes: estimatedMinutes
                )
            }
        }
    }

    static func findById(_ id: String) async throws -> WorkoutPlan? {
        try await AppDatabase.shared.dbPool.read { db in
            try WorkoutPlan.fetchOne(db, key: id)
        }
    }

    static func insert(_ plan: WorkoutPlan) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try plan.insert(db)
        }
    }

    static func update(_ id: String, name: String?, notes: String?) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            var setClauses: [String] = []
            var args: [DatabaseValue] = []

            if let name {
                setClauses.append("name = ?")
                args.append(name.databaseValue)
            }
            if let notes {
                setClauses.append("notes = ?")
                args.append(notes.databaseValue)
            }

            guard !setClauses.isEmpty else { return }

            let sql = "UPDATE workout_plans SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            args.append(id.databaseValue)
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }

    static func delete(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            // Delete child plan_exercises first to avoid orphans
            try db.execute(
                sql: "DELETE FROM plan_exercises WHERE plan_id = ?",
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM workout_plans WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Updates the position of multiple plans in a single transaction.
    static func reorder(_ planPositions: [(id: String, position: Int)]) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            for item in planPositions {
                try db.execute(
                    sql: "UPDATE workout_plans SET position = ? WHERE id = ?",
                    arguments: [item.position, item.id]
                )
            }
        }
    }

    // MARK: - Plan exercises

    static func findExercises(planId: String) async throws -> [PlanExercise] {
        try await AppDatabase.shared.dbPool.read { db in
            try PlanExercise
                .filter(Column("plan_id") == planId)
                .order(Column("position").asc)
                .fetchAll(db)
        }
    }

    /// Returns the maximum position value for the plan, or -1 if the plan has no exercises yet.
    static func findMaxPosition(planId: String) async throws -> Int {
        try await AppDatabase.shared.dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT MAX(position) AS max_pos FROM plan_exercises WHERE plan_id = ?",
                arguments: [planId]
            )
            return (row?["max_pos"] as Int?) ?? -1
        }
    }

    static func insertExercise(_ pe: PlanExercise) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try pe.insert(db)
        }
    }

    static func updateExercise(_ id: String, patch: PlanExercisePatch) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            var setClauses: [String] = []
            var args: [DatabaseValue] = []

            if let targetSets = patch.targetSets {
                setClauses.append("target_sets = ?")
                args.append(targetSets.databaseValue)
            }
            if let targetRepsMin = patch.targetRepsMin {
                setClauses.append("target_reps_min = ?")
                args.append(targetRepsMin.databaseValue)
            }
            if let targetRepsMax = patch.targetRepsMax {
                setClauses.append("target_reps_max = ?")
                args.append(targetRepsMax.databaseValue)
            }
            if let targetWeight = patch.targetWeight {
                setClauses.append("target_weight = ?")
                args.append(targetWeight.databaseValue)
            }
            if let restSeconds = patch.restSeconds {
                setClauses.append("rest_seconds = ?")
                args.append(restSeconds.databaseValue)
            }

            guard !setClauses.isEmpty else { return }

            let sql = "UPDATE plan_exercises SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            args.append(id.databaseValue)
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }

    static func deleteExercise(_ id: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM plan_exercises WHERE id = ?",
                arguments: [id]
            )
        }
    }

    static func reorderExercises(_ positions: [(id: String, position: Int)]) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            for item in positions {
                try db.execute(
                    sql: "UPDATE plan_exercises SET position = ? WHERE id = ?",
                    arguments: [item.position, item.id]
                )
            }
        }
    }

    static func deleteExercises(planId: String) async throws {
        try await AppDatabase.shared.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM plan_exercises WHERE plan_id = ?",
                arguments: [planId]
            )
        }
    }
}
