import Foundation
import Supabase
import AuthenticationServices

// MARK: - AuthManager

/// Observable auth state manager. Listens for Supabase auth events, loads the
/// full User model (session + cached profile), and exposes it to the UI.
@Observable
class AuthManager {
    var session: Session?
    var user: User?
    var isLoading = true

    init() {
        Task { await listenForAuthChanges() }
    }

    // MARK: - Auth state listener

    func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed:
                if let session {
                    self.session = session
                    await loadUser(session)
                } else {
                    self.isLoading = false
                }
            case .signedOut:
                self.session = nil
                self.user = nil
                self.isLoading = false
            default:
                self.isLoading = false
            }
        }
    }

    // MARK: - User loading

    /// Builds the full User from the session + local/remote profile cache.
    func loadUser(_ session: Session) async {
        isLoading = true
        defer { isLoading = false }

        let userId = session.user.id.uuidString

        // Try local cache first
        let profile: Profile?
        if let cached = try? await ProfileRepository.findById(userId) {
            profile = cached
        } else {
            // Fall back to remote fetch and cache locally
            profile = try? await ProfileService.fetchAndCacheProfile(userId)
        }

        let settings = profile?.settings ?? .default
        let createdAtDate: Date? = session.user.createdAt

        self.session = session
        self.user = User(
            id: userId,
            email: session.user.email,
            name: profile?.name,
            age: profile?.age,
            weight: profile?.weight,
            profilePictureUrl: profile?.profilePictureUrl,
            createdAt: createdAtDate,
            settings: settings
        )
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

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Refresh

    func refreshUser() async {
        guard let session else { return }
        await loadUser(session)
    }

    // MARK: - Helpers

    var currentUserId: String? { session?.user.id.uuidString }

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
