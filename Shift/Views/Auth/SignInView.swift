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
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Logo + Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image("ShiftLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
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

                    // Forgot password
                    Button {
                        showForgotPassword = true
                    } label: {
                        Text("Forgot password?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet()
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
        guard email.isValidEmail else {
            errorMessage = "Please enter a valid email address."
            return
        }
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
            // ASWebAuthenticationSession error 1 is user cancellation — don't surface it
            let nsError = error as NSError
            if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               nsError.code == 1 {
                return
            }
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

// MARK: - Email Validation

extension String {
    var isValidEmail: Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - ForgotPasswordSheet

struct ForgotPasswordSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset password")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(colors.text)
                        .padding(.bottom, 8)

                    Text("Enter your email and we'll send you a link to reset your password.")
                        .font(.system(size: 15))
                        .foregroundStyle(colors.muted)
                        .padding(.bottom, 28)

                    if sent {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.success)
                            Text("If an account exists with that email, you'll receive a reset link shortly.")
                                .font(.system(size: 14))
                                .foregroundStyle(colors.success)
                        }
                        .padding(.bottom, 12)
                    } else {
                        ShiftTextField(
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )
                        .padding(.bottom, 8)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger)
                                .padding(.bottom, 8)
                        }

                        Button {
                            Task { await sendReset() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                } else {
                                    Text("Send reset link")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(colors.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(email.isEmpty || isLoading)
                        .opacity((email.isEmpty || isLoading) ? 0.6 : 1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.muted)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func sendReset() async {
        guard !email.isEmpty else { return }
        guard email.isValidEmail else {
            errorMessage = "Please enter a valid email address."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.resetPassword(email: email)
            sent = true
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("not found")
                || message.contains("no user")
                || message.contains("unable to validate")
                || message.contains("user not found") {
                errorMessage = "No account found with that email address."
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
