import Foundation
import Supabase
import AuthenticationServices

private final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        continuation?.resume(returning: value)
    }
}

// MARK: - AuthManager

/// Observable auth state manager. Listens for Supabase auth events, loads the
/// full User model (session + cached profile), and exposes it to the UI.
@Observable
class AuthManager {
    var session: Session?
    var user: User?
    var isLoading = true
    var showPasswordReset = false

    init() {
        Task { await listenForAuthChanges() }
    }

    // MARK: - Auth state listener

    func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed:
                if let session {
                    await MainActor.run { self.session = session }
                    await loadUser(session)
                    if event != .tokenRefreshed {
                        await StoreService.shared.updatePurchasedProducts(syncWatch: false)
                        await WidgetDataService.updateSnapshot(
                            knownProStatus: StoreService.shared.isPro
                        )
                        PhoneSessionManager.shared.sendContextToWatch()
                    }
                } else {
                    await MainActor.run { self.isLoading = false }
                }
            case .signedOut:
                let signedOutUserId = self.currentUserId
                UserDefaults.standard.removeObject(forKey: "shift.cachedUserId")
                await MainActor.run {
                    self.session = nil
                    self.user = nil
                    self.isLoading = false
                }
                await GoalNotificationService.clearUserState(userId: signedOutUserId)
                ImageCache.shared.removeAll()
                await StoreService.shared.reset()
            case .passwordRecovery:
                if let session {
                    await MainActor.run {
                        self.session = session
                        self.showPasswordReset = true
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run { self.isLoading = false }
                }
            default:
                await MainActor.run { self.isLoading = false }
            }
        }
    }

    // MARK: - User loading

    /// Builds the full User from the session + local/remote profile cache.
    func loadUser(_ session: Session) async {
        // Only show loading screen on first load — not on token refreshes,
        // which would destroy and recreate MainTabView (re-triggering sync).
        if user == nil {
            await MainActor.run { isLoading = true }
        }

        let userId = session.user.id.uuidString.lowercased()

        // Try local cache first, fall back to remote with a timeout
        let profile: Profile?
        if let cached = try? await ProfileRepository.findById(userId) {
            profile = cached
        } else {
            // Use unstructured child tasks so returning at the deadline does not
            // wait for a network request that is slow to honour cancellation.
            let fetchTask = Task {
                try? await ProfileService.fetchAndCacheProfile(userId)
            }
            profile = await withCheckedContinuation { continuation in
                let gate = OneShotContinuation<Profile?>(continuation)
                Task {
                    gate.resume(returning: await fetchTask.value)
                }
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    fetchTask.cancel()
                    gate.resume(returning: nil)
                }
            }
        }

        let settings = profile?.settings ?? .default
        let createdAtDate: Date? = session.user.createdAt

        let newUser = User(
            id: userId,
            email: session.user.email,
            name: profile?.name,
            age: profile?.age,
            weight: profile?.weight,
            profilePictureUrl: profile?.profilePictureUrl,
            createdAt: createdAtDate,
            settings: settings
        )

        // Cache userId for background wake access (HealthKit observer may fire
        // before the async auth listener has restored the Supabase session)
        UserDefaults.standard.set(userId, forKey: "shift.cachedUserId")
        WidgetSnapshot.setActiveUserId(userId)

        await MainActor.run {
            self.session = session
            self.user = newUser
            self.isLoading = false
        }
    }

    // MARK: - Sign in / sign up

    func signInWithEmail(_ email: String, _ password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signUpWithEmail(_ email: String, _ password: String) async throws {
        try await supabase.auth.signUp(email: email, password: password)
    }

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) async throws {
        guard let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingAppleToken
        }
        try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: tokenString)
        )
    }

    func signInWithGoogle() async throws {
        try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: "com.zuhayrk.shift://callback")
        )
    }

    func updateEmail(_ newEmail: String) async throws {
        try await supabase.auth.update(user: UserAttributes(email: newEmail))
    }

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    func updatePassword(_ newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    func signOut() async throws {
        let signedOutUserId = currentUserId
        _ = try? await SyncService.flushQueue()
        try await supabase.auth.signOut()
        await GoalNotificationService.clearUserState(userId: signedOutUserId)
        ImageCache.shared.removeAll()
        await StoreService.shared.reset()
    }

    // MARK: - Refresh

    /// Re-reads the local profile and rebuilds the User without touching isLoading.
    /// This avoids flashing the loading screen and destroying the tab view.
    func refreshUser() async {
        guard let session else { return }
        let userId = session.user.id.uuidString.lowercased()
        let profile = try? await ProfileRepository.findById(userId)
        // Only use settings from profile if we actually found one — never reset to defaults
        let settings = profile?.settings ?? user?.settings ?? .default

        let newUser = User(
            id: userId,
            email: session.user.email,
            name: profile?.name,
            age: profile?.age,
            weight: profile?.weight,
            profilePictureUrl: profile?.profilePictureUrl,
            createdAt: session.user.createdAt,
            settings: settings
        )

        await MainActor.run { self.user = newUser }
    }

    // MARK: - Helpers

    var currentUserId: String? {
        session?.user.id.uuidString.lowercased()
            ?? UserDefaults.standard.string(forKey: "shift.cachedUserId")
    }

    func requireUserId() throws -> String {
        guard let id = currentUserId else {
            throw AuthError.notSignedIn
        }
        return id
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case notSignedIn
    case missingAppleToken

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in."
        case .missingAppleToken: return "Apple identity token was missing."
        }
    }
}
