import Foundation

struct RecoveryHealthMetrics: Equatable {
    var sleepHours: Double?
    var hrvMilliseconds: Double?
    var hrvBaselineMilliseconds: Double?
    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?

    init(
        sleepHours: Double? = nil,
        hrvMilliseconds: Double? = nil,
        hrvBaselineMilliseconds: Double? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil
    ) {
        self.sleepHours = sleepHours
        self.hrvMilliseconds = hrvMilliseconds
        self.hrvBaselineMilliseconds = hrvBaselineMilliseconds
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
    }
}

enum RecoveryRecommendation: String {
    case checkIn = "Add a quick check-in"
    case train = "Train as planned"
    case adjust = "Consider an easier session"
    case recover = "Recovery may be the better choice"

    var symbol: String {
        switch self {
        case .checkIn: return "waveform.path.ecg"
        case .train: return "bolt.heart.fill"
        case .adjust: return "gauge.with.dots.needle.33percent"
        case .recover: return "bed.double.fill"
        }
    }
}

struct RecoverySnapshot: Equatable {
    let recommendation: RecoveryRecommendation
    let reasons: [String]
    let metrics: RecoveryHealthMetrics
    let checkIn: Int?
}

enum RecoveryCheckInStore {
    private static let suite = UserDefaults(suiteName: "group.com.zuhayrk.shift")
    private static let prefix = "recovery-check-in."

    static func value(for date: Date = Date()) -> Int? {
        let value = suite?.integer(forKey: prefix + TrainingScheduleSettings.dateKey(date)) ?? 0
        return value == 0 ? nil : value
    }

    static func save(_ value: Int, for date: Date = Date()) {
        suite?.set(min(max(value, 1), 5), forKey: prefix + TrainingScheduleSettings.dateKey(date))
    }
}

enum RecoveryGuidanceService {
    static func load() async -> RecoverySnapshot {
        makeSnapshot(
            metrics: await HealthKitService.fetchRecoveryMetrics(),
            checkIn: RecoveryCheckInStore.value()
        )
    }

    static func makeSnapshot(
        metrics: RecoveryHealthMetrics,
        checkIn: Int?
    ) -> RecoverySnapshot {
        var concerns = 0
        var reasons: [String] = []

        if let sleep = metrics.sleepHours {
            if sleep < 6 {
                concerns += 2
                reasons.append("Short sleep")
            } else if sleep < 7 {
                concerns += 1
                reasons.append("Sleep was below 7 hours")
            } else {
                reasons.append(String(format: "%.1f hours sleep", sleep))
            }
        }
        if let hrv = metrics.hrvMilliseconds,
           let baseline = metrics.hrvBaselineMilliseconds,
           baseline > 0,
           hrv < baseline * 0.8 {
            concerns += 1
            reasons.append("HRV is below your recent range")
        }
        if let resting = metrics.restingHeartRate,
           let baseline = metrics.restingHeartRateBaseline,
           baseline > 0,
           resting > baseline * 1.1 {
            concerns += 1
            reasons.append("Resting heart rate is above your recent range")
        }
        if let checkIn {
            if checkIn <= 2 {
                concerns += 2
                reasons.append("You reported feeling run down")
            } else if checkIn == 3 {
                concerns += 1
                reasons.append("You reported feeling average")
            } else {
                reasons.append("You reported feeling good")
            }
        }

        let recommendation: RecoveryRecommendation
        if reasons.isEmpty {
            recommendation = .checkIn
            reasons = ["No recovery signals are available yet"]
        } else if concerns >= 3 {
            recommendation = .recover
        } else if concerns >= 1 {
            recommendation = .adjust
        } else {
            recommendation = .train
        }
        return RecoverySnapshot(
            recommendation: recommendation,
            reasons: Array(reasons.prefix(3)),
            metrics: metrics,
            checkIn: checkIn
        )
    }
}
