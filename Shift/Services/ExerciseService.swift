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
}
