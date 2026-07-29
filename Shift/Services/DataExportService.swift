import Foundation

struct ShiftDataExport: Codable {
    var exportedAt: Date
    var workouts: [ExportWorkout]
    var plans: [ExportPlan]
    var weightEntries: [WeightEntry]
    var bodyMeasurements: [BodyMeasurement]
    var progressPhotos: [ProgressPhoto]
}

struct ExportWorkout: Codable {
    var session: WorkoutSession
    var sets: [ExportSet]
}

struct ExportSet: Codable {
    var set: SessionSet
    var exerciseName: String
}

struct ExportPlan: Codable {
    var plan: WorkoutPlan
    var exercises: [ExportPlanExercise]
}

struct ExportPlanExercise: Codable {
    var planExercise: PlanExercise
    var exerciseName: String
}

enum DataExportService {
    static func makeExport(userID: String) async throws -> [URL] {
        let completed = try await SessionRepository.findCompleted(userId: userID)
        let inProgress = try await SessionRepository.findInProgress(userId: userID)
        let sessions = (completed + inProgress).sorted { $0.startedAt > $1.startedAt }
        let planItems = try await PlanRepository.findPlansWithCount(userId: userID)

        var allExerciseIDs = Set<String>()
        var setsBySession: [String: [SessionSet]] = [:]
        for session in sessions {
            let sets = try await SessionSetRepository.findAllForSession(session.id)
            setsBySession[session.id] = sets
            allExerciseIDs.formUnion(sets.map(\.exerciseId))
        }
        var planExercisesByPlan: [String: [PlanExercise]] = [:]
        for item in planItems {
            let exercises = try await PlanRepository.findExercises(planId: item.plan.id)
            planExercisesByPlan[item.plan.id] = exercises
            allExerciseIDs.formUnion(exercises.map(\.exerciseId))
        }
        let exerciseMap = try await ExerciseRepository.findByIds(Array(allExerciseIDs))

        let workouts = sessions.map { session in
            ExportWorkout(
                session: session,
                sets: (setsBySession[session.id] ?? []).map {
                    ExportSet(
                        set: $0,
                        exerciseName: exerciseMap[$0.exerciseId]?.displayName ?? "Unknown exercise"
                    )
                }
            )
        }
        let plans = planItems.map { item in
            ExportPlan(
                plan: item.plan,
                exercises: (planExercisesByPlan[item.plan.id] ?? []).map {
                    ExportPlanExercise(
                        planExercise: $0,
                        exerciseName: exerciseMap[$0.exerciseId]?.displayName ?? "Unknown exercise"
                    )
                }
            )
        }
        async let weights = WeightEntryRepository.findAll(userId: userID)
        async let measurements = BodyMeasurementRepository.findAll(userId: userID)
        async let photos = ProgressPhotoRepository.findAll(userId: userID)
        let bundle = try await ShiftDataExport(
            exportedAt: Date(),
            workouts: workouts,
            plans: plans,
            weightEntries: weights,
            bodyMeasurements: measurements,
            progressPhotos: photos
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shift-Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jsonURL = folder.appendingPathComponent("shift-data.json")
        let csvURL = folder.appendingPathComponent("shift-workouts.csv")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bundle).write(to: jsonURL, options: .atomic)
        try workoutCSV(workouts).write(to: csvURL, atomically: true, encoding: .utf8)
        return [jsonURL, csvURL]
    }

    private static func workoutCSV(_ workouts: [ExportWorkout]) -> String {
        var rows = [
            "workout_id,workout_name,started_at,ended_at,exercise,set_number,set_type,reps,weight_kg,rpe,notes"
        ]
        let formatter = ISO8601DateFormatter.shared
        for workout in workouts {
            for item in workout.sets {
                let set = item.set
                let endedAt = workout.session.endedAt.map {
                    formatter.string(from: $0)
                } ?? ""
                let weight = set.weight.map { String($0) } ?? ""
                let rpe = set.rpe.map { String($0) } ?? ""
                let fields: [String] = [
                    workout.session.id,
                    workout.session.name,
                    formatter.string(from: workout.session.startedAt),
                    endedAt,
                    item.exerciseName,
                    String(set.setNumber),
                    set.setType.rawValue,
                    String(set.reps),
                    weight,
                    rpe,
                    set.notes ?? ""
                ]
                rows.append(fields.map { csvField($0) }.joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
