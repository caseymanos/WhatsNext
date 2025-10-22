import Foundation
import Supabase

enum UserServiceError: LocalizedError {
    case usernameTaken
    case usernameInvalid
    case updateFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .usernameTaken:
            return "This username is already taken"
        case .usernameInvalid:
            return "Username must be 3-20 characters and contain only letters, numbers, and underscores"
        case .updateFailed(let error):
            return "Failed to update profile: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class UserService {
    private let supabase = SupabaseClientService.shared

    /// Check if a username is available
    func checkUsernameAvailability(username: String, excludeUserId: UUID? = nil) async throws -> Bool {
        do {
            var query = supabase.database
                .from("users")
                .select("id")
                .eq("username", value: username)

            // Exclude current user if updating their own username
            if let userId = excludeUserId {
                query = query.neq("id", value: userId)
            }

            let response: [User] = try await query.execute().value
            return response.isEmpty
        } catch {
            throw UserServiceError.networkError(error)
        }
    }

    /// Validate username format
    func validateUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must be 3-20 characters
        guard trimmed.count >= 3 && trimmed.count <= 20 else {
            return false
        }

        // Only alphanumeric and underscore
        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: trimmed)
    }

    /// Update user's username
    func updateUsername(userId: UUID, username: String) async throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate format
        guard validateUsername(trimmed) else {
            throw UserServiceError.usernameInvalid
        }

        // Check availability
        let isAvailable = try await checkUsernameAvailability(username: trimmed, excludeUserId: userId)
        guard isAvailable else {
            throw UserServiceError.usernameTaken
        }

        // Update in database
        do {
            try await supabase.database
                .from("users")
                .update(["username": trimmed])
                .eq("id", value: userId)
                .execute()
        } catch {
            throw UserServiceError.updateFailed(error)
        }
    }

    /// Update user's display name
    func updateDisplayName(userId: UUID, displayName: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Display name can be empty (will show username instead)
        // But if provided, should be 1-50 characters
        if !trimmed.isEmpty && (trimmed.count < 1 || trimmed.count > 50) {
            throw UserServiceError.usernameInvalid
        }

        do {
            try await supabase.database
                .from("users")
                .update(["display_name": trimmed.isEmpty ? nil : trimmed])
                .eq("id", value: userId)
                .execute()
        } catch {
            throw UserServiceError.updateFailed(error)
        }
    }

    /// Fetch updated user profile
    func fetchUser(userId: UUID) async throws -> User {
        do {
            let user: User = try await supabase.database
                .from("users")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            return user
        } catch {
            throw UserServiceError.networkError(error)
        }
    }
}
