import Foundation
import HealthKit

/// Lightweight HealthKit service for the watch app.
/// Reads step count directly so the watch doesn't depend on the phone for steps.
struct WatchHealthKitService {
    private static let store = HKHealthStore()
    private static let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorization() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [stepType])
    }

    static func fetchStepsToday() async -> Int {
        guard isAvailable else { return 0 }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            store.execute(query)
        }
    }
}
