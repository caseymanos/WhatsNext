import SwiftUI
import UIKit
import WhatsNextFeature

@main
struct WhatsNextApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var globalRealtimeManager = GlobalRealtimeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(globalRealtimeManager)
                .task {
                    // Start global realtime if the user is already authenticated on launch
                    if authViewModel.isAuthenticated {
                        await handleAuthenticationChange(isAuthenticated: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didRegisterDeviceToken)) { notification in
                    if let token = notification.object as? String {
                        Task {
                            await handleDeviceToken(token)
                        }
                    }
                }
                .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
                    Task {
                        await handleAuthenticationChange(isAuthenticated: isAuthenticated)
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    @MainActor
    private func handleDeviceToken(_ token: String) async {
        guard let userId = authViewModel.currentUser?.id else {
            print("No user logged in, skipping token save")
            return
        }

        do {
            try await PushNotificationService.shared.saveDeviceToken(userId: userId, token: token)
        } catch {
            print("Failed to save device token: \(error)")
        }
    }

    @MainActor
    private func handleAuthenticationChange(isAuthenticated: Bool) async {
        if isAuthenticated, let userId = authViewModel.currentUser?.id {
            // User logged in - start global real-time manager
            print("User logged in, starting GlobalRealtimeManager")
            
            // Fetch conversations to initialize the manager
            let conversationService = ConversationService()
            do {
                let conversations = try await conversationService.fetchConversations(userId: userId)
                try await globalRealtimeManager.start(userId: userId, conversations: conversations)
            } catch {
                print("Failed to start GlobalRealtimeManager: \(error)")
            }
        } else {
            // User logged out - stop global real-time manager
            print("User logged out, stopping GlobalRealtimeManager")
            await globalRealtimeManager.stop()
        }
    }
    
    @MainActor
    private func handleDeepLink(_ url: URL) {
        print("📱 Received deep link: \(url.absoluteString)")
        print("   Scheme: \(url.scheme ?? "none")")
        print("   Host: \(url.host ?? "none")")
        print("   Path: \(url.path)")
        print("   Query: \(url.query ?? "none")")

        // Handle OAuth callback deep links
        // Format: com.gauntletai.whatsnext://login-callback#access_token=...&refresh_token=...
        // Note: OAuth callbacks use fragment (#) not query (?)

        guard url.scheme == "com.gauntletai.whatsnext" else {
            print("⚠️ Ignoring deep link with unexpected scheme: \(url.scheme ?? "none")")
            return
        }

        Task {
            do {
                // Supabase Auth will automatically handle the session from the URL
                // This works with both query params and URL fragments
                try await SupabaseClientService.shared.auth.session(from: url)

                // Refresh the current user after OAuth login
                await authViewModel.checkAuthStatus()

                print("✅ Successfully authenticated via deep link")
            } catch {
                print("❌ Failed to handle deep link auth: \(error)")
                print("   Error details: \(error.localizedDescription)")

                // Provide user-friendly error message
                let errorMsg: String
                if let decodingError = error as? DecodingError {
                    errorMsg = "Authentication data format error. Please try again."
                    print("   Decoding error: \(decodingError)")
                } else {
                    errorMsg = "Authentication failed. Please try again."
                }

                authViewModel.errorMessage = errorMsg
            }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request push notification authorization on app launch
        Task { @MainActor in
            let status = await PushNotificationService.shared.checkAuthorizationStatus()

            // Only request if not determined yet
            if status == .notDetermined {
                try? await PushNotificationService.shared.requestAuthorization()
            } else if status == .authorized {
                await PushNotificationService.shared.registerForRemoteNotifications()
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)

            // Post notification so the app can save the token
            let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
            NotificationCenter.default.post(
                name: .didRegisterDeviceToken,
                object: tokenString
            )
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
