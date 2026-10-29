import Foundation
import Observation
import WatchKit
@preconcurrency import HealthKit
@preconcurrency import CoreLocation

@MainActor @Observable
final class WatchEnduranceRecorder: NSObject {
    static let shared = WatchEnduranceRecorder()
    private(set) var draft: EnduranceDraft?
    private(set) var location: CLLocation?
    private(set) var preparing = false
    private(set) var busy = false
    private(set) var heartRate: Double?
    private(set) var calories: Double?
    var error: String?
    var savedMessage: String?
    private(set) var lastSaved: EnduranceActivity?
    var selectedSport: EnduranceSport = .run
    var trainingSessionID: String?
    var savedRouteID: String?
    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var workout: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var checkpointTask: Task<Void, Never>?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast

    private override init() {
        super.init()
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }
    var ready: Bool {
        guard let location else { return false }
        return (0...50).contains(location.horizontalAccuracy) && abs(location.timestamp.timeIntervalSinceNow) < 20
            && manager.accuracyAuthorization == .fullAccuracy
    }
    private func key(_ owner: String) -> String { "shift.watch.endurance.draft.\(owner.lowercased())" }
    private func checkpoint() {
        guard var current = draft else { return }
        current.checkpointAt = Date(); draft = current; lastCheckpoint = Date()
        do { UserDefaults.standard.set(try JSONEncoder().encode(current), forKey: key(current.userId)) }
        catch { self.error = "Recovery checkpoint failed: \(error.localizedDescription)" }
    }
    #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
    func loadStoreCapture() {
        draft = .init(userId: StoreCaptureConfiguration.owner,sport:.run,startedAt:Date().addingTimeInterval(-1_324),accumulatedSeconds:1_324,checkpointAt:Date(),distanceMeters:3_420)
        heartRate = 148; calories = 256
    }
    #endif
    func prepare(sport: EnduranceSport, sessionID: String? = nil, routeID: String? = nil) async {
        guard draft == nil, WatchSessionManager.shared.canUseProFeatures else { return }
        guard WatchSessionManager.shared.context?.activeSession == nil,
              WatchSessionManager.shared.context?.endurance?.phoneRecording != true else {
            error = "Finish the recording already in progress before starting another."; return
        }
        selectedSport = sport; trainingSessionID = sessionID; savedRouteID = routeID
        savedMessage = nil; error = nil; preparing = true
        manager.requestWhenInUseAuthorization(); manager.startUpdatingLocation()
        guard HKHealthStore.isHealthDataAvailable() else { error = "Apple Health is unavailable."; return }
        do {
            let heart = HKQuantityType(.heartRate)
            let energy = HKQuantityType(.activeEnergyBurned)
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), energy, HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)],
                read: [heart, energy, HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)])
        } catch { self.error = error.localizedDescription }
    }
    func start() async {
        guard draft == nil, !busy, preparing, let owner = WatchSessionManager.shared.context?.userId,
              WatchSessionManager.shared.canUseProFeatures else { return }
        guard ready else { error = "Waiting for precise GPS. Move outdoors and allow precise location for Shift."; return }
        guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            error = "Allow Shift to save workouts in Apple Health to record on Watch in the background."; return
        }
        busy = true; defer { busy = false }
        let config = HKWorkoutConfiguration()
        config.activityType = selectedSport == .run ? .running : selectedSport == .walk ? .walking : .cycling
        config.locationType = .outdoor
        do {
            let native = try HKWorkoutSession(healthStore: health, configuration: config)
            let live = native.associatedWorkoutBuilder()
            configure(native, live: live)
            let now = Date()
            var current = EnduranceDraft(userId: owner, sport: selectedSport, startedAt: now, resumedAt: now, checkpointAt: now)
            current.trainingSessionID = trainingSessionID; current.savedRouteID = savedRouteID
            draft = current; checkpoint()
            try await live.addMetadata(["ShiftEnduranceId": current.id])
            native.startActivity(with: now)
            try await live.beginCollection(at: now)
            error = nil; manager.startUpdatingLocation(); startCheckpointing()
        } catch {
            workout?.end(); builder?.discardWorkout(); workout = nil; builder = nil; routeBuilder = nil
            if let owner = draft?.userId { UserDefaults.standard.removeObject(forKey: key(owner)) }; draft = nil
            self.error = error.localizedDescription
        }
    }
    private func configure(_ native: HKWorkoutSession, live: HKLiveWorkoutBuilder) {
        workout = native; builder = live
        native.delegate = self; live.delegate = self
        live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: native.workoutConfiguration)
        routeBuilder = live.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
    }
    func pause() {
        guard draft != nil else { return }
        if draft?.isPaused == false { draft?.pause(at: Date()) }
        workout?.pause(); manager.stopUpdatingLocation(); checkpointTask?.cancel(); checkpoint()
    }
    func resume() {
        guard let current = draft, current.isPaused, current.userId == WatchSessionManager.shared.context?.userId else { return }
        guard workout != nil else { error = "Save this recovered recording, then start a new activity."; return }
        guard manager.accuracyAuthorization == .fullAccuracy else { error = "Allow precise location for Shift to resume."; return }
        draft?.resume(at: Date()); workout?.resume(); manager.startUpdatingLocation(); startCheckpointing(); checkpoint()
    }
    func finish() async {
        guard let current = draft, !busy, current.userId == WatchSessionManager.shared.context?.userId else { return }
        busy = true; defer { busy = false }; pause()
        guard let paused = draft else { return }
        var activity = paused.finished(title: "\(paused.sport.title) · \(paused.startedAt.formatted(.dateTime.day().month()))", notes: "Recorded on Apple Watch", at: Date())
        do { try WatchEnduranceOutbox.save(activity) }
        catch { self.error = "Could not save on Watch. Your recording is kept. \(error.localizedDescription)"; return }
        var healthError: String?
        if let builder {
            workout?.end()
            await routeTask?.value
            do {
                try await builder.endCollection(at: Date())
                if let saved = try await builder.finishWorkout() {
                    activity.healthKitID = saved.uuid.uuidString.lowercased()
                    try WatchEnduranceOutbox.save(activity)
                    if let routeBuilder, !activity.route.isEmpty {
                        _ = try await routeBuilder.finishRoute(with: saved, metadata: ["ShiftEnduranceId": activity.id])
                    }
                }
            } catch { healthError = error.localizedDescription }
        }
        UserDefaults.standard.removeObject(forKey: key(activity.userId))
        draft = nil; workout = nil; builder = nil; routeBuilder = nil; preparing = false
        manager.stopUpdatingLocation(); heartRate = nil; calories = nil
        lastSaved = activity
        WKInterfaceDevice.current().play(.success)
        savedMessage = "Saved on Watch. Syncs to Shift when your iPhone is available."
        error = healthError.map { "Saved in Shift; Apple Health could not finish saving: \($0)" }
        WatchEnduranceOutbox.flush()
    }
    func discard() {
        guard !busy, let owner = draft?.userId, owner == WatchSessionManager.shared.context?.userId else { return }
        pause(); workout?.end(); builder?.discardWorkout()
        UserDefaults.standard.removeObject(forKey: key(owner))
        draft = nil; workout = nil; builder = nil; routeBuilder = nil; preparing = false
        manager.stopUpdatingLocation(); error = nil
    }
    func stopPreview() { if draft == nil { preparing = false; manager.stopUpdatingLocation() } }
    func accountChanged() {
        guard let current = draft, current.userId != WatchSessionManager.shared.context?.userId else { return }
        pause(); workout?.end(); builder?.discardWorkout(); draft = nil; workout = nil; builder = nil; routeBuilder = nil
        manager.stopUpdatingLocation(); preparing = false; heartRate = nil; calories = nil; error = nil; savedMessage = nil; lastSaved = nil
    }
    func removeDeletedAccount(_ owner: String) {
        guard UUID(uuidString: owner) != nil else { return }
        if draft?.userId == owner {
            pause(); workout?.end(); builder?.discardWorkout()
            draft = nil; workout = nil; builder = nil; routeBuilder = nil
            manager.stopUpdatingLocation(); preparing = false
        }
        if lastSaved?.userId == owner { lastSaved = nil; savedMessage = nil }
        UserDefaults.standard.removeObject(forKey: key(owner))
        WatchEnduranceOutbox.removeDeletedAccount(owner)
    }
    func recover() async {
        guard draft == nil, let owner = WatchSessionManager.shared.context?.userId,
              let data = UserDefaults.standard.data(forKey: key(owner)),
              var saved = try? JSONDecoder().decode(EnduranceDraft.self, from: data), saved.userId == owner else { WatchEnduranceOutbox.flush(); return }
        saved.pause(at: saved.checkpointAt); draft = saved; selectedSport = saved.sport
        do {
            if let native = try await health.recoverActiveWorkoutSession() { configure(native, live: native.associatedWorkoutBuilder()); native.pause() }
        } catch { self.error = "Recovered your saved recording in a paused state." }
        checkpoint(); WatchEnduranceOutbox.flush()
    }
    private func startCheckpointing() {
        checkpointTask?.cancel()
        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5)); guard !Task.isCancelled else { return }; self?.checkpoint()
            }
        }
    }
}

