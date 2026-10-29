import Foundation
import CryptoKit

enum EnduranceIdentity {
    /// A HealthKit workout can be imported by different Shift accounts on one
    /// device. Scope its deterministic primary key to the owning account.
    static func importedID(workoutID: String, userID: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("\(userID.lowercased())/\(workoutID.lowercased())".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // RFC 9562 custom UUID (version 8)
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
    }
}

enum TrainingMode: String, CaseIterable {
    case strength, endurance
    var title: String { rawValue.capitalized }
}

enum EnduranceSport: String, Codable, CaseIterable, Identifiable, Sendable {
    case run, walk, cycle
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .run: return "figure.run"; case .walk: return "figure.walk"; case .cycle: return "figure.outdoor.cycle" }
    }
    var maximumSpeed: Double {
        switch self { case .walk: return 5; case .run: return 13; case .cycle: return 45 }
    }
}

/// Raw GPS coordinates belong to the account owner and are never publicly shared.
struct EnduranceRoutePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: TimeInterval
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var activeSeconds: Double
    var segment: Int
    var speedMetersPerSecond: Double? = nil

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && altitude.isFinite && timestamp.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && horizontalAccuracy.isFinite && (0...50).contains(horizontalAccuracy) && verticalAccuracy.isFinite
            && activeSeconds.isFinite && activeSeconds >= 0
    }

    func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let lat = (other.latitude - latitude) * radians
        let lon = (other.longitude - longitude) * radians
        let a = pow(sin(lat / 2), 2) + cos(latitude * radians)
            * cos(other.latitude * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(max(0, a)), sqrt(max(0, 1 - a)))
    }
}

struct EnduranceSplit: Codable, Hashable, Sendable {
    var number: Int
    var distanceMeters: Double
    var activeSeconds: Double
}

protocol EnduranceEntity: Codable, Identifiable, Sendable where ID == String {
    static var table: String { get }
    var id: String { get }
    var userId: String { get }
    var sortDate: Date { get }
    var isValid: Bool { get }
}

struct EnduranceActivity: EnduranceEntity, Hashable {
    static let table = "endurance_activities"
    var id: String = UUID().uuidString.lowercased()
    var userId: String
    var sport: EnduranceSport
    var title: String
    var startedAt: Date
    var endedAt: Date
    var activeSeconds: Double
    var distanceMeters: Double
    var elevationGainMeters: Double = 0
    var route: [EnduranceRoutePoint] = []
    var splits: [EnduranceSplit] = []
    var source: String = "shift"
    var healthKitID: String?
    var notes: String = ""
    var trainingSessionID: String?
    var savedRouteID: String?
    var sortDate: Date { startedAt }
    var elapsedSeconds: Double { max(0, endedAt.timeIntervalSince(startedAt)) }
    var isValid: Bool {
        !id.isEmpty && !userId.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endedAt >= startedAt && activeSeconds.isFinite && activeSeconds > 0
            && activeSeconds <= elapsedSeconds + 1 && distanceMeters.isFinite && distanceMeters >= 0
            && elevationGainMeters.isFinite && elevationGainMeters >= 0 && route.allSatisfy(\.isValid)
    }
}

/// The recorder checkpoints this state locally; unfinished routes never sync.
struct EnduranceDraft: Codable, Sendable {
    var id: String = UUID().uuidString.lowercased()
    var userId: String
    var sport: EnduranceSport
    var startedAt: Date
    var resumedAt: Date?
    var accumulatedSeconds: Double = 0
    var checkpointAt: Date
    var route: [EnduranceRoutePoint] = []
    var distanceMeters: Double = 0
    var elevationGainMeters: Double = 0
    var segment: Int = 0
    var splits: [EnduranceSplit] = []
    var lastSplitSeconds: Double = 0
    var elevationAnchor: Double?
    var smoothedAltitude: Double?
    var trainingSessionID: String?
    var savedRouteID: String?

