import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo/Title
                VStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("WhatsNext")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Connect and chat with friends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                Spacer()

                // OAuth Sign In Buttons
                VStack(spacing: 12) {
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            Task {
                                await authViewModel.signInWithApple()
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)

                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
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

                    Text("or continue with email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color(.systemGray4))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Login Form
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

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .onSubmit {
                            if isFormValid {
                                Task {
                                    await authViewModel.signIn(email: email, password: password)
                                }
                            }
                        }
                    
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button {
                        Task {
                            await authViewModel.signIn(email: email, password: password)
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Sign In")
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

                    // Forgot Password
                    Button {
                        guard !email.isEmpty, email.contains("@") else {
                            authViewModel.errorMessage = "Enter a valid email to reset password"
                            return
                        }
                        Task { await authViewModel.requestPasswordReset(email: email) }
                    } label: {
                        Text("Forgot password?")
                            .font(.footnote)
                    }
                }
                .padding(.horizontal)
                
                // Sign Up Link
                Button {
                    showSignUp = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundStyle(.secondary)
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .padding(.top, 8)
                
                Spacer()
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}

