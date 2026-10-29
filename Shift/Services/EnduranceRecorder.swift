import Foundation
import CoreLocation
import Observation

@MainActor @Observable
final class EnduranceRecorder: NSObject, CLLocationManagerDelegate {
    static let shared = EnduranceRecorder()
    private(set) var draft: EnduranceDraft?
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isPreparing = false
    private(set) var isSaving = false
    var errorMessage: String?
    var showRecorder = false
    var completedActivity: EnduranceActivity?
    var pendingCalendarSession: TrainingSession?
    var requestedSport: EnduranceSport = .run
    var requestedTrainingSessionID: String?
    var requestedSavedRouteID: String?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var checkpointTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var ownerID: String?
    @ObservationIgnored private var lastPersistedAt = Date.distantPast

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    var hasAccurateLocation: Bool {
        guard let location else { return false }
        return manager.accuracyAuthorization == .fullAccuracy
            && (0...50).contains(location.horizontalAccuracy)
            && abs(location.timestamp.timeIntervalSinceNow) < 20
    }

    func activate(userID: String?) async {
        guard ownerID != userID else { return }
        suspend()
        await persistenceTask?.value
        if let userID, (Task.isCancelled || authManager.currentUserId != userID) { return }
        ownerID = userID
        draft = nil
        location = nil
        guard let userID else { return }
        do {
            if var saved = try await EnduranceStore.shared.draft(userID: userID), saved.userId == userID {
                guard ownerID == userID, authManager.currentUserId == userID, !Task.isCancelled else { return }
                // A terminated app cannot establish what happened after its last
                // durable checkpoint. Recover paused, without inventing time.
                saved.pause(at: saved.checkpointAt)
                draft = saved
                try await EnduranceStore.shared.saveDraft(saved)
            }
        } catch { errorMessage = "Your saved recording could not be restored: \(error.localizedDescription)" }
    }

