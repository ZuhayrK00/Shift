import Foundation
import HealthKit

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

    private static let readTypes: Set<HKObjectType> = [
        workoutType, bodyMassType,
        activeEnergyType, exerciseTimeType, standTimeType, stepCountType, distanceType,
        heartRateType,
        HKObjectType.activitySummaryType()
    ]
    private static let writeTypes: Set<HKSampleType> = [workoutType, bodyMassType]

    // MARK: - Availability

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    static func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    // MARK: - Background delivery

    /// Sets up a HealthKit observer query for step count and enables background delivery.
    /// When steps update (even while app is closed), iOS wakes the app briefly to run the handler.
    /// Call once at app launch.
    static func enableStepCountBackgroundDelivery() {
        guard isAvailable else { return }

        let query = HKObserverQuery(sampleType: stepCountType, predicate: nil) { _, completionHandler, _ in
            // HealthKit woke us — update widgets and check if step goal is hit
            Task {
                await WidgetDataService.updateSnapshot()
                await GoalNotificationService.checkAndNotifyGoalCompletion()
                completionHandler()
            }
        }
        store.execute(query)

        store.enableBackgroundDelivery(for: stepCountType, frequency: .hourly) { _, _ in }
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

        guard var activity = await summaryData else { return nil }
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
    private static func fetchSteps(for date: Date) async -> Int {
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
