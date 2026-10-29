import Foundation

enum TrainingDeepLinkStore {
    private static let key = "shift.pendingTrainingLink"
    static func store(_ url: URL) {
        guard url.scheme == "shift", ["endurance", "training-calendar"].contains(url.host ?? "") else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }
    static func consume(owner: String?) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: key), let url = URL(string: raw) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        let requestedOwner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "owner" }?.value
        guard requestedOwner == nil || requestedOwner == owner else { return nil }
        return url
    }
    static func calendarDate(_ url: URL) -> Date? {
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "date" })?.value else { return nil }
        let formatter = DateFormatter(); formatter.calendar = .current; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
