import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [Message] = []
    @Published public var optimisticMessages: [String: Message] = [:] // localId -> Message
    @Published public var isLoading = false
    @Published public var isSending = false
    @Published public var errorMessage: String?
    @Published public var typingUsers: [UUID] = []
    
    public let conversation: Conversation
    public let currentUserId: UUID
    
    private let messageService = MessageService()
    private let conversationService = ConversationService()
    private let imageUploadService = ImageUploadService()
    private let globalRealtimeManager = GlobalRealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    private var typingCheckTimer: Timer?
    private var markingAsRead = Set<UUID>() // Track messages currently being marked as read
    
    public init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        
        // Start periodic typing check
        startTypingCheck()
        
        // Observe global real-time events
        setupGlobalRealtimeObservers()
    }
    
    deinit {
        // Clean up synchronously - no async work in deinit
        typingCheckTimer?.invalidate()
        
        // Unregister this conversation as currently open (synchronous)
        globalRealtimeManager.setOpenConversation(nil)
        
        // Schedule async cleanup without capturing self
        let conversationId = conversation.id
        let manager = globalRealtimeManager
        Task.detached {
            await manager.unsubscribeFromTyping(conversationId: conversationId)
            await manager.unsubscribeFromReadReceipts(conversationId: conversationId)
        }
    }
    
    /// Fetch messages for the conversation
    public func fetchMessages() async {
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
            
            // Register this conversation as currently open
            globalRealtimeManager.setOpenConversation(conversation.id)
            
            // Subscribe to conversation-specific events (typing, read receipts)
            try await globalRealtimeManager.subscribeToTyping(conversationId: conversation.id)
            try await globalRealtimeManager.subscribeToReadReceipts(conversationId: conversation.id)
        } catch {
            errorMessage = "Failed to load messages"
            print("Error fetching messages: \(error)")
        }
    }
    
    /// Setup observers for global real-time events
    private func setupGlobalRealtimeObservers() {
        // Observe incoming messages for this conversation
        globalRealtimeManager.messagePublisher
            .filter { [weak self] message in
                message.conversationId == self?.conversation.id
            }
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
        
        // Observe typing indicators for this conversation
        globalRealtimeManager.typingPublisher
            .filter { [weak self] indicator in
                indicator.conversationId == self?.conversation.id
            }
            .sink { [weak self] indicator in
                self?.handleTypingIndicator(indicator)
            }
            .store(in: &cancellables)
        
        // Observe read receipts for this conversation
        globalRealtimeManager.readReceiptPublisher
            .filter { [weak self] receipt in
                // Check if this receipt is for any message in this conversation
                self?.messages.contains(where: { $0.id == receipt.messageId }) ?? false
            }
            .sink { [weak self] receipt in
                self?.handleReadReceipt(receipt)
            }
            .store(in: &cancellables)
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

    /// Send photos with optional caption
    func sendPhotos(_ images: [UIImage], caption: String?) async {
        guard !images.isEmpty else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            // Upload photos in parallel
            let photoUrls = try await imageUploadService.uploadMessagePhotos(
                userId: currentUserId,
                conversationId: conversation.id,
                images: images
            )

            // Send a message for each photo
            for photoUrl in photoUrls {
                let localId = UUID().uuidString

                // Create optimistic message
                let optimisticMessage = Message(
                    id: UUID(),
                    conversationId: conversation.id,
                    senderId: currentUserId,
                    content: caption,
                    messageType: .image,
                    mediaUrl: photoUrl,
                    createdAt: Date(),
                    updatedAt: nil,
                    deletedAt: nil,
                    localId: localId
                )

                // Add to optimistic messages
                optimisticMessages[localId] = optimisticMessage
                messages.append(optimisticMessage)

                // Send to server
                let sentMessage = try await messageService.sendMediaMessage(
                    conversationId: conversation.id,
                    senderId: currentUserId,
                    messageType: .image,
                    mediaUrl: photoUrl,
                    content: caption,
                    localId: localId
                )

                // Replace optimistic message with real one
                optimisticMessages.removeValue(forKey: localId)
                if let index = messages.firstIndex(where: { $0.localId == localId }) {
                    messages[index] = sentMessage
                }
            }
        } catch {
            errorMessage = "Failed to send photos: \(error.localizedDescription)"
            print("Error sending photos: \(error)")
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

