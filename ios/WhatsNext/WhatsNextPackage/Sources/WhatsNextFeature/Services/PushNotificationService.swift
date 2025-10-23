import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
import OSLog

@MainActor
public final class PushNotificationService: NSObject {
    public static let shared = PushNotificationService()

    private let logger = Logger(subsystem: "com.gauntletai.whatsnext", category: "PushNotifications")
    private let notificationCenter = UNUserNotificationCenter.current()

    @Published public var deviceToken: String?
    @Published public var isAuthorized = false
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
    }
    
    /// Request push notification authorization
    public func requestAuthorization() async throws {
        logger.info("Requesting push notification authorization")
        
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        
        isAuthorized = granted
        
        if granted {
            logger.info("Push notification authorization granted")
            await registerForRemoteNotifications()
        } else {
            logger.warning("Push notification authorization denied")
        }
    }
    
    /// Register for remote notifications with APNs
    public func registerForRemoteNotifications() async {
        logger.info("Registering for remote notifications")
        #if canImport(UIKit)
        await UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    
    /// Handle successful device token registration
    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        logger.info("Successfully registered for remote notifications. Token: \(tokenString.prefix(8))...")
    }
    
    /// Handle device token registration failure
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    /// Save device token to Supabase
    public func saveDeviceToken(userId: UUID, token: String) async throws {
        logger.info("Saving device token to Supabase for user: \(userId.uuidString)")
        
        try await SupabaseClientService.shared.database
            .from("users")
            .update(["push_token": token])
            .eq("id", value: userId)
            .execute()
        
        logger.info("Device token saved successfully")
    }
    
    /// Remove device token from Supabase (on logout)
    func removeDeviceToken(userId: UUID) async throws {
        logger.info("Removing device token from Supabase for user: \(userId.uuidString)")

        struct PushTokenUpdate: Encodable {
            let push_token: String?
        }

        try await SupabaseClientService.shared.database
            .from("users")
            .update(PushTokenUpdate(push_token: nil))
            .eq("id", value: userId)
            .execute()

        logger.info("Device token removed successfully")
        deviceToken = nil
    }
    
    /// Check current authorization status
    public func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        return settings.authorizationStatus
    }
    
    /// Schedule a local notification for a new message (for simulator)
    public func scheduleLocalNotification(
        conversationId: UUID,
        conversationName: String,
        senderName: String,
        messageContent: String
    ) async {
        logger.info("Scheduling local notification for conversation: \(conversationId.uuidString)")
        
        let content = UNMutableNotificationContent()
        content.title = conversationName
        content.body = "\(senderName): \(messageContent)"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "conversation_id": conversationId.uuidString,
            "sender_name": senderName
        ]
        
        // Trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            logger.info("Local notification scheduled successfully")
        } catch {
            logger.error("Failed to schedule local notification: \(error.localizedDescription)")
        }
    }
    
    /// Handle notification when app is in foreground
    func handleForegroundNotification(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        logger.info("Received foreground notification: \(userInfo)")
        
        // Extract conversation ID if present
        if let conversationId = userInfo["conversation_id"] as? String {
            logger.info("Notification for conversation: \(conversationId)")
            // Post notification for app to handle (e.g., refresh conversation)
            NotificationCenter.default.post(
                name: .didReceiveMessageNotification,
                object: nil,
                userInfo: ["conversation_id": conversationId]
            )
        }
    }
    
    /// Handle notification tap (when app opened from notification)
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        logger.info("User tapped notification: \(userInfo)")
        
        // Extract conversation ID and navigate to it
        if let conversationId = userInfo["conversation_id"] as? String {
            logger.info("Opening conversation: \(conversationId)")
            NotificationCenter.default.post(
                name: .didTapNotification,
                object: nil,
                userInfo: ["conversation_id": conversationId]
            )
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleForegroundNotification(notification)
        }
        
        // Show notification banner even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification response (tap)
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationResponse(response)
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let didReceiveMessageNotification = Notification.Name("didReceiveMessageNotification")
    static let didTapNotification = Notification.Name("didTapNotification")
    static let didRegisterDeviceToken = Notification.Name("didRegisterDeviceToken")
}

