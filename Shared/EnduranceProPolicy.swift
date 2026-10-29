import Foundation

struct EnduranceWeekPreview: Codable, Equatable, Sendable {
    var userID: String
    var programID: String
    var sessionIDs: [String]
    var createdAt: Date
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", programID = "program_id", sessionIDs = "session_ids", createdAt = "created_at"
    }
}

enum EndurancePlanningAccess: Equatable {
    case checking, pro, freeWeek, upgradeRequired, unavailable
    var canPlan: Bool { self == .pro || self == .freeWeek }
}

enum EnduranceProPolicy {
    static func planningAccess(isChecking: Bool, isPro: Bool, previewChecked: Bool, hasUsedPreview: Bool) -> EndurancePlanningAccess {
        if isChecking { return .checking }
        if isPro { return .pro }
        if hasUsedPreview { return .upgradeRequired }
        return previewChecked ? .freeWeek : .unavailable
    }
    static func isValidPreview(_ sessions: [TrainingSession], owner: String, programID: String) -> Bool {
        guard (1...7).contains(sessions.count), UUID(uuidString: programID) != nil,
              Set(sessions.map(\.id)).count == sessions.count,
              sessions.allSatisfy({ $0.isValid && $0.userId == owner && $0.programID == programID && $0.kind == .endurance
                  && $0.status == .scheduled && (300...10_800).contains($0.targetSeconds ?? 0) }),
              let first = sessions.map(\.scheduledAt).min(), let last = sessions.map(\.scheduledAt).max() else { return false }
        return last.timeIntervalSince(first) < 7 * 86_400
    }
}
