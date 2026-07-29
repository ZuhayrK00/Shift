import Foundation
import StoreKit
import WatchConnectivity
import WidgetKit

/// Watch-side connectivity and entitlement coordinator.
///
/// StoreKit is verified directly on Watch so a paid customer never needs to
/// open the iPhone app merely to unlock the Watch app. Phone state remains the
/// source of workout/account data and is persisted for offline use.
@Observable
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private(set) var context: WatchContext?
    private(set) var isPhoneReachable = false
    private(set) var isPro = StoreEntitlementCache.read()?.isPro ?? false
    private(set) var isCheckingEntitlement = true
    private(set) var lastSyncError: String?

    private var transactionListener: Task<Void, Never>?

    private static let contextKey = "watchContext.v2"
    private static let contextSuite = "group.com.zuhayrk.shift"

    var isSignedIn: Bool {
        guard let context else { return false }
        return context.isSignedIn ?? !context.userId.isEmpty
    }

    var canUseProFeatures: Bool {
        isPro && isSignedIn
    }

    private override init() {
        if let data = UserDefaults(suiteName: Self.contextSuite)?.data(forKey: Self.contextKey) {
            context = try? JSONDecoder().decode(WatchContext.self, from: data)
        }
        super.init()
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        Task { await refreshEntitlement() }
    }

    // MARK: - Independent StoreKit entitlement

    func refreshEntitlement() async {
        let snapshot = await StoreEntitlementVerifier.currentSnapshot()
        StoreEntitlementCache.write(snapshot)
        await MainActor.run {
            isPro = snapshot.isPro
            isCheckingEntitlement = false
            updateSharedProState()
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in Transaction.updates {
                guard let self else { return }
                await self.refreshEntitlement()
            }
        }
    }

    @MainActor
    private func applyPhoneEntitlement(isPro: Bool, verifiedAt: Date) {
        if let cached = StoreEntitlementCache.read(), cached.verifiedAt > verifiedAt {
            return
        }
        let snapshot = StoreEntitlementSnapshot(
            isPro: isPro,
            activeProductIDs: [],
            verifiedAt: verifiedAt
        )
        StoreEntitlementCache.write(snapshot)
        self.isPro = isPro
        isCheckingEntitlement = false
        updateSharedProState()
    }

    @MainActor
    private func updateSharedProState() {
        UserDefaults(suiteName: Self.contextSuite)?
            .set(canUseProFeatures, forKey: "isPro")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Send actions to iPhone

    func startSession(
        name: String = "Workout",
        completion: @escaping (String?, String?, Date?) -> Void
    ) {
        let actionId = UUID().uuidString.lowercased()
        let requestedSessionId = UUID().uuidString.lowercased()
        let startedAt = Date()
        send([
            "action": WatchAction.startSession.rawValue,
            "actionId": actionId,
            "sessionId": requestedSessionId,
            "name": name,
            "startedAt": ISO8601DateFormatter().string(from: startedAt)
        ]) { reply in
            guard Self.accepted(reply) else {
                completion(nil, nil, nil)
                return
            }
            let id = reply["sessionId"] as? String ?? requestedSessionId
            let returnedName = reply["name"] as? String ?? name
            let dateString = reply["startedAt"] as? String
            let returnedDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
                ?? startedAt
            completion(id, returnedName, returnedDate)
        }
    }

    func startSessionFromPlan(
        planId: String,
        completion: @escaping (String?, String?, Date?) -> Void
    ) {
        let actionId = UUID().uuidString.lowercased()
        let requestedSessionId = UUID().uuidString.lowercased()
        let startedAt = Date()
        let fallbackName = context?.plans.first(where: { $0.id == planId })?.name ?? "Workout"
        send([
            "action": WatchAction.startSessionFromPlan.rawValue,
            "actionId": actionId,
            "sessionId": requestedSessionId,
            "planId": planId,
            "startedAt": ISO8601DateFormatter().string(from: startedAt)
        ]) { reply in
            guard Self.accepted(reply) else {
                completion(nil, nil, nil)
                return
            }
            let id = reply["sessionId"] as? String ?? requestedSessionId
            let returnedName = reply["name"] as? String ?? fallbackName
            let dateString = reply["startedAt"] as? String
            let returnedDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
                ?? startedAt
            completion(id, returnedName, returnedDate)
        }
    }

    func logSet(
        sessionId: String,
        exerciseId: String,
        reps: Int,
        weight: Double?,
        setType: String = "normal",
        completion: @escaping (Bool) -> Void
    ) {
        var message: [String: Any] = [
            "action": WatchAction.logSet.rawValue,
            "actionId": UUID().uuidString.lowercased(),
            "sessionId": sessionId,
            "exerciseId": exerciseId,
            "reps": reps,
            "setType": setType
        ]
        if let weight { message["weight"] = weight }
        send(message) { completion(Self.accepted($0)) }
    }

    func finishSession(sessionId: String, completion: @escaping (Bool) -> Void) {
        send([
            "action": WatchAction.finishSession.rawValue,
            "actionId": UUID().uuidString.lowercased(),
            "sessionId": sessionId
        ]) { completion(Self.accepted($0)) }
    }

    func addExercise(
        sessionId: String,
        exerciseId: String,
        completion: @escaping (Bool) -> Void
    ) {
        send([
            "action": WatchAction.addExercise.rawValue,
            "actionId": UUID().uuidString.lowercased(),
            "sessionId": sessionId,
            "exerciseId": exerciseId
        ]) { completion(Self.accepted($0)) }
    }

    func deleteSession(sessionId: String, completion: @escaping (Bool) -> Void) {
        send([
            "action": WatchAction.deleteSession.rawValue,
            "actionId": UUID().uuidString.lowercased(),
            "sessionId": sessionId
        ]) { completion(Self.accepted($0)) }
    }

    func requestSync() {
        send(["action": WatchAction.requestSync.rawValue]) { _ in }
    }

    private static func accepted(_ reply: [String: Any]) -> Bool {
        WatchDeliveryPolicy.isAccepted(
            success: reply["success"] as? Bool == true,
            queued: reply["queued"] as? Bool == true,
            duplicate: reply["duplicate"] as? Bool == true
        )
    }

    private func send(
        _ message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            replyHandler(["error": "Watch connection is not active."])
            return
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                message,
                replyHandler: replyHandler,
                errorHandler: { [weak self] error in
                    self?.queue(message, fallbackError: error, replyHandler: replyHandler)
                }
            )
        } else {
            queue(message, fallbackError: nil, replyHandler: replyHandler)
        }
    }

    private func queue(
        _ message: [String: Any],
        fallbackError: Error?,
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            replyHandler(["error": fallbackError?.localizedDescription ?? "Watch connection is not active."])
            return
        }
        WCSession.default.transferUserInfo(message)
        replyHandler(["queued": true])
    }

    // MARK: - Persist and apply incoming state

    @MainActor
    private func persistContext(_ context: WatchContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        UserDefaults(suiteName: Self.contextSuite)?.set(data, forKey: Self.contextKey)
    }

    @MainActor
    private func applySignedOutState() {
        context = nil
        UserDefaults(suiteName: Self.contextSuite)?.removeObject(forKey: Self.contextKey)
        UserDefaults(suiteName: Self.contextSuite)?.removeObject(forKey: WidgetSnapshot.key)
        updateSharedProState()
    }

    @MainActor
    private func applyEntitlement(from dictionary: [String: Any]) {
        guard let pro = dictionary["isPro"] as? Bool else { return }
        let timestamp = dictionary["entitlementVerifiedAt"] as? Double
            ?? Date().timeIntervalSince1970
        applyPhoneEntitlement(
            isPro: pro,
            verifiedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func parseContext(_ dictionary: [String: Any]) {
        if dictionary["stateType"] as? String == "signedOut" {
            Task { @MainActor in
                applySignedOutState()
                applyEntitlement(from: dictionary)
            }
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let incoming = try? JSONDecoder().decode(WatchContext.self, from: data) else {
            Task { @MainActor in
                lastSyncError = "The iPhone sent data this Watch version could not read."
            }
            return
        }

        Task { @MainActor in
            applyEntitlement(from: dictionary)
            let incomingDate = incoming.generatedAt ?? .distantPast
            let currentDate = context?.generatedAt ?? .distantPast
            guard incomingDate >= currentDate else { return }
            context = incoming
            lastSyncError = nil
            persistContext(incoming)
            updateSharedProState()
            writeSnapshotForComplications()
        }
    }

    private func applySnapshot(_ dictionary: [String: Any]) {
        guard let snapshotDictionary = dictionary["snapshot"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: snapshotDictionary),
              let incoming = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return
        }
        Task { @MainActor in
            applyEntitlement(from: dictionary)
            if let existing = WidgetSnapshot.read(), existing.updatedAt > incoming.updatedAt {
                return
            }
            incoming.write()
            updateSharedProState()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func applyWorkoutUpdate(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let update = try? JSONDecoder().decode(WatchWorkoutUpdate.self, from: data) else {
            return
        }
        Task { @MainActor in
            guard var current = context,
                  current.userId == update.userId,
                  update.generatedAt >= (current.generatedAt ?? .distantPast) else { return }
            current.activeSession = update.activeSession
            current.generatedAt = update.generatedAt
            context = current
            persistContext(current)
        }
    }

    @MainActor
    private func writeSnapshotForComplications() {
        guard let context else { return }
        let incoming = WidgetSnapshot(
            workoutsThisWeek: context.snapshot.workoutsThisWeek,
            weeklyGoal: context.snapshot.weeklyGoal,
            stepsToday: context.snapshot.stepsToday,
            stepGoal: context.snapshot.stepGoal,
            workedOutToday: context.snapshot.workedOutToday,
            latestWeight: nil,
            latestWeightUnit: context.settings.weightUnit,
            weightTrend: [],
            currentStreak: context.snapshot.currentStreak,
            streakUnit: context.snapshot.streakUnit,
            updatedAt: context.snapshot.updatedAt ?? context.generatedAt ?? Date(),
            ownerUserId: context.userId,
            weekStart: context.snapshot.weekStart,
            schemaVersion: context.schemaVersion ?? 2
        )
        if let existing = WidgetSnapshot.read(), existing.updatedAt > incoming.updatedAt {
            return
        }
        incoming.write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            lastSyncError = error?.localizedDescription
        }
        guard activationState == .activated else { return }
        if !session.receivedApplicationContext.isEmpty {
            parseContext(session.receivedApplicationContext)
        }
        requestSync()
        Task { await refreshEntitlement() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        parseContext(applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
        if session.isReachable {
            requestSync()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let contextDictionary = message["contextUpdate"] as? [String: Any] {
            parseContext(contextDictionary)
        } else if message["stateType"] as? String == "snapshot" {
            applySnapshot(message)
        } else if message["stateType"] as? String == "workout" {
            applyWorkoutUpdate(message)
        } else if message["stateType"] as? String == "signedOut" {
            parseContext(message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo["stateType"] as? String == "snapshot" {
            applySnapshot(userInfo)
        } else if userInfo["stateType"] as? String == "workout" {
            applyWorkoutUpdate(userInfo)
        } else if userInfo["stateType"] as? String == "signedOut" {
            parseContext(userInfo)
        } else if userInfo["snapshot"] != nil {
            applySnapshot(userInfo)
        }
    }
}
