import Foundation
import Supabase

enum AuthError: LocalizedError {
    case invalidCredentials
    case userCreationFailed
    case sessionExpired
    case networkError(Error)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .userCreationFailed:
            return "Failed to create user profile"
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}

final class AuthService {
    private let supabase = SupabaseClientService.shared
    
    /// Sign up with email and password
    func signUp(email: String, password: String, username: String?, displayName: String?) async throws -> User {
        do {
            // Create auth user
            let authResponse = try await supabase.auth.signUp(
                email: email,
                password: password
            )

            // When email confirmation is disabled, session will be available immediately
            // When enabled, session will be nil until user confirms their email
            guard let session = authResponse.session else {
                throw AuthError.userCreationFailed
            }

            // Create user profile
            let user = User(
                id: session.user.id,
                email: email,
                username: username,
                displayName: displayName,
                avatarUrl: nil,
                createdAt: Date(),
                lastSeen: Date(),
                status: .online,
                pushToken: nil
            )

            try await supabase.database
                .from("users")
                .insert(user)
                .execute()

            // Register for push notifications after successful signup
            await registerPushNotifications(userId: user.id)

            return user
        } catch {
            throw AuthError.unknown(error)
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> User {
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            // Fetch user profile
            let user: User = try await supabase.database
                .from("users")
                .select()
                .eq("id", value: session.user.id)
                .single()
                .execute()
                .value
            
            // Update last_seen
            try await updateLastSeen(userId: user.id)
            
            // Register for push notifications and save token
            await registerPushNotifications(userId: user.id)
            
            return user
        } catch {
            throw AuthError.invalidCredentials
        }
    }
    
    /// Sign out
    func signOut(userId: UUID?) async throws {
        // Remove push token before signing out
        if let userId = userId {
            try? await PushNotificationService.shared.removeDeviceToken(userId: userId)
        }
        
        try await supabase.auth.signOut()
    }
    
    /// Get current session
    func getCurrentSession() async throws -> Session? {
        do {
            return try await supabase.auth.session
        } catch {
            return nil
        }
    }

    /// Get current user profile
    func getCurrentUser() async throws -> User? {
        do {
            let session = try await supabase.auth.session

            let user: User = try await supabase.database
                .from("users")
                .select()
                .eq("id", value: session.user.id)
                .single()
                .execute()
                .value

            return user
        } catch {
            return nil
        }
    }
    
    /// Update user profile
    func updateProfile(userId: UUID, username: String?, displayName: String?, avatarUrl: String?) async throws {
        struct ProfileUpdate: Encodable {
            let username: String?
            let display_name: String?
            let avatar_url: String?
        }

        let updates = ProfileUpdate(
            username: username,
            display_name: displayName,
            avatar_url: avatarUrl
        )

        try await supabase.database
            .from("users")
            .update(updates)
            .eq("id", value: userId)
            .execute()
    }
    
    /// Update last seen timestamp
    func updateLastSeen(userId: UUID) async throws {
        struct LastSeenUpdate: Encodable {
            let last_seen: Date
        }

        try await supabase.database
            .from("users")
            .update(LastSeenUpdate(last_seen: Date()))
            .eq("id", value: userId)
            .execute()
    }

    /// Update user status
    func updateStatus(userId: UUID, status: UserStatus) async throws {
        struct StatusUpdate: Encodable {
            let status: String
        }

        try await supabase.database
            .from("users")
            .update(StatusUpdate(status: status.rawValue))
            .eq("id", value: userId)
            .execute()
    }

    /// Send password reset email
    func requestPasswordReset(email: String) async throws {
        let redirectURL = URL(string: "com.gauntletai.whatsnext://login-callback")
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
    }

    /// Complete password reset by setting a new password for the current session
    func updatePassword(newPassword: String) async throws {
        let attrs = UserAttributes(password: newPassword)
        _ = try await supabase.auth.update(user: attrs)
    }
    
    /// Register for push notifications after login
    @MainActor
    private func registerPushNotifications(userId: UUID) async {
        // Request authorization if needed
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        
        if status == .notDetermined {
            try? await PushNotificationService.shared.requestAuthorization()
        } else if status == .authorized {
            // Register for remote notifications
            await PushNotificationService.shared.registerForRemoteNotifications()
            
            // Save existing token if available
            if let token = PushNotificationService.shared.deviceToken {
                try? await PushNotificationService.shared.saveDeviceToken(userId: userId, token: token)
            }
        }
    }
}

