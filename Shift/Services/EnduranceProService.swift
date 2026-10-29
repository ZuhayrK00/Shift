import Foundation
import Supabase

@MainActor @Observable
final class EnduranceProAccess {
    static let shared = EnduranceProAccess()
    private(set) var owner: String?
    private(set) var previewChecked = false
    private(set) var usedPreview = false
    private(set) var loading = false
    private(set) var error: String?
    private var revision = UUID()
    var decision: EndurancePlanningAccess {
        EnduranceProPolicy.planningAccess(isChecking: StoreService.shared.isCheckingEntitlement || loading,
            isPro: StoreService.shared.isPro, previewChecked: owner == authManager.currentUserId && previewChecked,
            hasUsedPreview: owner == authManager.currentUserId && usedPreview)
    }
    func load() async {
        let current = authManager.currentUserId
        let pass = UUID(); revision = pass
        if owner != current { owner = current; previewChecked = false; usedPreview = false; error = nil }
        guard let current else { loading = false; return }
        loading = true
        defer { if revision == pass { loading = false } }
        do {
            if StoreService.shared.isPro { error = nil; return }
            if let _ = try await EndurancePreviewStore.shared.receipt(owner: current) {
                guard revision == pass, authManager.currentUserId == current else { return }
                usedPreview = true; previewChecked = true; error = nil
                return
            }
            let receipts = try await EnduranceProService.remoteReceipts(owner: current)
            guard revision == pass, authManager.currentUserId == current else { return }
            if let receipt = receipts.first { try await EndurancePreviewStore.shared.remember(receipt) }
            guard revision == pass, authManager.currentUserId == current else { return }
            usedPreview = !receipts.isEmpty; previewChecked = true; error = nil
        } catch {
            guard revision == pass, authManager.currentUserId == current else { return }
            previewChecked = false
            self.error = "Connect to the internet to check your free week. Your saved plans are still available."
        }
    }
}

@MainActor
enum EnduranceProService {
    enum AccessError: LocalizedError, Equatable {
        case proRequired, checkUnavailable, invalidWeek
        var errorDescription: String? {
            switch self {
            case .proRequired: return "Your free week has been used. Shift Pro unlocks continued personalised planning. Your saved week stays yours."
            case .checkUnavailable: return "Connect to the internet to check your free week, then try again. It won't be used unless your plan saves."
            case .invalidWeek: return "Choose a valid week with one to seven sessions before saving."
            }
        }
    }
    static func requirePro() async throws {
        let owner = try authManager.requireUserId()
        guard await StoreService.verifyProEntitlement() else { throw AccessError.proRequired }
        guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
    }
    static func remoteReceipts(owner: String) async throws -> [EnduranceWeekPreview] {
        let response = try await supabase.from("endurance_week_previews").select().eq("user_id", value: owner).limit(1).execute()
        let records = try EnduranceCoding.decoder().decode([EnduranceWeekPreview].self, from: response.data)
        guard records.allSatisfy({ $0.userID == owner }), authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
        return records
    }
    /// Recheck at each paid operation, not just at the navigation/paywall boundary.
    static func requirePlanningAccess(retrying programID: String? = nil) async throws {
        let owner = try authManager.requireUserId()
        if await StoreService.verifyProEntitlement() {
            guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
            return
        }
        guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
        if let cached = try await EndurancePreviewStore.shared.receipt(owner: owner), cached.programID != programID {
            throw AccessError.proRequired
        }
        do {
            let records = try await remoteReceipts(owner: owner)
            if let receipt = records.first {
                try await EndurancePreviewStore.shared.remember(receipt)
                guard receipt.programID == programID else { throw AccessError.proRequired }
            }
        } catch let error as AccessError { throw error }
        catch { throw AccessError.checkUnavailable }
        guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
    }

    static func saveGeneratedWeek(_ sessions: [TrainingSession], programID: String) async throws {
        let owner = try authManager.requireUserId()
        guard EnduranceProPolicy.isValidPreview(sessions, owner: owner, programID: programID) else { throw AccessError.invalidWeek }
        if await StoreService.verifyProEntitlement() {
            guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
            try await EnduranceService.schedule(sessions)
            return
        }
        guard authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
        struct Parameters: Encodable {
            var p_program_id: String
            var p_sessions: [TrainingSession]
            func encode(to encoder: Encoder) throws {
                // Endurance uses ISO-8601 dates, independent of the client's default encoder.
                enum Keys: CodingKey { case p_program_id, p_sessions }
                var container = encoder.container(keyedBy: Keys.self)
                try container.encode(p_program_id, forKey: .p_program_id)
                let json = try EnduranceCoding.encoder().encode(p_sessions)
                try container.encode(try JSONDecoder().decode([AnyJSON].self, from: json), forKey: .p_sessions)
            }
        }
        let response: PostgrestResponse<Void>
        do { response = try await supabase.rpc("save_endurance_week_preview", params: Parameters(p_program_id: programID, p_sessions: sessions)).execute() }
        catch { throw AccessError.checkUnavailable }
        struct SavedWeek: Decodable { var receipt: EnduranceWeekPreview; var sessions: [TrainingSession] }
        let saved = try EnduranceCoding.decoder().decode(SavedWeek.self, from: response.data)
        guard saved.receipt.userID == owner, authManager.currentUserId == owner else { throw EnduranceError.wrongAccount }
        guard saved.receipt.programID == programID else {
            try await EndurancePreviewStore.shared.remember(saved.receipt)
            throw AccessError.proRequired
        }
        try await EndurancePreviewStore.shared.apply(saved.receipt, sessions: saved.sessions)
        NotificationCenter.default.post(name: .shiftEnduranceDidChange, object: nil)
        await TrainingNotificationService.reconcile()
        await EnduranceService.refreshSummaries()
        await EnduranceProAccess.shared.load()
    }
}
