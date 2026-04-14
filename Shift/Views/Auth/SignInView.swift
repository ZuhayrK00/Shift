import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSignUp = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Logo + Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(colors.accent)
                            .padding(.bottom, 8)

                        Text("Welcome back")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(colors.text)

                        Text("Sign in to continue your training.")
                            .font(.system(size: 16))
                            .foregroundStyle(colors.muted)
                    }
                    .padding(.top, 64)
                    .padding(.bottom, 40)

                    // Form fields
                    VStack(spacing: 12) {
                        ShiftTextField(
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )

                        ShiftSecureField(
                            placeholder: "Password",
                            text: $password
                        )
                    }
                    .padding(.bottom, 8)

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }

                    // Sign In button
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Text("Sign in")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1)
                    .padding(.top, 8)

                    // Divider
                    dividerWithLabel("or")
                        .padding(.vertical, 20)

                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        Task { await handleAppleResult(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Google Sign In
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colors.text)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colors.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 10)

                    // Sign up link
                    Button {
                        showSignUp = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("No account?")
                                .foregroundStyle(colors.muted)
                            Text("Sign up")
                                .foregroundStyle(colors.accent)
                        }
                        .font(.system(size: 15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView()
        }
    }

    // MARK: - Helpers

    private func dividerWithLabel(_ label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(colors.muted)
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
        }
    }

    private func signIn() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.signInWithEmail(email, password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func signInWithGoogle() async {
        errorMessage = nil
        do {
            try await authManager.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            errorMessage = nil
            do {
                try await authManager.signInWithApple(credential)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            // ASAuthorizationError.canceled is user-initiated; don't surface it
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Shared text field components

struct ShiftTextField: View {
    @Environment(\.shiftColors) private var colors
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .font(.system(size: 16))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ShiftSecureField: View {
    @Environment(\.shiftColors) private var colors
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .font(.system(size: 16))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
