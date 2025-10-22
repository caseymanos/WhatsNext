import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let authService = AuthService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        Task {
            await checkAuthStatus()
        }
    }
    
    /// Check if user is already authenticated
    func checkAuthStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let user = try await authService.getCurrentUser() {
                currentUser = user
                isAuthenticated = true
            } else {
                isAuthenticated = false
            }
        } catch {
            isAuthenticated = false
            print("Error checking auth status: \(error)")
        }
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String, username: String?, displayName: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let user = try await authService.signUp(
                email: email,
                password: password,
                username: username,
                displayName: displayName
            )
            currentUser = user
            isAuthenticated = true
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let user = try await authService.signIn(email: email, password: password)
            currentUser = user
            isAuthenticated = true
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }
    }
    
    /// Sign out
    func signOut() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let userId = currentUser?.id
        
        do {
            try await authService.signOut(userId: userId)
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = "Failed to sign out"
        }
    }
    
    /// Update user profile
    func updateProfile(username: String?, displayName: String?, avatarUrl: String?) async {
        guard let userId = currentUser?.id else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await authService.updateProfile(
                userId: userId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl
            )
            
            // Refresh current user
            if let updatedUser = try await authService.getCurrentUser() {
                currentUser = updatedUser
            }
        } catch {
            errorMessage = "Failed to update profile"
        }
    }
    
    /// Update last seen (call periodically or on app foreground)
    func updateLastSeen() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await authService.updateLastSeen(userId: userId)
        } catch {
            print("Failed to update last seen: \(error)")
        }
    }
    
    /// Update user status
    func updateStatus(_ status: UserStatus) async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await authService.updateStatus(userId: userId, status: status)
            // Update local state
            currentUser?.status = status
        } catch {
            print("Failed to update status: \(error)")
        }
    }
    
    // MARK: - Password Reset
    func requestPasswordReset(email: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authService.requestPasswordReset(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func updatePassword(newPassword: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authService.updatePassword(newPassword: newPassword)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

