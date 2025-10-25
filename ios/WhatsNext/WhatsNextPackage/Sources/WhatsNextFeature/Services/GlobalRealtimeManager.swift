import Foundation
import Combine
import UIKit
import OSLog

/// Global real-time manager that maintains persistent connections throughout user session
/// Similar to WhatsApp's architecture - single source of truth for all real-time events
@MainActor
public final class GlobalRealtimeManager: ObservableObject {
    public static let shared = GlobalRealtimeManager()
    
    private let logger = Logger(subsystem: "com.gauntletai.whatsnext", category: "GlobalRealtimeManager")
    
    // Combine publishers for broadcasting real-time events
    public let messagePublisher = PassthroughSubject<Message, Never>()
    public let conversationUpdatePublisher = PassthroughSubject<Conversation, Never>()
    public let typingPublisher = PassthroughSubject<TypingIndicator, Never>()
    public let readReceiptPublisher = PassthroughSubject<ReadReceipt, Never>()
    
    // State tracking
    @Published public var isActive = false
    @Published public var currentOpenConversationId: UUID?
    private var currentUserId: UUID?
    
    // Services
    private let realtimeService = RealtimeService()
    private let conversationService = ConversationService()
    private let userService = UserService()
    
    // Store conversations for notification context
    private var conversations: [UUID: Conversation] = [:]
    
    private init() {
        logger.info("GlobalRealtimeManager initialized")
    }
    
    /// Start global real-time subscriptions for a user
    public func start(userId: UUID, conversations: [Conversation]) async throws {
        guard !isActive else {
            logger.warning("GlobalRealtimeManager already active")
            return
        }
        
        logger.info("Starting GlobalRealtimeManager for user: \(userId.uuidString)")
        logger.info("Conversations count: \(conversations.count)")
        
        self.currentUserId = userId
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        
        // Subscribe to all messages across all user conversations
        do {
            try await subscribeToAllMessages(userId: userId)
            logger.info("✅ Messages subscription successful")
        } catch {
            logger.error("❌ Messages subscription failed: \(error.localizedDescription)")
            throw error
        }
        
        // Subscribe to conversation metadata updates
        do {
            try await subscribeToConversationUpdates(userId: userId)
            logger.info("✅ Conversation updates subscription successful")
        } catch {
            logger.error("❌ Conversation updates subscription failed: \(error.localizedDescription)")
            throw error
        }
        
        isActive = true
        logger.info("GlobalRealtimeManager started successfully")
    }
    
    /// Stop all global subscriptions
    public func stop() async {
        guard isActive else { return }
        
        logger.info("Stopping GlobalRealtimeManager")
        
        await realtimeService.cleanup()
        
        currentUserId = nil
        currentOpenConversationId = nil
        conversations.removeAll()
        isActive = false
        
        logger.info("GlobalRealtimeManager stopped")
    }
    
    /// Set which conversation is currently open (for notification filtering)
    nonisolated public func setOpenConversation(_ conversationId: UUID?) {
        Task { @MainActor in
            logger.debug("Setting open conversation: \(conversationId?.uuidString ?? "nil")")
            currentOpenConversationId = conversationId
            realtimeService.currentOpenConversationId = conversationId
        }
    }
    
    /// Update conversations cache (called when conversation list refreshes)
    public func updateConversations(_ conversations: [Conversation]) {
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        logger.debug("Updated conversations cache: \(conversations.count) conversations")
    }
    
    /// Subscribe to typing indicators for a specific conversation
    public func subscribeToTyping(conversationId: UUID) async throws {
        guard let userId = currentUserId else { return }
        
        try await realtimeService.subscribeToTypingIndicators(
            conversationId: conversationId,
            excludeUserId: userId
        ) { [weak self] indicator in
            Task { @MainActor [weak self] in
                self?.typingPublisher.send(indicator)
            }
        }
    }
    
    /// Unsubscribe from typing indicators for a conversation
    public func unsubscribeFromTyping(conversationId: UUID) async {
        await realtimeService.unsubscribeFromTypingIndicators(conversationId: conversationId)
    }
    
    /// Subscribe to read receipts for a specific conversation
    public func subscribeToReadReceipts(conversationId: UUID) async throws {
        try await realtimeService.subscribeToReadReceipts(conversationId: conversationId) { [weak self] receipt in
            Task { @MainActor [weak self] in
                self?.readReceiptPublisher.send(receipt)
            }
        }
    }
    
    /// Unsubscribe from read receipts for a conversation
    public func unsubscribeFromReadReceipts(conversationId: UUID) async {
        await realtimeService.unsubscribeFromReadReceipts(conversationId: conversationId)
    }
    
    // MARK: - Private Methods
    
    /// Subscribe to all messages across all user conversations
    private func subscribeToAllMessages(userId: UUID) async throws {
        try await realtimeService.subscribeToAllMessages(userId: userId) { [weak self] message in
            Task { @MainActor [weak self] in
                await self?.handleIncomingMessage(message)
            }
        }
    }
    
    /// Subscribe to conversation metadata updates
    private func subscribeToConversationUpdates(userId: UUID) async throws {
        try await realtimeService.subscribeToConversationUpdates(userId: userId) { [weak self] conversation in
            Task { @MainActor [weak self] in
                self?.handleConversationUpdate(conversation)
            }
        }
    }
    
