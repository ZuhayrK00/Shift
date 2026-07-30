import Foundation
import HealthKit

private final class HealthObserverRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var observedTypes: Set<String> = []

    func beginObserving(_ identifier: String) -> Bool {
        lock.withLock {
            guard !observedTypes.contains(identifier) else { return false }
            observedTypes.insert(identifier)
            return true
        }
    }
}

// MARK: - ActivityData

struct ActivityData {
    var moveCalories: Double = 0     // active energy burned (kcal)
    var moveGoal: Double = 0
    var exerciseMinutes: Double = 0
    var exerciseGoal: Double = 0     // typically 30
    var standHours: Double = 0
    var standGoal: Double = 0        // typically 12
    var steps: Int = 0
    var distanceKm: Double = 0       // walking + running distance
}

// MARK: - HealthKitService

struct HealthKitService {

    private static let store = HKHealthStore()

    private static let workoutType = HKObjectType.workoutType()
    private static let bodyMassType = HKQuantityType(.bodyMass)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let exerciseTimeType = HKQuantityType(.appleExerciseTime)
    private static let standTimeType = HKQuantityType(.appleStandTime)
    private static let stepCountType = HKQuantityType(.stepCount)
    private static let distanceType = HKQuantityType(.distanceWalkingRunning)
    private static let heartRateType = HKQuantityType(.heartRate)
    private static let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private static let heartRateVariabilityType = HKQuantityType(.heartRateVariabilitySDNN)
    private static let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private static let observerRegistry = HealthObserverRegistry()

    // MARK: - Availability

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    static func requestAuthorization(
        settings: HealthKitSettings,
        stepGoalTracking: Bool
    ) async throws {
        guard isAvailable else { return }

        var readTypes: Set<HKObjectType> = []
        var writeTypes: Set<HKSampleType> = []

        if settings.syncWorkouts {
            writeTypes.insert(workoutType)
            readTypes.formUnion([activeEnergyType, heartRateType])
        }
        if settings.syncBodyWeight {
            readTypes.insert(bodyMassType)
            writeTypes.insert(bodyMassType)
        }
        if settings.countExternalWorkouts {
            readTypes.insert(workoutType)
        }
        if settings.recoveryGuidance {
            readTypes.formUnion([
                sleepType, restingHeartRateType, heartRateVariabilityType
            ])
        }
        if settings.showDailyActivity {
            readTypes.formUnion([
                activeEnergyType, exerciseTimeType, standTimeType,
                stepCountType, distanceType, HKObjectType.activitySummaryType()
            ])
        }
        if stepGoalTracking {
            readTypes.insert(stepCountType)
        }

        guard !readTypes.isEmpty || !writeTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        configureBackgroundDelivery(
            settings: settings,
            stepGoalTracking: stepGoalTracking
        )
    }

    // MARK: - Background delivery

    /// Installs event observers as early as possible during launch. HealthKit can
    /// wake the app for matching saves/deletes, subject to system frequency caps
    /// (step count is capped at hourly on iPhone even when `.immediate` is used).
    static func configureBackgroundDelivery(
        settings: HealthKitSettings,
        stepGoalTracking: Bool
    ) {
        guard isAvailable else { return }

        if stepGoalTracking,
           observerRegistry.beginObserving(HKQuantityTypeIdentifier.stepCount.rawValue) {
            let query = HKObserverQuery(
                sampleType: stepCountType,
                predicate: nil
            ) { _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task {
                    // Complete the essential event check first, acknowledge
                    // HealthKit promptly, then perform nonessential refreshes.
                    await GoalNotificationService.handleStepCountChange()
                    completionHandler()
                    await WidgetDataService.updateSnapshot()
                    PhoneSessionManager.shared.sendSnapshotToWatch()
                }
            }
            store.execute(query)
        }

        if settings.countExternalWorkouts,
           observerRegistry.beginObserving(workoutType.identifier) {
            let query = HKObserverQuery(
                sampleType: workoutType,
                predicate: nil
            ) { _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task {
                    await GoalNotificationService.notifyFrequencyGoalIfReached()
                    completionHandler()
                    await WidgetDataService.updateSnapshot()
                    PhoneSessionManager.shared.sendSnapshotToWatch()
                }
            }
            store.execute(query)
        }

        if stepGoalTracking {
            enableBackgroundDelivery(for: stepCountType, label: "step count")
        }
        if settings.countExternalWorkouts {
            enableBackgroundDelivery(for: workoutType, label: "workouts")
        }
    }