    var isPaused: Bool { resumedAt == nil }
    func activeSeconds(at date: Date) -> Double {
        accumulatedSeconds + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    mutating func pause(at date: Date) {
        accumulatedSeconds = activeSeconds(at: date)
        resumedAt = nil
        checkpointAt = date
    }
    mutating func resume(at date: Date) {
        guard isPaused else { return }
        resumedAt = date
        segment += 1
        elevationAnchor = nil
        smoothedAltitude = nil
    }

    /// Reject stale, inaccurate and impossible samples. Pauses and signal gaps
    /// create separate segments, so neither maps nor distances bridge the gaps.
    @discardableResult
    mutating func append(_ sample: EnduranceRoutePoint, now: Date) -> Bool {
        guard !isPaused, sample.isValid,
              sample.timestamp >= (resumedAt ?? startedAt).timeIntervalSince1970,
              sample.timestamp >= startedAt.timeIntervalSince1970,
              sample.timestamp >= now.timeIntervalSince1970 - 20,
              sample.timestamp <= now.timeIntervalSince1970 + 5 else { return false }
        var point = sample
        point.segment = segment
        point.activeSeconds = activeSeconds(at: Date(timeIntervalSince1970: sample.timestamp))
        if let last = route.last {
            let dt = point.timestamp - last.timestamp
            guard dt > 0 else { return false }
            if last.segment == segment {
                if let speed = point.speedMetersPerSecond, speed.isFinite, speed >= 0, speed < 0.25 { return false }
                if dt > 30 {
                    segment += 1
                    point.segment = segment
                    elevationAnchor = nil
                    smoothedAltitude = nil
                } else {
                    let meters = last.distance(to: point)
                    guard meters / dt <= sport.maximumSpeed else { return false }
                    // Keep an anchor until movement clears small GPS jitter.
                    guard meters >= 3 else { return false }
                    let previousDistance = distanceMeters
                    distanceMeters += meters
                    while Double(splits.count + 1) * 1_000 <= distanceMeters {
                        let boundary = Double(splits.count + 1) * 1_000
                        let fraction = (boundary - previousDistance) / meters
                        let crossingTime = last.activeSeconds + fraction * (point.activeSeconds - last.activeSeconds)
                        splits.append(.init(number: splits.count + 1, distanceMeters: 1_000,
                                            activeSeconds: max(0, crossingTime - lastSplitSeconds)))
                        lastSplitSeconds = crossingTime
                    }
                }
            }
        }
        if point.verticalAccuracy >= 0 && point.verticalAccuracy <= 10 {
            let altitude = smoothedAltitude.map { $0 * 0.8 + point.altitude * 0.2 } ?? point.altitude
            smoothedAltitude = altitude
            if let anchor = elevationAnchor {
                let delta = altitude - anchor
                if abs(delta) >= 3 {
                    elevationGainMeters += max(0, delta)
                    elevationAnchor = altitude
                }
            } else { elevationAnchor = altitude }
        }
        route.append(point)
        checkpointAt = now
        return true
    }

    func finished(title: String, notes: String, at date: Date) -> EnduranceActivity {
        var allSplits = splits
        let remainder = distanceMeters - Double(splits.count) * 1_000
        if remainder > 1 {
            allSplits.append(.init(number: splits.count + 1, distanceMeters: remainder,
                                   activeSeconds: max(0, activeSeconds(at: date) - lastSplitSeconds)))
        }
        return EnduranceActivity(id: id, userId: userId, sport: sport, title: title,
            startedAt: startedAt, endedAt: date, activeSeconds: activeSeconds(at: date),
            distanceMeters: distanceMeters, elevationGainMeters: elevationGainMeters,
            route: route, splits: allSplits, notes: notes, trainingSessionID: trainingSessionID, savedRouteID: savedRouteID)
    }
}

enum EnduranceMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case distance, duration, activities
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum EnduranceGoalPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case week, month, deadline
    var id: String { rawValue }
    var title: String { switch self { case .week: return "Weekly"; case .month: return "Monthly"; case .deadline: return "By a date" } }
}

struct EnduranceGoal: EnduranceEntity, Hashable {
    static let table = "endurance_goals"
    var id: String = UUID().uuidString.lowercased()
    var userId: String
    /// nil combines all three endurance sports.
    var sport: EnduranceSport?
    var metric: EnduranceMetric
    /// SI units: meters, seconds, or activity count.
    var target: Double
    var period: EnduranceGoalPeriod
    var createdAt: Date = Date()
    var deadline: Date?
    var sortDate: Date { createdAt }
    var isValid: Bool {
        !id.isEmpty && !userId.isEmpty && target.isFinite && target > 0 && (metric != .activities || target.rounded() == target)
            && (period != .deadline || (deadline.map { $0 > createdAt } ?? false))
    }

    func interval(at now: Date, calendar: Calendar) -> DateInterval? {
        if period == .deadline {
            guard let deadline, deadline > createdAt else { return nil }
            return DateInterval(start: createdAt, end: deadline)
        }
        return calendar.dateInterval(of: period == .week ? .weekOfYear : .month, for: now)
    }

    func progress(in activities: [EnduranceActivity], at now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let window = interval(at: now, calendar: calendar) else { return 0 }
        return activities.filter {
            $0.userId == userId && (sport == nil || $0.sport == sport)
                && $0.startedAt >= window.start && $0.startedAt < window.end && $0.endedAt <= now
        }.reduce(0) { result, activity in
            switch metric {
            case .distance: return result + activity.distanceMeters
            case .duration: return result + activity.activeSeconds
            case .activities: return result + 1
            }
        }
    }
}

enum EnduranceFormat {
    static func distance(_ meters: Double, unit: String) -> String {
        String(format: "%.2f %@", meters / (unit == "mi" ? 1_609.344 : 1_000), unit)
    }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let total = max(0, Int(seconds))
        return total >= 3_600 ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
    static func pace(distance: Double, seconds: Double, sport: EnduranceSport, unit: String) -> String {
        guard distance > 0, seconds > 0 else { return "—" }
        let scale = unit == "mi" ? 1_609.344 : 1_000.0
        if sport == .cycle { return String(format: "%.1f %@/h", distance / scale / seconds * 3_600, unit) }
        return "\(duration(seconds / (distance / scale))) /\(unit)"
    }
}
