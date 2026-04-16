import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isLoading = false

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6 && !isLoading
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image("ShiftLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .padding(.bottom, 8)

                        Text("Create account")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(colors.text)

                        Text("Start tracking your lifts.")
                            .font(.system(size: 16))
                            .foregroundStyle(colors.muted)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)

                    // Fields
                    VStack(spacing: 12) {
                        ShiftTextField(
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )

                        ShiftSecureField(
                            placeholder: "Password (min. 6 characters)",
                            text: $password
                        )
                    }
                    .padding(.bottom, 8)

                    // Feedback
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.danger)
                            .padding(.vertical, 4)
                    }

                    if let successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.success)
                            Text(successMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(colors.success)
                        }
                        .padding(.vertical, 4)
                    }

                    // Create account button
                    Button {
                        Task { await signUp() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Text("Create account")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)
                    .padding(.top, 8)

                    // Sign in link
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(colors.muted)
                            Text("Sign in")
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
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil
        do {
            try await authManager.signUpWithEmail(email, password)
            // If Supabase auto-confirms, the auth listener will pick up the
            // session and navigate to onboarding automatically.
            // Give it a moment to process the auth state change.
            try? await Task.sleep(for: .milliseconds(500))
            if authManager.session != nil {
                // User is signed in — auth flow will handle navigation
                return
            }
            // Email confirmation required
            successMessage = "Account created! Check your email to confirm, then sign in."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
