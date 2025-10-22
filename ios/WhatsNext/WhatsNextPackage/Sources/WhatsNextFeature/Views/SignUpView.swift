import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var displayName = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Create Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Join WhatsNext to start chatting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // OAuth Sign In Buttons
                VStack(spacing: 12) {
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            Task {
                                await authViewModel.signInWithApple()
                                if authViewModel.isAuthenticated {
                                    dismiss()
                                }
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)

                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
                            if authViewModel.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.title3)
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .disabled(authViewModel.isLoading)
                }
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color(.systemGray4))

                    Text("or sign up with email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color(.systemGray4))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Sign Up Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    TextField("Username (optional)", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    TextField("Display Name (optional)", text: $displayName)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .onSubmit {
                            if isFormValid {
                                Task {
                                    await authViewModel.signUp(
                                        email: email,
                                        password: password,
                                        username: username.isEmpty ? nil : username,
                                        displayName: displayName.isEmpty ? nil : displayName
                                    )

                                    if authViewModel.isAuthenticated {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if !passwordsMatch && !confirmPassword.isEmpty {
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button {
                        Task {
                            await authViewModel.signUp(
                                email: email,
                                password: password,
                                username: username.isEmpty ? nil : username,
                                displayName: displayName.isEmpty ? nil : displayName
                            )
                            
                            if authViewModel.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        isFormValid ? Color.blue : Color.gray
                    )
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                    .disabled(!isFormValid || authViewModel.isLoading)
                }
                .padding(.horizontal)
                
                // Back to Login
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundStyle(.secondary)
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        email.contains("@") &&
        password.count >= 6 &&
        passwordsMatch
    }
    
    private var passwordsMatch: Bool {
        password == confirmPassword
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environmentObject(AuthViewModel())
    }
}

