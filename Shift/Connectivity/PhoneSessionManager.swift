import Foundation
import WatchConnectivity

private actor WatchActionLedger {
    static let shared = WatchActionLedger()

    private let defaults = UserDefaults.standard
    private let prefix = "shift.watch.action."
    private var inFlight: Set<String> = []

    func begin(actionId: String) -> Bool {
        let key = prefix + actionId
        let now = Date().timeIntervalSince1970
        if let stored = defaults.object(forKey: key) as? Double {
            // Negative values are crash-safe in-flight reservations. A stale
            // reservation can be retried after five minutes.
            if stored >= 0 || -stored > now - 5 * 60 {
                return false
            }
            defaults.removeObject(forKey: key)
        } else if defaults.object(forKey: key) != nil {
            return false
        }
        guard !inFlight.contains(actionId) else { return false }
        inFlight.insert(actionId)
        defaults.set(-now, forKey: key)
        return true
    }

    func finish(actionId: String, succeeded: Bool) {
        inFlight.remove(actionId)
        if succeeded {
            defaults.set(Date().timeIntervalSince1970, forKey: prefix + actionId)
            removeExpiredEntries()
        } else {
            defaults.removeObject(forKey: prefix + actionId)
        }
    }

    private func removeExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(prefix) {
            if let timestamp = value as? Double,
               timestamp >= 0,
               timestamp < cutoff {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

extension Notification.Name {
    /// Posted when the Watch modifies workout data so phone views can refresh.
    static let watchDidUpdateWorkout = Notification.Name("watchDidUpdateWorkout")
}

/// iPhone-side WatchConnectivity manager.
/// Receives workout actions from the Watch and sends context updates.
@Observable
final class PhoneSessionManager: NSObject {
    static let shared = PhoneSessionManager()

    private(set) var isWatchReachable = false
    private(set) var isWatchPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncError: String?
    private let sendLock = NSLock()
    private var isSendingContext = false
    private var needsAnotherContextPass = false
    private var shouldRefreshEntitlementForNextPass = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send context to Watch

    func sendContextToWatch(refreshEntitlement: Bool = false) {
        guard WCSession.default.activationState == .activated else { return }
        refreshWatchState(WCSession.default)
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        let shouldStart = sendLock.withLock {
            shouldRefreshEntitlementForNextPass =
                shouldRefreshEntitlementForNextPass || refreshEntitlement
            if isSendingContext {
                needsAnotherContextPass = true
                return false
            }
            isSendingContext = true
            return true
        }
        guard shouldStart else { return }

        Task { [weak self] in
            guard let self else { return }
            while true {
                let shouldRefreshEntitlement = sendLock.withLock {
                    let value = self.shouldRefreshEntitlementForNextPass
                    self.shouldRefreshEntitlementForNextPass = false
                    return value
                }
                await sendContextPass(refreshEntitlement: shouldRefreshEntitlement)

                let shouldRepeat = sendLock.withLock {
                    if self.needsAnotherContextPass {
                        self.needsAnotherContextPass = false
                        return true
                    }
                    self.isSendingContext = false
                    return false
                }
                if !shouldRepeat { break }
            }
        }
    }

    private func sendContextPass(refreshEntitlement: Bool) async {
        if refreshEntitlement {
            // Re-verify entitlement from StoreKit before syncing to watch.
            // This ensures Pro status is fresh even if the app process was
            // killed and restarted by a WatchConnectivity wake.
            await StoreService.shared.updatePurchasedProducts(syncWatch: false)

            await WidgetDataService.updateSnapshot(
                knownProStatus: StoreService.shared.isPro
            )
        }
            let context = await buildContext()
            guard let data = try? JSONEncoder().encode(context),
                  var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[PhoneSession] Failed to encode context")
                return
            }

            // Include Pro status so the watch can update complications
            dict["isPro"] = StoreService.shared.isPro
            dict["entitlementVerifiedAt"] =
                StoreEntitlementCache.read()?.verifiedAt.timeIntervalSince1970
                ?? Date().timeIntervalSince1970

            do {
                try WCSession.default.updateApplicationContext(dict)
                await MainActor.run {
                    lastSyncDate = Date()
                    lastSyncError = nil
                }
            } catch {
                print("[PhoneSession] updateApplicationContext error: \(error.localizedDescription)")
                await MainActor.run {
                    lastSyncError = error.localizedDescription
                }
            }

            // Also send via message for immediate delivery when watch app is open
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(["contextUpdate": dict], replyHandler: nil) { error in
                    print("[PhoneSession] sendMessage error: \(error.localizedDescription)")
                }
            }

    }

    /// Lightweight update that only sends the snapshot to watch complications.
    /// Used during background wakes where the full context build is too heavy.
    /// Uses transferCurrentComplicationUserInfo for high-priority delivery.
    func sendSnapshotToWatch() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        sendSnapshotUpdate()
    }

    /// Sends only live-workout state after set/session mutations. This avoids
    /// rebuilding and retransmitting every saved plan after each logged set.
    func sendWorkoutUpdateToWatch() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled,
              let userId = authManager.currentUserId else { return }

        Task {
            let update = WatchWorkoutUpdate(
                userId: userId,
                activeSession: await buildActiveSession(),
                generatedAt: Date()
            )
            guard let data = try? JSONEncoder().encode(update),
                  var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            payload["stateType"] = "workout"
            payload["schemaVersion"] = 2

            for transfer in WCSession.default.outstandingUserInfoTransfers
            where transfer.userInfo["stateType"] as? String == "workout" {
                transfer.cancel()
            }
            WCSession.default.transferUserInfo(payload)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
        }
    }

    func sendSignedOutStateToWatch() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        let payload: [String: Any] = [
            "stateType": "signedOut",
            "schemaVersion": 2,
            "isPro": false,
            "entitlementVerifiedAt": Date().timeIntervalSince1970
        ]
        try? WCSession.default.updateApplicationContext(payload)
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func sendSnapshotUpdate() {
        guard let snap = WidgetSnapshot.read(),
              let snapData = try? JSONEncoder().encode(snap),
              var snapDict = try? JSONSerialization.jsonObject(with: snapData) as? [String: Any] else { return }
        // Read from App Group rather than the singleton — during background
        // wakes, verifyProEntitlement() has already written the fresh value
        // here but the singleton may not have been refreshed.
        let isPro = UserDefaults(suiteName: "group.com.zuhayrk.shift")?.bool(forKey: "isPro") ?? false
        snapDict["isPro"] = isPro
        let payload: [String: Any] = [
            "stateType": "snapshot",
            "schemaVersion": 2,
            "snapshot": snapDict,
            "isPro": isPro,
            "entitlementVerifiedAt":
                StoreEntitlementCache.read()?.verifiedAt.timeIntervalSince1970
                ?? Date().timeIntervalSince1970
        ]

        for transfer in WCSession.default.outstandingUserInfoTransfers
        where transfer.userInfo["stateType"] as? String == "snapshot" {
            transfer.cancel()
        }
        WCSession.default.transferUserInfo(payload)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        if WCSession.default.isComplicationEnabled,
           WCSession.default.remainingComplicationUserInfoTransfers > 0 {
            WCSession.default.transferCurrentComplicationUserInfo(payload)
        }
    }

    private func buildContext() async -> WatchContext {
        let userId = authManager.currentUserId ?? ""

        // Fall back to local profile cache when woken in the background by HealthKit
        let settings: UserSettings
        if let userSettings = authManager.user?.settings {
            settings = userSettings
        } else if !userId.isEmpty, let profile = try? await ProfileRepository.findById(userId) {
            settings = profile.settings
        } else {
            settings = .default
        }

        // Plans
        let plans: [WatchPlan] = await {
            guard let planList = try? await PlanService.listPlans() else { return [] }
            var result: [WatchPlan] = []
            for p in planList {
                guard let full = try? await PlanService.getPlanWithExercises(p.plan.id) else { continue }
                let exercises = full.exercises.map { e in
                    WatchPlanExercise(
                        id: e.planExercise.id,
                        exerciseId: e.exercise.id,
                        exerciseName: e.exercise.name,
                        equipment: e.exercise.equipment,
                        targetSets: e.planExercise.targetSets,
                        targetRepsMin: e.planExercise.targetRepsMin,
                        targetRepsMax: e.planExercise.targetRepsMax,
                        targetWeight: e.planExercise.targetWeight,
                        restSeconds: e.planExercise.restSeconds,
                        position: e.planExercise.position
                    )
                }
                result.append(WatchPlan(id: p.plan.id, name: p.plan.name, exercises: exercises))
            }
            return result
        }()

        // Recent exercises
        let recentExercises: [WatchExercise] = await {
            guard let ids = try? await ExerciseService.getRecentlyUsedExerciseIds(),
                  let exercises = try? await ExerciseService.getByIds(Array(ids.prefix(20))) else { return [] }
            return ids.prefix(20).compactMap { id in
                guard let ex = exercises[id] else { return nil }
                return WatchExercise(id: ex.id, name: ex.name, equipment: ex.equipment)
            }
        }()

        let activeSession = await buildActiveSession()

        // Last completed session today
        let lastCompleted: WatchCompletedSession? = await {
            guard let sessions = try? await WorkoutService.getCompletedSessions(for: Date()),
                  let last = sessions.last else { return nil }
            let setCount = last.exercises.reduce(0) { $0 + $1.setCount }
            let exercises = last.exercises.map { ex in
                WatchCompletedExercise(id: ex.id, name: ex.name, setCount: ex.setCount)
            }
            return WatchCompletedSession(
                sessionId: last.id,
                name: last.name,
                startedAt: last.startedAt,
                endedAt: last.endedAt ?? Date(),
                exerciseCount: last.exercises.count,
                setCount: setCount,
                exercises: exercises
            )
        }()

        // Snapshot data
        let snapshot = WidgetSnapshot.read()
        let snapshotData = WatchContext.WatchSnapshotData(
            workoutsThisWeek: snapshot?.workoutsThisWeek ?? 0,
            weeklyGoal: snapshot?.weeklyGoal,
            stepsToday: snapshot?.stepsToday ?? 0,
            stepGoal: snapshot?.stepGoal,
            workedOutToday: snapshot?.workedOutToday ?? false,
            currentStreak: snapshot?.currentStreak ?? 0,
            streakUnit: snapshot?.streakUnit ?? "days",
            updatedAt: snapshot?.updatedAt,
            weekStart: snapshot?.weekStart
        )

        return WatchContext(
            plans: plans,
            recentExercises: recentExercises,
            activeSession: activeSession,
            lastCompletedSession: lastCompleted,
            settings: WatchSettings(
                weightUnit: settings.weightUnit,
                defaultWeightIncrement: settings.defaultWeightIncrement,
                restTimerEnabled: settings.restTimer.enabled,
                restTimerDurationSeconds: settings.restTimer.durationSeconds
            ),
            userId: userId,
            snapshot: snapshotData,
            schemaVersion: 2,
            generatedAt: Date(),
            isSignedIn: !userId.isEmpty
        )
    }

    private func buildActiveSession() async -> WatchActiveSession? {
        guard let session = try? await WorkoutService.getLatestInProgress(),
              let exerciseIds = try? await WorkoutService.getSessionExerciseIds(session.id) else {
            return nil
        }
        let exerciseMap = (try? await ExerciseService.getByIds(exerciseIds)) ?? [:]
        var watchExercises: [WatchSessionExercise] = []
        for exerciseId in exerciseIds {
            let sets = (try? await WorkoutService.getSetsFor(
                sessionId: session.id,
                exerciseId: exerciseId
            )) ?? []
            let exercise = exerciseMap[exerciseId]
            watchExercises.append(
                WatchSessionExercise(
                    exerciseId: exerciseId,
                    exerciseName: exercise?.name ?? "Exercise",
                    equipment: exercise?.equipment,
                    completedSets: sets.filter(\.isCompleted).count,
                    totalSets: sets.count,
                    groupId: sets.first?.groupId
                )
            )
        }
        return WatchActiveSession(
            sessionId: session.id,
            planId: session.planId,
            name: session.name,
            startedAt: session.startedAt,
            exercises: watchExercises
        )
    }

    private func refreshWatchState(_ session: WCSession) {
        let paired = session.activationState == .activated && session.isPaired
        let installed = paired && session.isWatchAppInstalled
        let reachable = installed && session.isReachable
        Task { @MainActor in
            isWatchPaired = paired
            isWatchAppInstalled = installed
            isWatchReachable = reachable
        }
    }

    // MARK: - Handle Watch messages

    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let actionRaw = message["action"] as? String,
              let action = WatchAction(rawValue: actionRaw) else {
            replyHandler?(["error": "Unknown action"])
            return
        }

        Task { @MainActor in
            let actionId = action == .requestSync ? nil : message["actionId"] as? String
            if let actionId,
               !(await WatchActionLedger.shared.begin(actionId: actionId)) {
                replyHandler?(["duplicate": true])
                return
            }

            func respond(_ payload: [String: Any], succeeded: Bool) {
                replyHandler?(payload)
                if let actionId {
                    Task {
                        await WatchActionLedger.shared.finish(
                            actionId: actionId,
                            succeeded: succeeded
                        )
                    }
                }
            }

            switch action {
            case .startSession:
                let name = message["name"] as? String ?? "Workout"
                let requestedSessionId = message["sessionId"] as? String
                let startedAt = (message["startedAt"] as? String)
                    .flatMap { ISO8601DateFormatter.shared.date(from: $0) }
                    ?? Date()
                do {
                    let session = try await WorkoutService.createSession(
                        name: name,
                        startedAt: startedAt,
                        id: requestedSessionId
                    )
                    respond([
                        "success": true,
                        "sessionId": session.id,
                        "name": session.name,
                        "startedAt": ISO8601DateFormatter.shared.string(from: session.startedAt)
                    ], succeeded: true)
                    sendWorkoutUpdateToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .startSessionFromPlan:
                guard let planId = message["planId"] as? String else {
                    respond(["error": "Missing planId"], succeeded: false)
                    return
                }
                let requestedSessionId = message["sessionId"] as? String
                let startedAt = (message["startedAt"] as? String)
                    .flatMap { ISO8601DateFormatter.shared.date(from: $0) }
                    ?? Date()
                do {
                    let session = try await PlanService.createSessionFromPlan(
                        planId,
                        startedAt: startedAt,
                        sessionId: requestedSessionId
                    )
                    respond([
                        "success": true,
                        "sessionId": session.id,
                        "name": session.name,
                        "startedAt": ISO8601DateFormatter.shared.string(from: session.startedAt)
                    ], succeeded: true)
                    sendWorkoutUpdateToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .finishSession:
                guard let sessionId = message["sessionId"] as? String else {
                    respond(["error": "Missing sessionId"], succeeded: false)
                    return
                }
                do {
                    try await WorkoutService.finishSession(sessionId)
                    respond(["success": true], succeeded: true)
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .logSet:
                guard let sessionId = message["sessionId"] as? String,
                      let exerciseId = message["exerciseId"] as? String,
                      let reps = message["reps"] as? Int else {
                    respond(["error": "Missing required fields"], succeeded: false)
                    return
                }
                do {
                    let weight = message["weight"] as? Double
                    let setType = message["setType"] as? String
                    let newSet = try await WorkoutService.addSet(
                        sessionId: sessionId,
                        exerciseId: exerciseId,
                        reps: reps,
                        weight: weight,
                        setType: SetType(rawValue: setType ?? "normal")
                    )
                    respond(["success": true, "setId": newSet.id], succeeded: true)
                    sendWorkoutUpdateToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .addExercise:
                guard let sessionId = message["sessionId"] as? String,
                      let exerciseId = message["exerciseId"] as? String else {
                    respond(["error": "Missing required fields"], succeeded: false)
                    return
                }
                do {
                    try await WorkoutService.addExercisesToSession(sessionId, exerciseIds: [exerciseId])
                    respond(["success": true], succeeded: true)
                    sendWorkoutUpdateToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .deleteSession:
                guard let sessionId = message["sessionId"] as? String else {
                    respond(["error": "Missing sessionId"], succeeded: false)
                    return
                }
                do {
                    try await WorkoutService.deleteSession(sessionId)
                    respond(["success": true], succeeded: true)
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    respond(["error": error.localizedDescription], succeeded: false)
                }

            case .requestSync:
                sendContextToWatch(refreshEntitlement: true)
                respond(["success": true], succeeded: true)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refreshWatchState(session)
        Task { @MainActor in
            lastSyncError = error?.localizedDescription
        }
        if activationState == .activated {
            sendContextToWatch(refreshEntitlement: true)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        refreshWatchState(session)
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshWatchState(session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshWatchState(session)
        if session.activationState == .activated, session.isWatchAppInstalled {
            sendContextToWatch(refreshEntitlement: true)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleMessage(userInfo, replyHandler: nil)
    }
}