    /// Handle incoming message from real-time subscription
    private func handleIncomingMessage(_ message: Message) async {
        logger.info("🔵 Message received: \(message.id.uuidString) in conversation: \(message.conversationId.uuidString)")
        logger.info("🔵 Conversations registered in cache: \(self.conversations.keys.count)")
        logger.info("🔵 Conversation IDs: \(self.conversations.keys.map { $0.uuidString }.joined(separator: ", "))")

        // Client-side filter: Verify message belongs to user's conversations
        let isMember = isUserMemberOfConversation(message.conversationId)
        logger.info("🔵 Is user member of conversation \(message.conversationId.uuidString)? \(isMember)")

        guard isMember else {
            logger.warning("❌ FILTERED OUT message for non-member conversation: \(message.conversationId.uuidString)")
            return
        }

        // Fetch sender information for realtime messages (since they don't include joins)
        var enrichedMessage = message
        if enrichedMessage.sender == nil {
            do {
                let sender = try await userService.fetchUser(userId: message.senderId)
                enrichedMessage.sender = sender
                logger.info("🔵 ✅ Fetched sender info: \(sender.displayName ?? sender.username ?? "unknown")")
            } catch {
                logger.error("🔵 ❌ Failed to fetch sender: \(error.localizedDescription)")
            }
        }

        // Broadcast message to all observers
        logger.info("🔵 ✅ Broadcasting message to observers -> conv=\(enrichedMessage.conversationId.uuidString) id=\(enrichedMessage.id.uuidString)")
        messagePublisher.send(enrichedMessage)

        // Show notification if appropriate
        await showAppropriateNotification(for: enrichedMessage)
    }
    
    /// Handle conversation metadata update
    private func handleConversationUpdate(_ conversation: Conversation) {
        logger.debug("Received conversation update: \(conversation.id.uuidString)")
        
        // Client-side filter: Verify user is a participant
        guard isUserMemberOfConversation(conversation.id) else {
            logger.warning("Filtered out update for non-member conversation: \(conversation.id.uuidString)")
            return
        }
        
        // Update local cache
        conversations[conversation.id] = conversation
        
        // Broadcast to observers
        logger.debug("[GRM] Broadcasting conversation update -> conv=\(conversation.id)")
        conversationUpdatePublisher.send(conversation)
    }
    
    /// Check if user is member of a conversation
    private func isUserMemberOfConversation(_ conversationId: UUID) -> Bool {
        return conversations.keys.contains(conversationId)
    }
    
    /// Show appropriate notification based on app state and current context
    private func showAppropriateNotification(for message: Message) async {
        logger.info("🟠 Notification check for message: \(message.id.uuidString)")

        guard let userId = currentUserId else {
            logger.info("🟠 ⏭️ No current user - skipping notification")
            return
        }

        // Don't notify for own messages
        guard message.senderId != userId else {
            logger.info("🟠 ⏭️ Skipping notification - own message: \(message.id.uuidString)")
            return
        }

        // Don't notify if this conversation is currently open
        if currentOpenConversationId == message.conversationId {
            logger.info("🟠 ⏭️ Skipping notification - conversation \(message.conversationId.uuidString) is currently OPEN")
            return
        }

        // Get sender name from the enriched message
        let senderName = message.sender?.displayName
            ?? message.sender?.username
            ?? "Someone"

        // Get conversation name (use sender name for 1:1, group name for groups)
        let conversation = conversations[message.conversationId]
        let conversationName: String
        if let conv = conversation, conv.isGroup {
            conversationName = conv.name ?? "Group Chat"
        } else {
            // For 1:1, use sender's name as conversation name
            conversationName = senderName
        }

        let messageContent = message.content ?? "[Media]"

        // Check app state
        let appState = UIApplication.shared.applicationState
        let appStateString = appState == .active ? "active (foreground)" : appState == .background ? "background" : "inactive"

        logger.info("🟠 App state: \(appStateString) (\(appState.rawValue))")
        logger.info("🟠 Currently open conversation: \(self.currentOpenConversationId?.uuidString ?? "none")")

        if appState == .active {
            // App is in foreground - show in-app banner
            logger.info("🟠 ✅ SHOWING IN-APP BANNER for: \(conversationName)")
            InAppBannerManager.shared.showBanner(
                conversationId: message.conversationId,
                conversationName: conversationName,
                senderName: senderName,
                messageContent: messageContent
            )
        } else {
            // App is in background or inactive - send local notification
            logger.info("🟠 ✅ SCHEDULING LOCAL NOTIFICATION for: \(conversationName)")
            await PushNotificationService.shared.scheduleLocalNotification(
                conversationId: message.conversationId,
                conversationName: conversationName,
                senderName: senderName,
                messageContent: messageContent
            )
        }
    }
    
    /// Get display name for conversation
    private func getConversationName(for conversation: Conversation?, currentUserId: UUID) -> String {
        guard let conversation = conversation else {
            return "Chat"
        }
        
        if conversation.isGroup {
            return conversation.name ?? "Group Chat"
        } else {
            // For 1:1, show other user's name
            if let otherUser = conversation.participants?.first(where: { $0.id != currentUserId }) {
                return otherUser.displayName ?? otherUser.username ?? "Direct Message"
            }
            return "Direct Message"
        }
    }
}

