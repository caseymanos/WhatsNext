import SwiftUI
import UIKit

@main
struct MessageAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .onReceive(NotificationCenter.default.publisher(for: .didRegisterDeviceToken)) { notification in
                    if let token = notification.object as? String {
                        Task {
                            await handleDeviceToken(token)
                        }
                    }
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