    func prepare(sport: EnduranceSport? = nil, trainingSessionID: String? = nil, savedRouteID: String? = nil) {
        if draft == nil { requestedTrainingSessionID = trainingSessionID; requestedSavedRouteID = savedRouteID }
        if let sport { requestedSport = sport }
        errorMessage = nil
        isPreparing = true
        if draft?.isPaused != false { manager.distanceFilter = kCLDistanceFilterNone }
        showRecorder = true
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: errorMessage = EnduranceError.locationDenied.localizedDescription
        }
    }

    func openPendingCalendarSession() {
        guard let item = pendingCalendarSession else { return }
        pendingCalendarSession = nil
        guard item.userId == authManager.currentUserId else { return }
        prepare(sport: item.sport, trainingSessionID: item.id, savedRouteID: item.routeID)
    }

    func stopPreview() {
        isPreparing = false
        if draft == nil || draft?.isPaused == true { manager.stopUpdatingLocation() }
    }

    func start(sport: EnduranceSport) async throws {
        guard draft == nil, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let userID = authManager.currentUserId, userID == ownerID else { throw EnduranceError.wrongAccount }
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { throw EnduranceError.locationDenied }
        guard hasAccurateLocation else { throw EnduranceError.waitingForGPS }
        let now = Date()
        var recording = EnduranceDraft(userId: userID, sport: sport, startedAt: now, resumedAt: now, checkpointAt: now)
        recording.trainingSessionID = requestedTrainingSessionID
        recording.savedRouteID = requestedSavedRouteID
        if recording.trainingSessionID == nil,
           let planned = try? await EnduranceStore.shared.all(TrainingSession.self, userID: userID),
           let completed = try? await EnduranceStore.shared.all(EnduranceActivity.self, userID: userID) {
            recording.trainingSessionID = TrainingLinkPolicy.candidate(sessions: planned, userID: userID, kind: .endurance,
                sport: sport, date: now, excluding: Set(completed.compactMap(\.trainingSessionID)))
        }
        // Do not begin recording until the initial recovery checkpoint exists.
        try await EnduranceStore.shared.saveDraft(recording)
        guard userID == ownerID, userID == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        draft = recording
        beginLocationUpdates()
        beginCheckpointing()
        await TrainingNotificationService.reconcile()
        PhoneSessionManager.shared.sendContextToWatch()
    }

    func pause() {
        guard draft != nil else { return }
        draft?.pause(at: Date())
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        checkpointTask?.cancel()
        persist()
    }

    func resume() throws {
        guard draft?.isPaused == true, draft?.userId == authManager.currentUserId else { return }
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { throw EnduranceError.locationDenied }
        guard manager.accuracyAuthorization == .fullAccuracy else { throw EnduranceError.locationDenied }
        errorMessage = nil
        draft?.resume(at: Date())
        beginLocationUpdates()
        beginCheckpointing()
        persist()
    }

    func suspend() {
        pause()
        manager.stopUpdatingLocation()
        isPreparing = false
        showRecorder = false
    }

    func prepareToLeaveAccount() async {
        suspend()
        await persistenceTask?.value
    }

    func finish(title: String, notes: String) async throws -> EnduranceActivity {
        guard !isSaving, let current = draft, current.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        isSaving = true
        defer { isSaving = false }
        pause()
        await persistenceTask?.value
        guard let paused = draft else { throw EnduranceError.invalidActivity }
        let activity = paused.finished(title: title, notes: notes, at: Date())
        try await EnduranceService.save(activity, finishingDraft: true)
        if draft?.id == activity.id && ownerID == activity.userId {
            draft = nil
            completedActivity = activity
            showRecorder = false
        }
        Task { await EnduranceService.refreshSummaries() }
        return activity
    }

    func discard() async throws {
        guard let current = draft, current.userId == authManager.currentUserId else { throw EnduranceError.wrongAccount }
        pause()
        await persistenceTask?.value
        try await EnduranceStore.shared.deleteDraft(userID: current.userId)
        draft = nil
        showRecorder = false
        await TrainingNotificationService.reconcile()
        PhoneSessionManager.shared.sendContextToWatch()
    }

    private func beginLocationUpdates() {
        manager.distanceFilter = 5
        manager.activityType = draft?.sport == .cycle ? .otherNavigation : .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func beginCheckpointing() {
        checkpointTask?.cancel()
        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.persist()
            }
        }
    }

    private func persist(force: Bool = true) {
        guard force || Date().timeIntervalSince(lastPersistedAt) >= 5 else { return }
        guard var snapshot = draft else { return }
        lastPersistedAt = Date()
        snapshot.checkpointAt = Date()
        draft?.checkpointAt = snapshot.checkpointAt
        let previous = persistenceTask
        persistenceTask = Task { [weak self] in
            await previous?.value
            do { try await EnduranceStore.shared.saveDraft(snapshot) }
            catch { self?.errorMessage = "The recording is in memory, but its recovery copy could not be saved. \(error.localizedDescription)" }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            errorMessage = manager.accuracyAuthorization == .fullAccuracy ? nil : EnduranceError.locationDenied.localizedDescription
            if isPreparing || draft?.isPaused == false { manager.startUpdatingLocation() }
        } else if authorization == .denied || authorization == .restricted {
            pause()
            errorMessage = EnduranceError.locationDenied.localizedDescription
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isPreparing || draft?.isPaused == false else { return }
        for sample in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            if sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 50,
               abs(sample.timestamp.timeIntervalSinceNow) < 20 {
                location = sample
                if errorMessage?.hasPrefix("GPS signal interrupted") == true { errorMessage = nil }
            }
            guard draft?.isPaused == false, draft?.userId == authManager.currentUserId else { continue }
            let point = EnduranceRoutePoint(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude,
                altitude: sample.altitude, timestamp: sample.timestamp.timeIntervalSince1970,
                horizontalAccuracy: sample.horizontalAccuracy, verticalAccuracy: sample.verticalAccuracy,
                activeSeconds: 0, segment: 0,
                speedMetersPerSecond: sample.speed >= 0 ? sample.speed : nil)
            if draft?.append(point, now: Date()) == true { persist(force: false) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            pause()
            errorMessage = EnduranceError.locationDenied.localizedDescription
        } else {
            errorMessage = "GPS signal interrupted. Recording time continues; route updates will resume when the signal returns."
        }
    }
}
