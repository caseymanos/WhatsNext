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

    // MARK: - Google Calendar OAuth

    /// Request Google Calendar access with proper scopes
    func authorizeGoogleCalendar() async throws -> GoogleOAuthCredentials {
        print("🔵 Requesting Google Calendar authorization")

        // Configure Google Sign In
        let config = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        GIDSignIn.sharedInstance.configuration = config

        // Get the presenting view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("   ❌ No root view controller found")
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller"]))
        }

        // Request calendar scope
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        print("   Requesting scope: \(calendarScope)")

        // Check if user is already signed in
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            print("   User already signed in, requesting additional scopes")

            // Check if we already have the calendar scope
            if currentUser.grantedScopes?.contains(calendarScope) == true {
                print("   ✅ Calendar scope already granted")
                return try extractCredentials(from: currentUser)
            }

            // Request additional scopes
            do {
                let result = try await currentUser.addScopes([calendarScope], presenting: rootViewController)
                print("   ✅ Additional scopes granted")
                return try extractCredentials(from: result)
            } catch {
                print("   ❌ Failed to add scopes: \(error.localizedDescription)")
                throw AuthError.unknown(error)
            }
        } else {
            print("   No user signed in, performing full sign in with calendar scope")

            // Sign in with calendar scope
            let result: GIDSignInResult
            do {
                result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootViewController,
                    hint: nil,
                    additionalScopes: [calendarScope]
                )
                print("   ✅ User signed in with calendar scope")
                return try extractCredentials(from: result.user)
            } catch {
                print("   ❌ Google Calendar authorization failed: \(error.localizedDescription)")
                throw AuthError.unknown(error)
            }
        }
    }

    /// Extract credentials from Google user
    private func extractCredentials(from user: GIDGoogleUser) throws -> GoogleOAuthCredentials {
        guard let accessToken = user.accessToken.tokenString else {
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token"]))
        }

        guard let refreshToken = user.refreshToken.tokenString else {
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No refresh token"]))
        }

        guard let expirationDate = user.accessToken.expirationDate else {
            throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No expiration date"]))
        }

        let scope = user.grantedScopes?.joined(separator: " ") ?? "https://www.googleapis.com/auth/calendar"

        print("   Access token (first 20 chars): \(String(accessToken.prefix(20)))...")
        print("   Refresh token (first 20 chars): \(String(refreshToken.prefix(20)))...")
        print("   Expires at: \(expirationDate)")
        print("   Scopes: \(scope)")

        return GoogleOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expirationDate,
            scope: scope
        )
    }

    /// List available calendars for the user
    func listGoogleCalendars(credentials: GoogleOAuthCredentials) async throws -> [GoogleCalendar] {
        let googleService = GoogleCalendarService()
        return try await googleService.listCalendars(credentials: credentials)
    }
}
