import Foundation

// MARK: - HistorySession

struct HistorySession: Identifiable {
    var sessionId: String
    var date: Date
    var sets: [SessionSet]
    var id: String { sessionId }
}

// MARK: - TimeFilter

enum TimeFilter: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths   = "6M"
    case oneYear     = "1Y"
    case ytd         = "YTD"
    case all         = "ALL"

    /// Returns the earliest date that falls within this filter window, or nil for "all time".
    func cutoffDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
        case .sixMonths:   return cal.date(byAdding: .month, value: -6, to: now)
        case .oneYear:     return cal.date(byAdding: .year,  value: -1, to: now)
        case .ytd:         return cal.date(from: cal.dateComponents([.year], from: now))
        case .all:         return nil
        }
    }

    var label: String {
        switch self {
        case .threeMonths: return "3 months"
        case .sixMonths:   return "6 months"
        case .oneYear:     return "1 year"
        case .ytd:         return "Year to date"
        case .all:         return "All time"
        }
    }
}

// MARK: - ChartPoint

struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

// MARK: - PersonalBestStat

struct PersonalBestStat {
    var label: String
    var value: String
    var subtitle: String
    var icon: String          // SF Symbol name
}

// MARK: - ProgressData

struct ProgressData {
    var heaviestWeight: [ChartPoint]
    var estimated1RM: [ChartPoint]
    var totalVolume: [ChartPoint]
    var personalBests: [PersonalBestStat]
    var rangeLabel: String
}

// MARK: - ExerciseHistoryService

struct ExerciseHistoryService {

    // MARK: - History

    /// Returns completed sets for the exercise, grouped by session, newest first.
    static func getHistory(_ exerciseId: String) async throws -> [HistorySession] {
        let raw = try await SessionSetRepository.findHistory(exerciseId: exerciseId)

        // Group by sessionId while preserving newest-first order
        var order: [String] = []
        var groups: [String: (date: Date, sets: [SessionSet])] = [:]

        for item in raw {
            let sid = item.set.sessionId
            if groups[sid] == nil {
                order.append(sid)
                groups[sid] = (date: item.sessionStartedAt, sets: [])
            }
            groups[sid]?.sets.append(item.set)
        }

        return order.compactMap { sid -> HistorySession? in
            guard let entry = groups[sid] else { return nil }
            return HistorySession(sessionId: sid, date: entry.date, sets: entry.sets)
        }
    }

    // MARK: - Progress

    /// Computes chart-ready progress data for the exercise over the given time window.
    static func getProgress(
        _ exerciseId: String,
        filter: TimeFilter,
        unit: String
    ) async throws -> ProgressData {
        let allHistory = try await getHistory(exerciseId)
        let cutoff = filter.cutoffDate()

        let filtered = allHistory.filter { session in
            guard let cutoff else { return true }
            return session.date >= cutoff
        }

        var heaviestWeightPoints: [ChartPoint] = []
        var estimated1RMPoints:   [ChartPoint] = []
        var totalVolumePoints:    [ChartPoint] = []

        // Accumulators for personal-best stats (computed from ALL history, not filtered)
        var allTimeMaxWeight: Double = 0
        var allTimeMax1RM:    Double = 0
        var allTimeMaxVolume: Double = 0

        for session in allHistory {
            let allSets = session.sets.filter { $0.setType == .normal && $0.weight != nil }
            guard !allSets.isEmpty else { continue }

            let maxW = allSets.compactMap { $0.weight }.max() ?? 0
            let vol = allSets.reduce(0.0) { acc, s in acc + (s.weight ?? 0) * Double(s.reps) }
            let e1RM: Double = {
                let best = allSets.max { a, b in
                    let aEst = (a.weight ?? 0) * (1 + Double(a.reps) / 30)
                    let bEst = (b.weight ?? 0) * (1 + Double(b.reps) / 30)
                    return aEst < bEst
                }
                guard let s = best, let w = s.weight else { return 0 }
                return w * (1 + Double(s.reps) / 30)
            }()

            if maxW > allTimeMaxWeight { allTimeMaxWeight = maxW }
            if e1RM > allTimeMax1RM    { allTimeMax1RM    = e1RM }
            if vol  > allTimeMaxVolume { allTimeMaxVolume = vol  }
        }

        for session in filtered.reversed() {  // chronological for chart ordering
            let normalSets = session.sets.filter { $0.setType == .normal && $0.weight != nil }
            guard !normalSets.isEmpty else { continue }

            let maxWeight = normalSets.compactMap { $0.weight }.max() ?? 0
            let volume    = normalSets.reduce(0.0) { acc, s in
                acc + (s.weight ?? 0) * Double(s.reps)
            }
            let est1RM: Double = {
                // Brzycki formula approximation: weight * (1 + reps/30)
                let best = normalSets.max { a, b in
                    let aEst = (a.weight ?? 0) * (1 + Double(a.reps) / 30)
                    let bEst = (b.weight ?? 0) * (1 + Double(b.reps) / 30)
                    return aEst < bEst
                }
                guard let s = best, let w = s.weight else { return 0 }
                return w * (1 + Double(s.reps) / 30)
            }()

            let date = session.date
            heaviestWeightPoints.append(ChartPoint(date: date, value: convertWeight(maxWeight, to: unit)))
            estimated1RMPoints.append(ChartPoint(date: date, value: convertWeight(est1RM, to: unit)))
            totalVolumePoints.append(ChartPoint(date: date, value: convertWeight(volume, to: unit)))
        }

        let personalBests: [PersonalBestStat] = [
            PersonalBestStat(
                label: "Best weight",
                value: formatWeight(allTimeMaxWeight, unit: unit),
                subtitle: "Heaviest single lift",
                icon: "trophy"
            ),
            PersonalBestStat(
                label: "Est. 1RM",
                value: formatWeight(allTimeMax1RM, unit: unit),
                subtitle: "Estimated one-rep max",
                icon: "dumbbell"
            ),
            PersonalBestStat(
                label: "Best volume",
                value: formatWeight(allTimeMaxVolume, unit: unit),
                subtitle: "Most volume in a session",
                icon: "chart.bar"
            ),
            PersonalBestStat(
                label: "Sessions",
                value: "\(filtered.count)",
                subtitle: "In selected range",
                icon: "bolt"
            )
        ]

        return ProgressData(
            heaviestWeight: heaviestWeightPoints,
            estimated1RM: estimated1RMPoints,
            totalVolume: totalVolumePoints,
            personalBests: personalBests,
            rangeLabel: filter.label
        )
    }

    // MARK: - Private helpers

    // Weight formatting uses the global formatWeight() from Format.swift
}
