import Foundation
import AuthenticationServices
import Supabase
import CryptoKit

@MainActor
final class AppleAuthService: NSObject {
    private let supabase = SupabaseClientService.shared
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var currentNonce: String?

    /// Sign in with Apple
    func signInWithApple() async throws -> User {
        print("🍎 Starting Apple Sign In")

        // Generate a random nonce for security
        let nonce = generateRandomNonce()
        self.currentNonce = nonce
        print("   Generated nonce (first 8 chars): \(String(nonce.prefix(8)))...")

        // Request Apple Sign In authorization
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        print("   Set hashed nonce on request")

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self

        print("   Presenting Apple Sign In UI")
        // Use continuation to convert delegate callbacks to async/await
        let authorization: ASAuthorization
        do {
            authorization = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                authorizationController.performRequests()
            }
            print("   ✅ User authorized with Apple")
        } catch {
            print("   ❌ Apple authorization failed: \(error.localizedDescription)")
            throw AuthError.unknown(error)
        }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("   ❌ Invalid credential type received")
            throw AuthError.unknown(NSError(domain: "AppleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"]))
        }

        print("   User ID: \(appleIDCredential.user)")
        print("   Email: \(appleIDCredential.email ?? "none")")
        print("   Full Name: \(appleIDCredential.fullName?.givenName ?? "none") \(appleIDCredential.fullName?.familyName ?? "none")")

        guard let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            print("   ❌ Failed to extract identity token")
            throw AuthError.unknown(NSError(domain: "AppleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get identity token"]))
        }

        print("   Identity token (first 20 chars): \(String(tokenString.prefix(20)))...")

        // Sign in to Supabase with Apple identity token
        print("   Signing in to Supabase with Apple token...")
        print("   Using nonce: \(String(nonce.prefix(8)))...")
        let session: Session
        do {
            session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString,
                    nonce: nonce
                )
            )
            print("   ✅ Supabase session created for user: \(session.user.id)")
        } catch {
            print("   ❌ Supabase signInWithIdToken failed")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            print("   Error details: \(error)")

            // Try to extract more details from the error
            let nsError = error as NSError
            print("   Error domain: \(nsError.domain)")
            print("   Error code: \(nsError.code)")
            print("   Error userInfo: \(nsError.userInfo)")

            // Log underlying error if present
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                print("   Underlying error: \(underlyingError)")
            }

            throw AuthError.unknown(error)
        }

        // Get or create user profile
        return try await getOrCreateUserProfile(
            session: session,
            appleCredential: appleIDCredential
        )
    }

    private func getOrCreateUserProfile(session: Session, appleCredential: ASAuthorizationAppleIDCredential) async throws -> User {
        // Try to fetch existing user profile
        do {
            let user: User = try await supabase.database
                .from("users")
                .select()
                .eq("id", value: session.user.id)
                .single()
                .execute()
                .value

            // Update last_seen
            try? await updateLastSeen(userId: user.id)

            return user
        } catch {
            // User doesn't exist, create new profile
            let displayName: String?
            if let fullName = appleCredential.fullName {
                let firstName = fullName.givenName ?? ""
                let lastName = fullName.familyName ?? ""
                displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            } else {
                displayName = nil
            }

            let user = User(
                id: session.user.id,
                email: appleCredential.email ?? session.user.email ?? "",
                username: nil,
                displayName: displayName?.isEmpty == false ? displayName : nil,
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

            return user
        }
    }

    private func updateLastSeen(userId: UUID) async throws {
        struct LastSeenUpdate: Encodable {
            let last_seen: Date
        }

        try await supabase.database
            .from("users")
            .update(LastSeenUpdate(last_seen: Date()))
            .eq("id", value: userId)
            .execute()
    }

    /// Generate a cryptographically secure random nonce
    private func generateRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    /// Hash the nonce with SHA256
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window from the first connected scene
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first ?? ASPresentationAnchor()
    }
}