extension WatchEnduranceRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.preparing || self.draft?.isPaused == false else { return }
            var accepted: [CLLocation] = []
            for sample in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                if sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 50, abs(sample.timestamp.timeIntervalSinceNow) < 20 { self.location = sample }
                guard self.draft?.isPaused == false, self.draft?.userId == WatchSessionManager.shared.context?.userId else { continue }
                let point = EnduranceRoutePoint(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude,
                    altitude: sample.altitude, timestamp: sample.timestamp.timeIntervalSince1970, horizontalAccuracy: sample.horizontalAccuracy,
                    verticalAccuracy: sample.verticalAccuracy, activeSeconds: 0, segment: 0, speedMetersPerSecond: sample.speed >= 0 ? sample.speed : nil)
                if self.draft?.append(point, now: Date()) == true { accepted.append(sample) }
            }
            if !accepted.isEmpty, let route = self.routeBuilder {
                let previous = self.routeTask
                self.routeTask = Task { @MainActor in
                    await previous?.value
                    do { try await route.insertRouteData(accepted) } catch { self.error = "The Shift route is kept, but Apple Health route saving failed: \(error.localizedDescription)" }
                }
            }
            if Date().timeIntervalSince(self.lastCheckpoint) >= 5 { self.checkpoint() }
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { self.pause(); self.error = "Allow precise location for Shift in Watch settings to record routes." }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.error = "GPS interrupted. Time continues; route points resume when the signal returns." }
    }
}
extension WatchEnduranceRecorder: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .paused, self.draft?.isPaused == false { self.draft?.pause(at: date); self.manager.stopUpdatingLocation(); self.checkpoint() }
            else if toState == .running, self.draft?.isPaused == true { self.draft?.resume(at: date); self.manager.startUpdatingLocation(); self.startCheckpointing() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.pause(); self.error = error.localizedDescription }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self.calories = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
    }
}
