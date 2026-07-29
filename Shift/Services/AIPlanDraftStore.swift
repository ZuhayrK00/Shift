import Foundation

#if canImport(FoundationModels)

@available(iOS 26, *)
struct AIPlanDraftSnapshot: Codable {
    var plan: GeneratedPlan
    var savedAt: Date
}

@available(iOS 26, *)
enum AIPlanDraftStore {
    static func save(_ plan: GeneratedPlan, userID: String, quickSession: Bool) {
        let snapshot = AIPlanDraftSnapshot(plan: plan, savedAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key(userID: userID, quickSession: quickSession))
    }

    static func load(userID: String, quickSession: Bool) -> AIPlanDraftSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(userID: userID, quickSession: quickSession)),
              let snapshot = try? JSONDecoder().decode(AIPlanDraftSnapshot.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(snapshot.savedAt) < 24 * 60 * 60 else {
            clear(userID: userID, quickSession: quickSession)
            return nil
        }
        return snapshot
    }

    static func clear(userID: String, quickSession: Bool) {
        UserDefaults.standard.removeObject(forKey: key(userID: userID, quickSession: quickSession))
    }

    private static func key(userID: String, quickSession: Bool) -> String {
        "shift.aiDraft.\(userID).\(quickSession ? "quick" : "program")"
    }
}
#endif
