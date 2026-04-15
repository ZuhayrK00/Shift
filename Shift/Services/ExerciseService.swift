import Foundation

// MARK: - ExerciseService

/// Pass-through orchestration over ExerciseRepository, MuscleGroupRepository, and
/// SessionSetRepository. Read-only — no mutations, no queue.
struct ExerciseService {

    static func listExercises() async throws -> [Exercise] {
        let exercises = try await ExerciseRepository.findAll()
        // Prefetch all exercise thumbnail images in the background
        let urls = exercises.compactMap { $0.imageUrl.flatMap(URL.init) }
        ImageCache.shared.prefetch(urls)
        return exercises
    }

    static func getById(_ id: String) async throws -> Exercise? {
        try await ExerciseRepository.findById(id)
    }

    /// Returns a dictionary keyed by exercise id. Missing ids are silently absent.
    static func getByIds(_ ids: [String]) async throws -> [String: Exercise] {
        try await ExerciseRepository.findByIds(ids)
    }

    static func listMuscleGroups() async throws -> [MuscleGroup] {
        try await MuscleGroupRepository.findAll()
    }

    /// Exercise ids ordered by how recently they were used in a completed session.
    static func getRecentlyUsedExerciseIds() async throws -> [String] {
        let userId = try authManager.requireUserId()
        return try await SessionSetRepository.findRecentlyUsedExerciseIds(userId: userId)
    }

    /// Top-N personal bests: heaviest weight per exercise across all completed sessions.
    static func getPersonalBests(limit: Int = 10) async throws -> [PersonalBest] {
        let userId = try authManager.requireUserId()
        return try await SessionSetRepository.findPersonalBests(userId: userId, limit: limit)
    }

    // MARK: - Custom exercise CRUD

    static func createExercise(
        name: String,
        primaryMuscleId: String,
        equipment: String? = nil,
        instructions: String? = nil,
        level: String? = nil,
        category: String? = nil,
        bodyPart: String? = nil
    ) async throws -> Exercise {
        let userId = try authManager.requireUserId()
        let id = UUID().uuidString.lowercased()
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)

        let exercise = Exercise(
            id: id,
            name: name,
            slug: slug,
            instructions: instructions,
            primaryMuscleId: primaryMuscleId,
            secondaryMuscleIds: [],
            equipment: equipment?.lowercased(),
            isBuiltIn: false,
            createdBy: userId,
            level: level?.lowercased(),
            category: category?.lowercased(),
            bodyPart: bodyPart?.lowercased()
        )

        try await ExerciseRepository.upsert(exercise)
        try await enqueue(table: "exercises", op: "insert", payload: exercisePayload(exercise))
        return exercise
    }

    static func updateExercise(
        _ id: String,
        name: String,
        primaryMuscleId: String,
        equipment: String?,
        instructions: String?,
        level: String?,
        category: String?,
        bodyPart: String?
    ) async throws {
        guard var exercise = try await ExerciseRepository.findById(id) else { return }
        guard !exercise.isBuiltIn else { return } // can't edit built-ins

        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)

        exercise.name = name
        exercise.slug = slug
        exercise.primaryMuscleId = primaryMuscleId
        exercise.equipment = equipment?.lowercased()
        exercise.instructions = instructions
        exercise.level = level?.lowercased()
        exercise.category = category?.lowercased()
        exercise.bodyPart = bodyPart?.lowercased()

        try await ExerciseRepository.upsert(exercise)
        try await enqueue(table: "exercises", op: "update", payload: exercisePayload(exercise))
    }

    static func deleteExercise(_ id: String) async throws {
        try await ExerciseRepository.delete(id)
        try await enqueue(table: "exercises", op: "delete", payload: ["id": id])
    }

    // MARK: - Private helpers

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

    private static func exercisePayload(_ ex: Exercise) -> [String: Any] {
        var payload: [String: Any] = [
            "id": ex.id,
            "name": ex.name,
            "slug": ex.slug,
            "primary_muscle_id": ex.primaryMuscleId,
            "secondary_muscle_ids": ex.secondaryMuscleIds,
            "is_built_in": ex.isBuiltIn,
        ]
        payload["created_by"] = ex.createdBy.map { $0 as Any } ?? NSNull()
        payload["equipment"] = ex.equipment.map { $0 as Any } ?? NSNull()
        payload["instructions"] = ex.instructions.map { $0 as Any } ?? NSNull()
        payload["level"] = ex.level.map { $0 as Any } ?? NSNull()
        payload["category"] = ex.category.map { $0 as Any } ?? NSNull()
        payload["body_part"] = ex.bodyPart.map { $0 as Any } ?? NSNull()
        payload["image_url"] = NSNull()
        payload["secondary_image_url"] = NSNull()
        payload["force"] = ex.force.map { $0 as Any } ?? NSNull()
        payload["mechanic"] = ex.mechanic.map { $0 as Any } ?? NSNull()
        payload["instructions_steps"] = NSNull()
        payload["description"] = ex.description.map { $0 as Any } ?? NSNull()
        return payload
    }
}
