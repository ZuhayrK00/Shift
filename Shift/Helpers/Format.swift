import Foundation

// MARK: - ISO 8601 formatter singletons

extension ISO8601DateFormatter {
    /// Standard formatter: "2024-01-15T10:30:00Z"
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Fractional-seconds variant: "2024-01-15T10:30:00.000Z"
    static let sharedWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Pluralise

/// Returns "\(count) \(singular)" or "\(count) \(plural)" based on count.
/// If plural is omitted, appends "s" to the singular.
///
///     pluralise(1, "SET")   → "1 SET"
///     pluralise(3, "SET")   → "3 SETS"
///     pluralise(1, "rep")   → "1 rep"
///     pluralise(2, "rep")   → "2 reps"
func pluralise(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    let word = count == 1 ? singular : (plural ?? singular + "s")
    return "\(count) \(word)"
}

// MARK: - Weight formatting

private let kgToLbs = 2.20462

/// Converts a weight stored in kg to the display unit if needed.
func convertWeight(_ kg: Double, to unit: String) -> Double {
    unit == "lbs" ? kg * kgToLbs : kg
}

/// Converts a weight from the display unit back to kg for storage.
func convertWeightToKg(_ value: Double, from unit: String) -> Double {
    unit == "lbs" ? value / kgToLbs : value
}

/// Formats a weight value (stored in kg) for display in the user's chosen unit.
///
///     formatWeight(60, unit: "kg")  → "60 kg"
///     formatWeight(60, unit: "lbs") → "132 lbs"
func formatWeight(_ kg: Double, unit: String) -> String {
    let val = convertWeight(kg, to: unit)
    let numStr = val == val.rounded() ? String(format: "%.0f", val) : String(format: "%.1f", val)
    return "\(numStr) \(unit)"
}

// MARK: - Date key helpers

private let localDateKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    // Uses the device's current time zone (no explicit zone set)
    return f
}()

/// Returns a "YYYY-MM-DD" key in the device's local time zone.
///
///     toLocalDateKey(Date())  → "2024-01-15"
func toLocalDateKey(_ date: Date) -> String {
    localDateKeyFormatter.string(from: date)
}

/// Returns a Date set to noon on the same local calendar day as `date`.
/// Useful for building stable "day" comparisons without time-zone edge cases.
func noonOfLocalDate(_ date: Date) -> Date {
    var cal = Calendar.current
    cal.locale = Locale(identifier: "en_US_POSIX")
    var comps = cal.dateComponents([.year, .month, .day], from: date)
    comps.hour = 12
    comps.minute = 0
    comps.second = 0
    return cal.date(from: comps) ?? date
}
