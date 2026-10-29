import Foundation

enum EnduranceImportRange: String, CaseIterable, Identifiable {
    case allHistory = "All history", lastYear = "Last year", last90Days = "Last 90 days"
    var id: String { rawValue }
    func startDate(at now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .allHistory: nil
        case .lastYear: calendar.date(byAdding: .year, value: -1, to: now)
        case .last90Days: calendar.date(byAdding: .day, value: -90, to: now)
        }
    }
    var scopeDescription: String {
        switch self { case .allHistory: "from all available history"; case .lastYear: "from the last year"; case .last90Days: "from the last 90 days" }
    }
}

enum EnduranceHealthPreferences {
    private static func routeKey(userID: String) -> String {
        "shift.endurance.healthImport.\(userID.lowercased()).includeRoutes"
    }

    static func includesRoutes(userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: routeKey(userID: userID))
    }

    static func setIncludesRoutes(_ enabled: Bool, userID: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: routeKey(userID: userID))
    }

    static func clear(userID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: routeKey(userID: userID))
    }
}

/// A repeat import can succeed without adding anything. Keep that separate from
/// Health returning no readable workouts or providing no route for a workout.
struct EnduranceImportReport: Equatable, Sendable {
    var foundCount = 0
    var importedCount = 0
    var updatedRouteCount = 0
    var alreadyImportedCount = 0
    var unavailableRouteCount = 0
    var invalidWorkoutCount = 0
    var shiftWorkoutCount = 0
    var previouslyImportedCount = 0
    var range: EnduranceImportRange = .allHistory
    var walkCount = 0
    var runCount = 0
    var cycleCount = 0
    var routeFailureCount = 0

    var title: String {
        if importedCount > 0 || updatedRouteCount > 0 { return "Import complete" }
        if alreadyImportedCount > 0 && unavailableRouteCount > 0 { return "Activities saved, maps unavailable" }
        if alreadyImportedCount > 0 { return "You're up to date" }
        return "No workouts to import"
    }

    var message: String {
        var parts: [String] = []
        if foundCount > 0 { parts.append("Found \(walkCount) walks/hikes, \(runCount) runs and \(cycleCount) rides \(range.scopeDescription).") }
        if importedCount > 0 {
            parts.append("Added \(importedCount) new \(importedCount == 1 ? "activity" : "activities").")
        }
        if updatedRouteCount > 0 {
            parts.append("Added maps to \(updatedRouteCount) previously imported \(updatedRouteCount == 1 ? "activity" : "activities").")
        }
        if alreadyImportedCount > 0 {
            if importedCount == 0 && updatedRouteCount == 0 {
                parts.append(alreadyImportedCount == 1
                    ? "This workout is already in Shift. Find it in Activities."
                    : "All \(alreadyImportedCount) available workouts are already in Shift. Find them in Activities.")
            } else {
                parts.append("\(alreadyImportedCount) \(alreadyImportedCount == 1 ? "workout was" : "workouts were") already in Shift; no duplicates were added.")
            }
        }
        if foundCount == 0 {
            if shiftWorkoutCount > 0 {
                parts.append("The available workouts were recorded by Shift and don't need to be imported again.")
            } else {
                // HealthKit does not disclose whether read access was denied.
                parts.append("Apple Health didn't return any runs, walks, hikes or rides \(range.scopeDescription). Check Shift's workout read access in Apple Health if you expected to see workouts. Daily step and walking-distance totals without a recorded workout aren't individual sessions.")
            }
            if previouslyImportedCount > 0 {
                parts.append("Your \(previouslyImportedCount) previously imported \(previouslyImportedCount == 1 ? "activity is" : "activities are") still saved in Activities.")
            }
        }
        if unavailableRouteCount > 0 {
            parts.append("Apple Health didn't provide map data for \(unavailableRouteCount) \(unavailableRouteCount == 1 ? "workout" : "workouts"). The workout may have no GPS route, or route read access may not be allowed. Its saved activity is kept.")
        }
        if invalidWorkoutCount > 0 {
            parts.append("Skipped \(invalidWorkoutCount) \(invalidWorkoutCount == 1 ? "workout" : "workouts") without usable recording data.")
        }
        if routeFailureCount > 0 { parts.append("Map queries failed for \(routeFailureCount) workouts. Their workout details were still imported or kept; import again with maps enabled to retry.") }
        return parts.joined(separator: "\n\n")
    }
}
