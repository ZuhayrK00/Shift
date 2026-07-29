import Foundation

struct WeeklyTrainingSummary: Equatable, Sendable {
    var workoutCount: Int
    var workingSetCount: Int
    var volume: Double
    var volumeChangePercent: Int?
    var muscleNames: [String]
}

enum WeeklyTrainingSummaryService {
    static func load(
        userID: String,
        weekStartsOn: String,
        now: Date = Date()
    ) async throws -> WeeklyTrainingSummary {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOn.lowercased() == "sunday" ? 1 : 2
        let start = startOfWeek(containing: now, calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let nextStart = calendar.date(byAdding: .day, value: 7, to: start) ?? now

        let sessions = try await SessionRepository.findCompleted(userId: userID)
        let current = sessions.filter { $0.startedAt >= start && $0.startedAt < nextStart }
        let previous = sessions.filter { $0.startedAt >= previousStart && $0.startedAt < start }

        let currentSets = try await sets(for: current)
        let previousSets = try await sets(for: previous)
        let exerciseIDs = Array(Set(currentSets.map(\.exerciseId)))
        let exerciseMap = try await ExerciseRepository.findByIds(exerciseIDs)
        let groups = try await MuscleGroupRepository.findAll()
        let groupNames = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        let muscles = Set(exerciseMap.values.compactMap {
            groupNames[$0.primaryMuscleId] ?? $0.bodyPart ?? $0.category
        }).sorted()

        let currentVolume = volume(of: currentSets)
        let previousVolume = volume(of: previousSets)
        let change = previousVolume > 0
            ? Int((((currentVolume - previousVolume) / previousVolume) * 100).rounded())
            : nil

        return WeeklyTrainingSummary(
            workoutCount: current.count,
            workingSetCount: currentSets.filter {
                $0.isCompleted && $0.setType != .warmup
            }.count,
            volume: currentVolume,
            volumeChangePercent: change,
            muscleNames: muscles
        )
    }

    private static func sets(for sessions: [WorkoutSession]) async throws -> [SessionSet] {
        var result: [SessionSet] = []
        for session in sessions {
            result.append(contentsOf: try await SessionSetRepository.findForSession(session.id))
        }
        return result
    }

    private static func volume(of sets: [SessionSet]) -> Double {
        sets.filter { $0.isCompleted && $0.setType != .warmup }.reduce(0) {
            $0 + (($1.weight ?? 0) * Double($1.reps))
        }
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromStart, to: startOfDay) ?? startOfDay
    }
}
