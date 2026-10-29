import Foundation
import HealthKit
import CoreLocation

/// Import is explicitly initiated by the user. Route access is a separate opt-in.
@MainActor
enum EnduranceHealthService {
    private static let health = HKHealthStore()
    private static var importing = false
    private enum ImportError: LocalizedError {
        case alreadyRunning
        var errorDescription: String? { "An Apple Health import is already running. Wait for it to finish before starting another." }
    }

    static func importActivities(includeRoutes: Bool, range: EnduranceImportRange = .allHistory, progress: @escaping (Int, Int) -> Void) async throws -> EnduranceImportReport {
        guard HKHealthStore.isHealthDataAvailable() else { throw EnduranceError.unavailable }
        guard !importing else { throw ImportError.alreadyRunning }
        let userID = try authManager.requireUserId()
        importing = true
        defer {
            importing = false
            Task { if authManager.currentUserId == userID { await finishImport() } }
        }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if includeRoutes { read.insert(HKSeriesType.workoutRoute()) }
        try await health.requestAuthorization(toShare: [], read: read)
        let workouts = try await workouts(since: range.startDate())
        let existing = try await EnduranceStore.shared.all(EnduranceActivity.self, userID: userID)
        let existingByHealthID = Dictionary(existing.compactMap { activity -> (String, EnduranceActivity)? in
            guard let id = activity.healthKitID else { return nil }
            return (id.lowercased(), activity)
        }, uniquingKeysWith: { first, second in first.route.count >= second.route.count ? first : second })
        var report = EnduranceImportReport(previouslyImportedCount: existingByHealthID.count, range: range)
        for (index, workout) in workouts.enumerated() {
            try Task.checkCancellation()
            guard userID == authManager.currentUserId else { throw EnduranceError.wrongAccount }
            progress(index + 1, workouts.count)
            guard let sport = sport(for: workout.workoutActivityType) else { continue }
            guard workout.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier,
                  workout.metadata?["ShiftSessionId"] == nil,
                  workout.metadata?["ShiftEnduranceId"] == nil else { report.shiftWorkoutCount += 1; continue }
            report.foundCount += 1
            switch sport { case .walk: report.walkCount += 1; case .run: report.runCount += 1; case .cycle: report.cycleCount += 1 }
            let healthKitID = workout.uuid.uuidString.lowercased()
            let id = EnduranceIdentity.importedID(workoutID: healthKitID, userID: userID)
            let previous = existingByHealthID[healthKitID]
            if previous != nil && (!includeRoutes || previous?.route.isEmpty == false) {
                report.alreadyImportedCount += 1
                continue
            }
            var coordinates: [CLLocation] = []
            if includeRoutes {
                do { coordinates = try await locations(for: workout) }
                catch is CancellationError { throw CancellationError() }
                catch { report.routeFailureCount += 1 }
            }
            let elapsed = max(0, workout.endDate.timeIntervalSince(workout.startDate))
            let active = min(elapsed, max(0, workout.duration))
            let ratio = elapsed > 0 ? active / elapsed : 0
            var segment = 0
            var points: [EnduranceRoutePoint] = []
            for location in coordinates.sorted(by: { $0.timestamp < $1.timestamp }) {
                if let last = points.last, location.timestamp.timeIntervalSince1970 - last.timestamp > 30 { segment += 1 }
                let point = EnduranceRoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    altitude: location.altitude, timestamp: location.timestamp.timeIntervalSince1970,
                    horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy,
                    activeSeconds: max(0, location.timestamp.timeIntervalSince(workout.startDate) * ratio), segment: segment)
                if point.isValid { points.append(point) }
            }
            if includeRoutes && points.isEmpty { report.unavailableRouteCount += 1 }
            if previous != nil && points.isEmpty {
                // A route query that returns nothing is not an update. Preserve
                // the saved activity and explain the missing map to the user.
                report.alreadyImportedCount += 1
                continue
            }
            let meters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            var activity = previous ?? EnduranceActivity(id: id, userId: userID, sport: sport,
                title: "\(workout.workoutActivityType == .hiking ? "Hike" : sport.title) · Apple Health", startedAt: workout.startDate, endedAt: workout.endDate,
                activeSeconds: active, distanceMeters: max(0, meters), source: "healthkit", healthKitID: healthKitID)
            activity.route = points
            if let gain = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                activity.elevationGainMeters = max(0, gain.doubleValue(for: .meter()))
            }
            guard activity.isValid else { report.invalidWorkoutCount += 1; continue }
            try Task.checkCancellation()
            // Health imports don't infer calendar completion or trigger per-row
            // reminder/widget reloads. Save durably, then refresh once at the end.
            guard userID == authManager.currentUserId else { throw EnduranceError.wrongAccount }
            try await EnduranceStore.shared.save(activity)
            if previous == nil { report.importedCount += 1 }
            else { report.updatedRouteCount += 1 }
        }
        return report
    }

    private static func sport(for type: HKWorkoutActivityType) -> EnduranceSport? {
        switch type { case .running: return .run; case .walking, .hiking: return .walk; case .cycling: return .cycle; default: return nil }
    }

    private static func workouts(since date: Date?) async throws -> [HKWorkout] {
        let sports = [HKWorkoutActivityType.running, .walking, .hiking, .cycling].map { HKQuery.predicateForWorkouts(with: $0) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: sports),
            HKQuery.predicateForSamples(withStart: date, end: Date(), options: [.strictStartDate, .strictEndDate])
        ])
        // nil limit means all matching workouts. Async descriptors propagate
        // cancellation to HealthKit rather than leaving callback queries running.
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)], limit: nil)
        return try await query.result(for: health)
    }
    private static func finishImport() async {
        SyncService.flushInBackground()
        await TrainingNotificationService.reconcile()
        await EnduranceService.refreshSummaries()
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
    }
    private static func locations(for workout: HKWorkout) async throws -> [CLLocation] {
        let query = HKSampleQueryDescriptor(predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [], limit: nil)
        let routes = try await query.result(for: health)
        var locations: [CLLocation] = []
        for route in routes {
            try Task.checkCancellation()
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: health) {
                try Task.checkCancellation()
                locations.append(location)
            }
        }
        return locations
    }
}
