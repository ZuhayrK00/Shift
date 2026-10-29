import Foundation
import WatchConnectivity

/// Completed activities remain on Watch until iPhone acknowledges a durable save.
@MainActor
enum WatchEnduranceOutbox {
    private static var folder: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EnduranceOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    static func save(_ activity: EnduranceActivity) throws {
        let envelope = EnduranceWatchTransfer(userID: activity.userId, activity: activity)
        guard envelope.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: folder.appendingPathComponent("\(activity.id).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func flush() {
        guard let owner = WatchSessionManager.shared.context?.userId, WatchSessionManager.shared.isSignedIn,
              WCSession.default.activationState == .activated else { return }
        let outstanding = Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            guard !outstanding.contains(url.lastPathComponent),
                  let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(EnduranceWatchTransfer.self, from: data),
                  record.canReceive(as: owner) else { continue }
            WCSession.default.transferFile(url, metadata: ["stateType": "enduranceActivity", "userID": owner, "activityID": record.activity.id, "revision": record.revision])
        }
    }
    static func acknowledge(id: String, owner: String, revision: String) {
        guard UUID(uuidString: id) != nil else { return }
        let url = folder.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(EnduranceWatchTransfer.self, from: data),
              record.matchesAcknowledgment(id: id, owner: owner, revision: revision) else { return }
        try? FileManager.default.removeItem(at: url)
    }
    static func removeDeletedAccount(_ owner: String) {
        guard UUID(uuidString: owner) != nil else { return }
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(EnduranceWatchTransfer.self, from: data), record.userID == owner else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
    static func pendingCount(owner: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { url in
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(EnduranceWatchTransfer.self, from: data) else { return false }
            return record.canReceive(as: owner)
        }.count
    }
}
