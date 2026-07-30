import Foundation

enum AgePolicy {
    static let minimumAge = 13
    static let maximumAge = 120

    static func isEligible(_ age: Int?) -> Bool {
        guard let age else { return false }
        return (minimumAge...maximumAge).contains(age)
    }
}
