import Foundation
import GoogleSignIn
import Supabase

@MainActor
final class GoogleAuthService {
    private let supabase = SupabaseClientService.shared

    // Google Cloud iOS Client ID (for the Google Sign In SDK)
    private let clientID = "169626497145-pbp5d35n4q8atod0ltp96jkllkrck91e.apps.googleusercontent.com"

    // Google Cloud Web Client ID (for Supabase validation)
    private let serverClientID = "169626497145-480k40j56rc3ufluv8i8o6sr2cp5gki0.apps.googleusercontent.com"

    /// Sign in with Google
    func signInWithGoogle() async throws -> User {
        print("🔵 Starting Google Sign In")
        print("   iOS Client ID: \(String(clientID.prefix(20)))...")
        print("   Web Client ID: \(String(serverClientID.prefix(20)))...")

        // Configure Google Sign In with both client IDs
        // serverClientId is needed for Supabase to validate the token
        let config = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        GIDSignIn.sharedInstance.configuration = config
        print("   Google Sign In configured with both client IDs")

        // Get the presenting view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("   ❌ No root view controller found")
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller"]))
        }

        print("   Presenting Google Sign In UI")
        // Sign in with Google
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            print("   ✅ User signed in with Google")
            print("   User ID: \(result.user.userID ?? "none")")
            print("   Email: \(result.user.profile?.email ?? "none")")
            print("   Name: \(result.user.profile?.name ?? "none")")
        } catch {
            print("   ❌ Google sign in failed: \(error.localizedDescription)")
            throw AuthError.unknown(error)
        }

        guard let idToken = result.user.idToken?.tokenString else {
            print("   ❌ Failed to get ID token from Google")
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"]))
        }

        print("   ID token (first 20 chars): \(String(idToken.prefix(20)))...")

        // Sign in to Supabase with Google ID token
        print("   Signing in to Supabase with Google token...")
        let session: Session
        do {
            session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken
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
            googleUser: result.user
        )
    }

    private func getOrCreateUserProfile(session: Session, googleUser: GIDGoogleUser) async throws -> User {
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
            let profile = googleUser.profile

            let user = User(
                id: session.user.id,
                email: profile?.email ?? session.user.email ?? "",
                username: nil,
                displayName: profile?.name,
                avatarUrl: profile?.imageURL(withDimension: 200)?.absoluteString,
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

    /// Sign out from Google
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}