    private static func enableBackgroundDelivery(for type: HKObjectType, label: String) {
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
            if let error {
                print("[HealthKit] Failed to enable \(label) background delivery: \(error.localizedDescription)")
            } else if !success {
                print("[HealthKit] \(label) background delivery was not enabled.")
            }
        }
    }

    // MARK: - Save workout

    /// Writes a completed workout session to HealthKit as a strength training workout.
    /// Attaches "ShiftSessionId" metadata so we can identify Shift-originated workouts later.
    static func saveWorkout(
        session: WorkoutSession,
        exerciseNames: [String: String]
    ) async throws {
        guard isAvailable else { return }

        let startDate = session.startedAt
        let endDate = session.endedAt ?? Date()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await builder.beginCollection(at: startDate)

        let metadata: [String: Any] = [
            "ShiftSessionId": session.id,
            HKMetadataKeyWorkoutBrandName: "Shift"
        ]

        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: endDate)
        try await builder.finishWorkout()
    }

    // MARK: - Body weight

    /// Reads the most recent body mass sample from HealthKit.
    /// Returns weight in **kg**, or nil if unavailable.
    static func readLatestBodyWeight() async -> Double? {
        guard isAvailable else { return nil }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                let kg = sample?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    /// Writes a body mass sample to HealthKit.
    /// - Parameter weightKg: Weight in kilograms.
    static func writeBodyWeight(_ weightKg: Double, date: Date = Date()) async throws {
        guard isAvailable else { return }

        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg)
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: date,
            end: date
        )
        try await store.save(sample)
    }

    // MARK: - External workouts

    /// Counts strength training workouts in HealthKit since a given date
    /// that were NOT logged by Shift (no "ShiftSessionId" metadata).
    static func countExternalWorkouts(since startDate: Date) async -> Int {
        guard isAvailable else { return 0 }

        let workoutPredicate = HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, datePredicate])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let external = workouts.filter { workout in
                    workout.metadata?["ShiftSessionId"] == nil
                }
                continuation.resume(returning: external.count)
            }
            store.execute(query)
        }
    }

    // MARK: - Session stats (calories + heart rate)

    /// Returns total active energy burned (kcal) during a time range.
    static func fetchCalories(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    /// Returns average heart rate (bpm) during a time range, or nil if no samples exist.
    static func fetchAverageHeartRate(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                let bpm = result?.averageQuantity()?.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                )
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: - Recovery signals

    static func fetchRecoveryMetrics() async -> RecoveryHealthMetrics {
        guard isAvailable else { return .init() }
        let now = Date()
        let baselineStart = Calendar.current.date(byAdding: .day, value: -28, to: now)
            ?? now.addingTimeInterval(-28 * 86_400)

        async let sleep = fetchSleepHours(endingAt: now)
        async let hrvLatest = fetchLatestQuantity(
            heartRateVariabilityType,
            unit: .secondUnit(with: .milli),
            since: baselineStart
        )
        async let hrvBaseline = fetchAverageQuantity(
            heartRateVariabilityType,
            unit: .secondUnit(with: .milli),
            since: baselineStart
        )
        async let restingLatest = fetchLatestQuantity(
            restingHeartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            since: baselineStart
        )
        async let restingBaseline = fetchAverageQuantity(
            restingHeartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            since: baselineStart
        )

        return await RecoveryHealthMetrics(
            sleepHours: sleep,
            hrvMilliseconds: hrvLatest,
            hrvBaselineMilliseconds: hrvBaseline,
            restingHeartRate: restingLatest,
            restingHeartRateBaseline: restingBaseline
        )
    }

    private static func fetchSleepHours(endingAt end: Date) async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: end)
            ?? end.addingTimeInterval(-18 * 3_600)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictEndDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let intervals = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .sorted { $0.startDate < $1.startDate }
                guard !intervals.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Merge overlaps from multiple sleep sources rather than double-counting.
                var total: TimeInterval = 0
                var rangeStart = intervals[0].startDate
                var rangeEnd = intervals[0].endDate
                for sample in intervals.dropFirst() {
                    if sample.startDate <= rangeEnd {
                        rangeEnd = max(rangeEnd, sample.endDate)
                    } else {
                        total += rangeEnd.timeIntervalSince(rangeStart)
                        rangeStart = sample.startDate
                        rangeEnd = sample.endDate
                    }
                }
                total += rangeEnd.timeIntervalSince(rangeStart)
                continuation.resume(returning: total / 3_600)
            }
            store.execute(query)
        }
    }

    private static func fetchLatestQuantity(
        _ type: HKQuantityType,
        unit: HKUnit,
        since start: Date
    ) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private static func fetchAverageQuantity(
        _ type: HKQuantityType,
        unit: HKUnit,
        since start: Date
    ) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                continuation.resume(
                    returning: result?.averageQuantity()?.doubleValue(for: unit)
                )
            }
            store.execute(query)
        }
    }

    // MARK: - Activity data (rings + steps + distance)

    /// Fetches today's activity ring data, step count, and distance.
    static func fetchTodayActivity() async -> ActivityData? {
        await fetchActivity(for: Date())
    }

    /// Fetches activity ring data, step count, and distance for a given date.
    static func fetchActivity(for date: Date) async -> ActivityData? {
        guard isAvailable else { return nil }

        async let summaryData = fetchActivitySummary(for: date)
        async let stepsData = fetchSteps(for: date)
        async let distanceData = fetchDistance(for: date)

        var activity = await summaryData ?? ActivityData()
        activity.steps = await stepsData
        activity.distanceKm = await distanceData
        return activity
    }

    /// Reads activity summary (rings) for a given date.
    private static func fetchActivitySummary(for date: Date) async -> ActivityData? {
        let cal = Calendar.current
        var dateComponents = cal.dateComponents([.year, .month, .day, .era], from: date)
        dateComponents.calendar = cal

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let data = ActivityData(
                    moveCalories: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count()),
                    standGoal: summary.appleStandHoursGoal.doubleValue(for: .count()),
                    steps: 0
                )
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    /// Public accessor for today's step count (used by WidgetDataService).
    static func fetchStepsForWidget() async -> Int {
        guard isAvailable else { return 0 }
        return await fetchSteps(for: Date())
    }

    /// Reads total step count for a given date.
    static func fetchSteps(for date: Date) async -> Int {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            store.execute(query)
        }
    }

    /// Reads walking + running distance for a given date (in km).
    private static func fetchDistance(for date: Date) async -> Double {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let km = result?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
                continuation.resume(returning: km)
            }
            store.execute(query)
        }
    }
}
