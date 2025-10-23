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
        
        self.currentUserId = userId
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        
        // Subscribe to all messages across all user conversations
        try await subscribeToAllMessages(userId: userId)
        
        // Subscribe to conversation metadata updates
        try await subscribeToConversationUpdates(userId: userId)
        
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
        logger.debug("Received message: \(message.id.uuidString) in conversation: \(message.conversationId.uuidString)")
        
        // Broadcast message to all observers
        logger.debug("[GRM] onMessage -> conv=\(message.conversationId) id=\(message.id)")
        messagePublisher.send(message)
        
        // Show notification if appropriate
        await showAppropriateNotification(for: message)
    }
    
    /// Handle conversation metadata update
    private func handleConversationUpdate(_ conversation: Conversation) {
        logger.debug("Received conversation update: \(conversation.id.uuidString)")
        
        // Update local cache
        conversations[conversation.id] = conversation
        
        // Broadcast to observers
        conversationUpdatePublisher.send(conversation)
    }
    
    /// Show appropriate notification based on app state and current context
    private func showAppropriateNotification(for message: Message) async {
        guard let userId = currentUserId else { return }
        
        // Don't notify for own messages
        guard message.senderId != userId else {
            logger.debug("Skipping notification for own message")
            return
        }
        
        // Don't notify if this conversation is currently open
        if currentOpenConversationId == message.conversationId {
            logger.debug("Skipping notification - conversation is open")
            return
        }
        
        // Get conversation for context
        let conversation = conversations[message.conversationId]
        let conversationName = getConversationName(for: conversation, currentUserId: userId)
        let senderName = message.sender?.displayName 
            ?? message.sender?.username 
            ?? "Someone"
        let messageContent = message.content ?? "[Media]"
        
        // Check app state
        let appState = UIApplication.shared.applicationState
        
        logger.info("Showing notification for message. App state: \(appState.rawValue), conversation open: \(self.currentOpenConversationId?.uuidString ?? "none")")
        
        if appState == .active {
            // App is in foreground - show in-app banner
            InAppBannerManager.shared.showBanner(
                conversationId: message.conversationId,
                conversationName: conversationName,
                senderName: senderName,
                messageContent: messageContent
            )
            logger.debug("Showing in-app banner")
        } else {
            // App is in background or inactive - send local notification
            await PushNotificationService.shared.scheduleLocalNotification(
                conversationId: message.conversationId,
                conversationName: conversationName,
                senderName: senderName,
                messageContent: messageContent
            )
            logger.debug("Scheduled local notification")
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

