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

struct PlanExercisePatch: Sendable {
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    /// Outer nil leaves the value unchanged; inner nil clears it.
    var targetWeight: Double??
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

            let plans = try planRows.map { try WorkoutPlan(row: $0) }
            guard !plans.isEmpty else { return [] }
            let planIds = plans.map(\.id)
            let placeholders = planIds.map { _ in "?" }.joined(separator: ", ")

            // Fetch details for every plan in one query.
            let detailSql = """
                SELECT pe.plan_id, mg.name AS muscle_group, e.image_url
                FROM plan_exercises pe
                JOIN exercises e ON e.id = pe.exercise_id
                JOIN muscle_groups mg ON mg.id = e.primary_muscle_id
                WHERE pe.plan_id IN (\(placeholders))
                ORDER BY pe.plan_id, pe.position ASC
                """
            let detailRows = try Row.fetchAll(
                db,
                sql: detailSql,
                arguments: StatementArguments(planIds)
            )
            let allPlanExercises = try PlanExercise.fetchAll(
                db,
                sql: "SELECT * FROM plan_exercises WHERE plan_id IN (\(placeholders))",
                arguments: StatementArguments(planIds)
            )
            let detailsByPlan = Dictionary(grouping: detailRows) {
                $0["plan_id"] as String
            }
            let exercisesByPlan = Dictionary(grouping: allPlanExercises, by: \.planId)
            let countByPlan = Dictionary(uniqueKeysWithValues: planRows.map {
                ($0["id"] as String, $0["exercise_count"] as Int? ?? 0)
            })

            return plans.map { plan in
                let exerciseCount = countByPlan[plan.id] ?? 0

                var seenGroups = Set<String>()
                var muscleGroups: [String] = []
                var imageUrls: [String] = []

                for detailRow in detailsByPlan[plan.id] ?? [] {
                    if let group: String = detailRow["muscle_group"], seenGroups.insert(group).inserted {
                        muscleGroups.append(group)
                    }
                    if let url: String = detailRow["image_url"], imageUrls.count < 4 {
                        imageUrls.append(url)
                    }
                }

                let estimatedMinutes = WorkoutDurationEstimator.estimate(
                    exercises: exercisesByPlan[plan.id] ?? []
                )

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
            if let targetWeightUpdate = patch.targetWeight {
                if let targetWeight = targetWeightUpdate {
                    setClauses.append("target_weight = ?")
                    args.append(targetWeight.databaseValue)
                } else {
                    setClauses.append("target_weight = NULL")
                }
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
