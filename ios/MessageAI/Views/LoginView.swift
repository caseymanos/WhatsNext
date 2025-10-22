import SwiftUI

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
                
                // Login Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
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

