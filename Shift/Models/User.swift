import Foundation

// NOT a database record — synthesized from auth session + profile row.

struct User: Identifiable {
    var id: String
    var email: String?
    var name: String?
    var age: Int?
    var weight: Double?
    var height: Double?            // total inches
    var profilePictureUrl: String?
    var createdAt: Date?
    var settings: UserSettings

    // MARK: - Computed helpers

    /// Best available name for greeting: explicit name, email username, or fallback "there".
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let email, let at = email.firstIndex(of: "@") {
            let username = String(email[email.startIndex..<at])
            if !username.isEmpty { return username }
        }
        return "there"
    }

    /// Two uppercase initials derived from displayName, or "?" when unavailable.
    var initials: String {
        let words = displayName
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "?" }

        if words.count == 1 {
            let first = words[0]
            // Guard: "there" and email usernames get just one initial
            guard let initial = first.first else { return "?" }
            return String(initial).uppercased()
        }

        // Two words → first letter of each
        let firstInitial = words[0].first.map { String($0).uppercased() } ?? ""
        let secondInitial = words[1].first.map { String($0).uppercased() } ?? ""
        return firstInitial + secondInitial
    }
}
