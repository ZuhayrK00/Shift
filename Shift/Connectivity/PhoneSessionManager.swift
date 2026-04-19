import Foundation
import WatchConnectivity

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

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send context to Watch

    func sendContextToWatch() {
        guard WCSession.default.activationState == .activated else { return }

        Task {
            // Ensure snapshot is fresh before sending to watch
            await WidgetDataService.updateSnapshot()
            let context = await buildContext()
            guard let data = try? JSONEncoder().encode(context),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[PhoneSession] Failed to encode context")
                return
            }

            do {
                try WCSession.default.updateApplicationContext(dict)
            } catch {
                print("[PhoneSession] updateApplicationContext error: \(error.localizedDescription)")
            }

            // Also send via message for immediate delivery when watch app is open
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(["contextUpdate": dict], replyHandler: nil) { error in
                    print("[PhoneSession] sendMessage error: \(error.localizedDescription)")
                }
            }

            sendComplicationUpdate()
        }
    }

    /// Lightweight update that only sends the snapshot to watch complications.
    /// Used during background wakes where the full context build is too heavy.
    /// Uses transferCurrentComplicationUserInfo for high-priority delivery.
    func sendSnapshotToWatch() {
        guard WCSession.default.activationState == .activated else { return }
        sendComplicationUpdate()
    }

    private func sendComplicationUpdate() {
        guard WCSession.default.isComplicationEnabled else { return }
        guard let snap = WidgetSnapshot.read(),
              let snapData = try? JSONEncoder().encode(snap),
              let snapDict = try? JSONSerialization.jsonObject(with: snapData) as? [String: Any] else { return }
        WCSession.default.transferCurrentComplicationUserInfo(["snapshot": snapDict])
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

        // Active session
        let activeSession: WatchActiveSession? = await {
            guard let session = try? await WorkoutService.getLatestInProgress() else { return nil }
            guard let exerciseIds = try? await WorkoutService.getSessionExerciseIds(session.id) else { return nil }
            let exerciseMap = (try? await ExerciseService.getByIds(exerciseIds)) ?? [:]

            var watchExercises: [WatchSessionExercise] = []
            for eid in exerciseIds {
                let sets = (try? await WorkoutService.getSetsFor(sessionId: session.id, exerciseId: eid)) ?? []
                let exercise = exerciseMap[eid]
                watchExercises.append(WatchSessionExercise(
                    exerciseId: eid,
                    exerciseName: exercise?.name ?? "Exercise",
                    equipment: exercise?.equipment,
                    completedSets: sets.filter { $0.isCompleted }.count,
                    totalSets: sets.count,
                    groupId: sets.first?.groupId
                ))
            }

            return WatchActiveSession(
                sessionId: session.id,
                planId: session.planId,
                name: session.name,
                startedAt: session.startedAt,
                exercises: watchExercises
            )
        }()

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
            streakUnit: snapshot?.streakUnit ?? "days"
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
            snapshot: snapshotData
        )
    }

    // MARK: - Handle Watch messages

    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let actionRaw = message["action"] as? String,
              let action = WatchAction(rawValue: actionRaw) else {
            replyHandler?(["error": "Unknown action"])
            return
        }

        Task { @MainActor in
            switch action {
            case .startSession:
                let name = message["name"] as? String ?? "Workout"
                do {
                    let session = try await WorkoutService.createSession(name: name)
                    replyHandler?(["sessionId": session.id, "name": session.name,
                                   "startedAt": ISO8601DateFormatter.shared.string(from: session.startedAt)])
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .startSessionFromPlan:
                guard let planId = message["planId"] as? String else {
                    replyHandler?(["error": "Missing planId"])
                    return
                }
                do {
                    let session = try await PlanService.createSessionFromPlan(planId)
                    replyHandler?(["sessionId": session.id, "name": session.name,
                                   "startedAt": ISO8601DateFormatter.shared.string(from: session.startedAt)])
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .finishSession:
                guard let sessionId = message["sessionId"] as? String else {
                    replyHandler?(["error": "Missing sessionId"])
                    return
                }
                do {
                    try await WorkoutService.finishSession(sessionId)
                    replyHandler?(["success": true])
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .logSet:
                guard let sessionId = message["sessionId"] as? String,
                      let exerciseId = message["exerciseId"] as? String,
                      let reps = message["reps"] as? Int else {
                    replyHandler?(["error": "Missing required fields"])
                    return
                }
                do {
                    let newSet = try await WorkoutService.addSet(sessionId: sessionId, exerciseId: exerciseId)
                    let weight = message["weight"] as? Double
                    let setType = message["setType"] as? String
                    try await WorkoutService.updateSet(newSet.id, patch: SetPatch(
                        reps: reps,
                        weight: weight,
                        isCompleted: true,
                        setType: SetType(rawValue: setType ?? "normal")
                    ))
                    replyHandler?(["success": true, "setId": newSet.id])
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .addExercise:
                guard let sessionId = message["sessionId"] as? String,
                      let exerciseId = message["exerciseId"] as? String else {
                    replyHandler?(["error": "Missing required fields"])
                    return
                }
                do {
                    try await WorkoutService.addExercisesToSession(sessionId, exerciseIds: [exerciseId])
                    replyHandler?(["success": true])
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .deleteSession:
                guard let sessionId = message["sessionId"] as? String else {
                    replyHandler?(["error": "Missing sessionId"])
                    return
                }
                do {
                    try await WorkoutService.deleteSession(sessionId)
                    replyHandler?(["success": true])
                    sendContextToWatch()
                    NotificationCenter.default.post(name: .watchDidUpdateWorkout, object: nil)
                } catch {
                    replyHandler?(["error": error.localizedDescription])
                }

            case .requestSync:
                sendContextToWatch()
                replyHandler?(["success": true])
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            sendContextToWatch()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
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
