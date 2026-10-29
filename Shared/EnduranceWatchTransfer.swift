import Foundation

struct EnduranceWatchTransfer: Codable {
    var schemaVersion = 1
    var revision: String = UUID().uuidString.lowercased()
    var userID: String
    var activity: EnduranceActivity
    var isValid: Bool {
        schemaVersion == 1 && UUID(uuidString: activity.id) != nil && UUID(uuidString: userID) != nil
            && userID == activity.userId && activity.source == "shift" && activity.isValid
    }
    func matchesAcknowledgment(id: String, owner: String, revision: String) -> Bool {
        isValid && activity.id == id && userID == owner && self.revision == revision
    }
    func canReceive(as owner: String?) -> Bool { isValid && owner == userID }
}
