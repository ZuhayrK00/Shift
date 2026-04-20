import Foundation
import WatchConnectivity
import WidgetKit

/// Watch-side WatchConnectivity manager.
/// Receives application context from iPhone and sends workout actions.
@Observable
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private(set) var context: WatchContext?
    private(set) var isPhoneReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send actions to iPhone

    func startSession(name: String = "Workout", completion: @escaping (String?, String?, Date?) -> Void) {
        send(["action": WatchAction.startSession.rawValue, "name": name]) { reply in
            let id = reply["sessionId"] as? String
            let name = reply["name"] as? String
            let dateStr = reply["startedAt"] as? String
            let date = dateStr.flatMap { ISO8601DateFormatter().date(from: $0) }
            completion(id, name, date)
        }
    }

    func startSessionFromPlan(planId: String, completion: @escaping (String?, String?, Date?) -> Void) {
        send(["action": WatchAction.startSessionFromPlan.rawValue, "planId": planId]) { reply in
            let id = reply["sessionId"] as? String
            let name = reply["name"] as? String
            let dateStr = reply["startedAt"] as? String
            let date = dateStr.flatMap { ISO8601DateFormatter().date(from: $0) }
            completion(id, name, date)
        }
    }

    func logSet(sessionId: String, exerciseId: String, reps: Int, weight: Double?, setType: String = "normal", completion: @escaping (Bool) -> Void) {
        var msg: [String: Any] = [
            "action": WatchAction.logSet.rawValue,
            "sessionId": sessionId,
            "exerciseId": exerciseId,
            "reps": reps,
            "setType": setType
        ]
        if let weight { msg["weight"] = weight }

        send(msg) { reply in
            completion(reply["success"] as? Bool ?? false)
        }
    }

    func finishSession(sessionId: String, completion: @escaping (Bool) -> Void) {
        send(["action": WatchAction.finishSession.rawValue, "sessionId": sessionId]) { reply in
            completion(reply["success"] as? Bool ?? false)
        }
    }

    func addExercise(sessionId: String, exerciseId: String, completion: @escaping (Bool) -> Void) {
        send(["action": WatchAction.addExercise.rawValue, "sessionId": sessionId, "exerciseId": exerciseId]) { reply in
            completion(reply["success"] as? Bool ?? false)
        }
    }

    func deleteSession(sessionId: String, completion: @escaping (Bool) -> Void) {
        send(["action": WatchAction.deleteSession.rawValue, "sessionId": sessionId]) { reply in
            completion(reply["success"] as? Bool ?? false)
        }
    }

    func requestSync() {
        send(["action": WatchAction.requestSync.rawValue]) { _ in }
    }

    // MARK: - Private

    private func send(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard WCSession.default.activationState == .activated else {
            replyHandler(["error": "Not activated"])
            return
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: replyHandler, errorHandler: { error in
                print("[WatchSession] sendMessage error: \(error.localizedDescription)")
                // Fall back to transferUserInfo (no reply, but guaranteed delivery)
                WCSession.default.transferUserInfo(message)
                replyHandler(["error": error.localizedDescription])
            })
        } else {
            // Queue for delivery when iPhone wakes
            WCSession.default.transferUserInfo(message)
            replyHandler(["queued": true])
        }
    }

    // MARK: - Write snapshot for complications

    private func writeSnapshotForComplications() {
        guard let ctx = context else { return }
        let snapshot = WidgetSnapshot(
            workoutsThisWeek: ctx.snapshot.workoutsThisWeek,
            weeklyGoal: ctx.snapshot.weeklyGoal,
            stepsToday: ctx.snapshot.stepsToday,
            stepGoal: ctx.snapshot.stepGoal,
            workedOutToday: ctx.snapshot.workedOutToday,
            latestWeight: nil,
            latestWeightUnit: ctx.settings.weightUnit,
            weightTrend: [],
            currentStreak: ctx.snapshot.currentStreak,
            streakUnit: ctx.snapshot.streakUnit,
            updatedAt: Date()
        )
        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            // Check for any existing application context
            if !session.receivedApplicationContext.isEmpty {
                parseContext(session.receivedApplicationContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        parseContext(applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let contextDict = message["contextUpdate"] as? [String: Any] {
            parseContext(contextDict)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Save Pro status to app group for complications
        if let isPro = userInfo["isPro"] as? Bool {
            UserDefaults(suiteName: "group.com.zuhayrk.shift")?.set(isPro, forKey: "isPro")
        }

        // Handle complication snapshot updates (from transferCurrentComplicationUserInfo)
        if let snapDict = userInfo["snapshot"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: snapDict),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            snapshot.write()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func parseContext(_ dict: [String: Any]) {
        // Save Pro status to app group for complications
        if let isPro = dict["isPro"] as? Bool {
            UserDefaults(suiteName: "group.com.zuhayrk.shift")?.set(isPro, forKey: "isPro")
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let ctx = try? JSONDecoder().decode(WatchContext.self, from: data) else { return }

        Task { @MainActor in
            self.context = ctx
            self.writeSnapshotForComplications()
        }
    }
}
