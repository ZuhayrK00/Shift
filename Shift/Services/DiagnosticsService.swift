import Foundation

struct DiagnosticsSnapshot {
    let appVersion: String
    let buildNumber: String
    let lastReferenceSync: Date?
    let pendingChanges: Int
    let failedChanges: Int
    let nextRetry: Date?
    let lastQueueError: String?
    let widgetUpdatedAt: Date?
    let entitlementVerifiedAt: Date?
    let isPro: Bool
    let watchPaired: Bool
    let watchInstalled: Bool
    let watchReachable: Bool
    let watchLastSync: Date?

    var shareableText: String {
        let formatter = ISO8601DateFormatter()
        func date(_ value: Date?) -> String { value.map(formatter.string) ?? "never" }
        return """
        Shift diagnostics
        App: \(appVersion) (\(buildNumber))
        Reference sync: \(date(lastReferenceSync))
        Pending changes: \(pendingChanges)
        Failed changes: \(failedChanges)
        Next retry: \(date(nextRetry))
        Last sync error: \(lastQueueError ?? "none")
        Widget snapshot: \(date(widgetUpdatedAt))
        Entitlement: \(isPro ? "Pro" : "Free"), verified \(date(entitlementVerifiedAt))
        Watch: paired=\(watchPaired), installed=\(watchInstalled), reachable=\(watchReachable)
        Watch sync: \(date(watchLastSync))
        """
    }
}

enum DiagnosticsService {
    static func load() async -> DiagnosticsSnapshot {
        let rows = (try? await MutationQueueRepository.readPending()) ?? []
        let phone = PhoneSessionManager.shared
        let info = Bundle.main.infoDictionary ?? [:]
        return DiagnosticsSnapshot(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            lastReferenceSync: SyncService.getLastSyncedAt(),
            pendingChanges: rows.count,
            failedChanges: rows.filter { $0.attemptCount > 0 }.count,
            nextRetry: try? await MutationQueueRepository.nextRetryDate(),
            lastQueueError: sanitize(rows.last(where: { $0.lastError != nil })?.lastError),
            widgetUpdatedAt: WidgetSnapshot.read()?.updatedAt,
            entitlementVerifiedAt: StoreEntitlementCache.read()?.verifiedAt,
            isPro: StoreService.shared.isPro,
            watchPaired: phone.isWatchPaired,
            watchInstalled: phone.isWatchAppInstalled,
            watchReachable: phone.isWatchReachable,
            watchLastSync: phone.lastSyncDate
        )
    }

    static func retryEverything() async -> DiagnosticsSnapshot {
        await StoreService.shared.updatePurchasedProducts(syncWatch: false)
        _ = try? await SyncService.flushQueue()
        if authManager.currentUserId != nil {
            try? await SyncService.pullUserData()
        }
        await WidgetDataService.updateSnapshot(knownProStatus: StoreService.shared.isPro)
        PhoneSessionManager.shared.sendContextToWatch(refreshEntitlement: true)
        return await load()
    }

    private static func sanitize(_ error: String?) -> String? {
        guard let error else { return nil }
        return String(
            error
                .replacingOccurrences(
                    of: #"(?i)(bearer|token|authorization|apikey)[=: ]+[^\s,;]+"#,
                    with: "$1=[redacted]",
                    options: .regularExpression
                )
                .prefix(240)
        )
    }
}
