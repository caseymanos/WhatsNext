import Foundation
import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var optimisticMessages: [String: Message] = [:] // localId -> Message
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var typingUsers: [UUID] = []
    
    let conversation: Conversation
    let currentUserId: UUID
    
    private let messageService = MessageService()
    private let conversationService = ConversationService()
    private let realtimeService = RealtimeService()
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    private var typingCheckTimer: Timer?
    private var markingAsRead = Set<UUID>() // Track messages currently being marked as read
    
    init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        
        // Start periodic typing check
        startTypingCheck()
    }
    
    deinit {
        Task { [realtimeService, conversation] in
            await realtimeService.unsubscribeFromMessages(conversationId: conversation.id)
            await realtimeService.unsubscribeFromTypingIndicators(conversationId: conversation.id)
            await realtimeService.unsubscribeFromReadReceipts(conversationId: conversation.id)
            // Clear the currently open conversation
            realtimeService.currentOpenConversationId = nil
        }
        typingCheckTimer?.invalidate()
    }
    
    /// Fetch messages for the conversation
    func fetchMessages() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            messages = try await messageService.fetchMessages(conversationId: conversation.id)
            
            // Mark conversation as read
            try await conversationService.updateLastRead(
                conversationId: conversation.id,
                userId: currentUserId
            )
            
            // Subscribe to real-time updates
            try await subscribeToRealtimeUpdates()
            
            // Mark this conversation as currently open
            realtimeService.currentOpenConversationId = conversation.id
        } catch {
            errorMessage = "Failed to load messages"
            print("Error fetching messages: \(error)")
        }
    }
    
    /// Subscribe to real-time message and typing updates
    private func subscribeToRealtimeUpdates() async throws {
        // Get conversation name for notifications
        let conversationName = getConversationName()
        
        // Subscribe to messages
        try await realtimeService.subscribeToMessages(
            conversationId: conversation.id,
            currentUserId: currentUserId,
            conversationName: conversationName
        ) { [weak self] message in
            Task { @MainActor in
                self?.handleIncomingMessage(message)
            }
        }
        
        // Subscribe to typing indicators
        try await realtimeService.subscribeToTypingIndicators(
            conversationId: conversation.id,
            excludeUserId: currentUserId
        ) { [weak self] indicator in
            Task { @MainActor in
                self?.handleTypingIndicator(indicator)
            }
        }
        
        // Subscribe to read receipts
        try await realtimeService.subscribeToReadReceipts(
            conversationId: conversation.id
        ) { [weak self] receipt in
            Task { @MainActor in
                self?.handleReadReceipt(receipt)
            }
        }
    }
    
    /// Get conversation display name
    private func getConversationName() -> String {
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
    
    /// Start periodic check for expired typing indicators
    private func startTypingCheck() {
        typingCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkTypingExpiration()
            }
        }
    }
    
    /// Check and remove expired typing indicators
    private func checkTypingExpiration() async {
        let fiveSecondsAgo = Date().addingTimeInterval(-5)
        typingUsers.removeAll { userId in
            // In a real implementation, we'd track timestamps per user
            // For now, we'll fetch fresh indicators
            false
        }
        
        // Fetch current typing indicators
        await fetchTypingIndicators()
    }
    
    /// Handle incoming typing indicator
    private func handleTypingIndicator(_ indicator: TypingIndicator) {
        if !typingUsers.contains(indicator.userId) {
            typingUsers.append(indicator.userId)
        }
    }
    
    /// Handle read receipt from realtime
    private func handleReadReceipt(_ receipt: ReadReceipt) {
        // Find the message this receipt is for
        if let index = messages.firstIndex(where: { $0.id == receipt.messageId }) {
            // Initialize readReceipts array if nil
            if messages[index].readReceipts == nil {
                messages[index].readReceipts = []
            }
            
            // Add or update the receipt
            if let existingIndex = messages[index].readReceipts?.firstIndex(where: { $0.userId == receipt.userId }) {
                // Update existing receipt
                messages[index].readReceipts?[existingIndex] = receipt
            } else {
                // Add new receipt
                messages[index].readReceipts?.append(receipt)
            }
        }
    }
    
    /// Send a text message with optimistic UI
    func sendMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let localId = UUID().uuidString
        
        // Create optimistic message
        let optimisticMessage = Message(
            id: UUID(),
            conversationId: conversation.id,
            senderId: currentUserId,
            content: content,
            messageType: .text,
            mediaUrl: nil,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil,
            localId: localId
        )
        
        // Add to optimistic messages
        optimisticMessages[localId] = optimisticMessage
        
        // Add to messages list for immediate display
        messages.append(optimisticMessage)
        
        isSending = true
        defer { isSending = false }
        
        do {
            // Send to server
            let sentMessage = try await messageService.sendMessage(
                conversationId: conversation.id,
                senderId: currentUserId,
                content: content,
                localId: localId
            )
            
            // Remove optimistic message
            optimisticMessages.removeValue(forKey: localId)
            
            // Replace optimistic message with real one
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index] = sentMessage
            }
        } catch {
            // Remove optimistic message on error
            optimisticMessages.removeValue(forKey: localId)
            messages.removeAll { $0.localId == localId }
            
            errorMessage = "Failed to send message"
            print("Error sending message: \(error)")
        }
    }
    
    /// Delete a message
    func deleteMessage(_ message: Message) async {
        do {
            try await messageService.deleteMessage(messageId: message.id)
            messages.removeAll { $0.id == message.id }
        } catch {
            errorMessage = "Failed to delete message"
            print("Error deleting message: \(error)")
        }
    }
    
    /// Mark messages as read
    func markMessagesAsRead() async {
        let unreadMessages = messages.filter { message in
            message.senderId != currentUserId &&
            message.readReceipts?.contains(where: { $0.userId == currentUserId }) != true &&
            !markingAsRead.contains(message.id) // Skip if already marking
        }
        
        // Track messages we're about to mark
        let messageIds = Set(unreadMessages.map { $0.id })
        markingAsRead.formUnion(messageIds)
        
        defer {
            // Clean up tracking when done
            markingAsRead.subtract(messageIds)
        }
        
        for message in unreadMessages {
            do {
                try await messageService.markAsRead(messageId: message.id, userId: currentUserId)
                
                // Update local message with read receipt
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    var updatedMessage = messages[index]
                    let receipt = ReadReceipt(
                        messageId: message.id,
                        userId: currentUserId,
                        readAt: Date()
                    )
                    if updatedMessage.readReceipts == nil {
                        updatedMessage.readReceipts = [receipt]
                    } else {
                        updatedMessage.readReceipts?.append(receipt)
                    }
                    messages[index] = updatedMessage
                }
            } catch {
                print("Error marking message as read: \(error)")
                // On error, remove from tracking so it can be retried
                markingAsRead.remove(message.id)
            }
        }
    }
    
    /// Fetch read receipts for own messages
    func fetchReadReceipts() async {
        let ownMessages = messages.filter { $0.senderId == currentUserId }
        
        for message in ownMessages {
            do {
                let receipts = try await messageService.fetchReadReceipts(messageId: message.id)
                
                // Update message with receipts
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].readReceipts = receipts
                }
            } catch {
                print("Error fetching read receipts: \(error)")
            }
        }
    }
    
    /// Get read receipt status for a message
    func getReceiptStatus(for message: Message) -> MessageReceiptStatus {
        guard message.senderId == currentUserId else {
            return .none
        }
        
        let receipts = message.readReceipts ?? []
        
        // For 1:1 conversations, check if other user has read
        if !conversation.isGroup {
            if receipts.contains(where: { $0.userId != currentUserId }) {
                return .read
            }
            return .delivered
        }
        
        // For groups, show if anyone has read
        if !receipts.isEmpty {
            let readCount = receipts.filter { $0.userId != currentUserId }.count
            let participantCount = (conversation.participants?.count ?? 0) - 1
            
            if readCount == participantCount && participantCount > 0 {
                return .readByAll
            } else if readCount > 0 {
                return .readBySome(readCount)
            }
        }
        
        return .delivered
    }

    /// Send typing indicator
    func sendTypingIndicator() async {
        do {
            try await messageService.updateTypingIndicator(
                conversationId: conversation.id,
                userId: currentUserId
            )
        } catch {
            print("Error sending typing indicator: \(error)")
        }
    }

    /// Fetch typing indicators
    func fetchTypingIndicators() async {
        do {
            let indicators = try await messageService.fetchTypingIndicators(
                conversationId: conversation.id,
                excludeUserId: currentUserId
            )
            typingUsers = indicators.map { $0.userId }
        } catch {
            print("Error fetching typing indicators: \(error)")
        }
    }

    /// Handle incoming message (from realtime)
    func handleIncomingMessage(_ message: Message) {
        // Check if message already exists (deduplicate)
        guard !messages.contains(where: { $0.id == message.id }) else { return }

        // If there's an optimistic message with same localId, replace it
        if let localId = message.localId,
           let index = messages.firstIndex(where: { $0.localId == localId }) {
            messages[index] = message
            optimisticMessages.removeValue(forKey: localId)
        } else {
            // Add new message
            messages.append(message)
        }

        // Mark as read if conversation is open
        Task {
            await markMessagesAsRead()
        }
    }

    /// Load more messages (pagination)
    func loadMoreMessages() async {
        guard let oldestMessage = messages.first else { return }

        do {
            let olderMessages = try await messageService.fetchMessages(
                conversationId: conversation.id,
                limit: 50,
                before: oldestMessage.createdAt
            )

            messages.insert(contentsOf: olderMessages, at: 0)
        } catch {
            print("Error loading more messages: \(error)")
        }
    }
}

enum MessageReceiptStatus {
    case none
    case sent
    case delivered
    case read
    case readByAll
    case readBySome(Int)

    var icon: String {
        switch self {
        case .none: return ""
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read, .readByAll: return "checkmark.circle.fill"
        case .readBySome: return "checkmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .none, .sent, .delivered: return "secondary"
        case .read, .readByAll, .readBySome: return "blue"
        }
    }
}

