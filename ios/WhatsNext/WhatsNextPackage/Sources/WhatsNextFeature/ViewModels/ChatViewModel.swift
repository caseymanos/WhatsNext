import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [Message] = []
    @Published public var optimisticMessages: [String: Message] = [:] // localId -> Message
    @Published public var failedMessages: [String: Message] = [:] // localId -> Message for failed sends
    @Published public var isLoading = false
    @Published public var isSending = false
    @Published public var errorMessage: String?
    @Published public var typingUsers: [UUID] = []
    @Published public var isOnline = true

    public let conversation: Conversation
    public let currentUserId: UUID

    private let messageService = MessageService()
    private let conversationService = ConversationService()
    private let imageUploadService = ImageUploadService()
    private let globalRealtimeManager = GlobalRealtimeManager.shared
    private let messageSyncService = MessageSyncService.shared
    private let localStorage = LocalStorageService.shared
    private let networkMonitor = NetworkMonitor.shared
    private let logger = Logger(subsystem: "com.gauntletai.whatsnext", category: "ChatViewModel")
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    private var typingCheckTimer: Timer?
    private var markingAsRead = Set<UUID>() // Track messages currently being marked as read
    
    public init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId

        // Set initial network state
        self.isOnline = networkMonitor.isConnected

        // Start periodic typing check
        startTypingCheck()

        // Observe global real-time events
        setupGlobalRealtimeObservers()

        // Observe network status changes
        setupNetworkObserver()

        // Observe sync service status
        setupSyncObserver()
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

        // Always load from cache first (works offline, instant display)
        let cachedMessages = messageSyncService.fetchCachedMessages(conversationId: conversation.id)
        if !cachedMessages.isEmpty {
            messages = cachedMessages
            logger.info("Loaded \(cachedMessages.count) cached messages")
        }

        // Load pending failed messages from outbox
        do {
            let outboxMessages = try localStorage.fetchOutboxMessages()
            let conversationOutbox = outboxMessages.filter { $0.conversationId == self.conversation.id }

            for outboxMessage in conversationOutbox {
                let failedMsg = Message(
                    id: UUID(),
                    conversationId: outboxMessage.conversationId,
                    senderId: outboxMessage.senderId,
                    content: outboxMessage.content,
                    messageType: MessageType(rawValue: outboxMessage.messageType) ?? .text,
                    mediaUrl: outboxMessage.mediaUrl,
                    createdAt: outboxMessage.createdAt,
                    localId: outboxMessage.localId
                )
                failedMessages[outboxMessage.localId] = failedMsg

                // Add to messages if not already there
                if !messages.contains(where: { $0.localId == outboxMessage.localId }) {
                    messages.append(failedMsg)
                }
            }

            // Sort messages by creation date
            messages.sort { $0.createdAt < $1.createdAt }
        } catch {
            logger.error("Failed to load outbox messages: \(error.localizedDescription)")
        }

        // Try to fetch from server if online
        if isOnline {
            do {
                let serverMessages = try await messageService.fetchMessages(conversationId: conversation.id)

                // Cache all server messages
                for message in serverMessages {
                    await messageSyncService.cacheMessage(message)
                }

                // Merge with cached messages (prefer server version)
                var messageDict: [UUID: Message] = [:]

                // Start with cached messages
                for msg in messages {
                    messageDict[msg.id] = msg
                }

                // Overwrite with server messages (they're authoritative)
                for msg in serverMessages {
                    messageDict[msg.id] = msg
                }

                // Convert back to sorted array
                messages = Array(messageDict.values).sorted { $0.createdAt < $1.createdAt }

                logger.info("Loaded \(serverMessages.count) messages from server")

                // Fetch existing read receipts BEFORE displaying (prevents cascade)
                await fetchReadReceipts()

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

                // Mark messages as read now that they're loaded
                await markMessagesAsRead()

                // Sync any pending messages
                await syncPendingMessages()
            } catch {
                logger.error("Failed to load messages from server: \(error.localizedDescription)")

                // If we have cached messages, don't show error (offline mode works)
                if messages.isEmpty {
                    errorMessage = "Failed to load messages. You're offline."
                } else {
                    logger.info("Using cached messages (offline mode)")
                }
            }
        } else {
            logger.info("Offline - using \(self.messages.count) cached messages")

            // Still register as open conversation for when we come back online
            globalRealtimeManager.setOpenConversation(conversation.id)
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

    /// Setup network status observer
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                if isConnected {
                    // Network is back - trigger sync for this conversation
                    Task {
                        await self?.syncPendingMessages()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Setup sync service observer
    private func setupSyncObserver() {
        messageSyncService.$syncError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.logger.error("Sync error: \(error)")
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
        logger.info("🟣 Received read receipt for message: \(receipt.messageId.uuidString)")
        logger.info("🟣 Read by user: \(receipt.userId.uuidString)")
        logger.info("🟣 Read at: \(receipt.readAt)")

        // Find the message this receipt is for
        if let index = messages.firstIndex(where: { $0.id == receipt.messageId }) {
            logger.info("🟣 ✅ Found message at index \(index)")

            // Initialize readReceipts array if nil
            if messages[index].readReceipts == nil {
                messages[index].readReceipts = []
                logger.info("🟣 Initialized empty readReceipts array")
            }

            // Add or update the receipt
            if let existingIndex = messages[index].readReceipts?.firstIndex(where: { $0.userId == receipt.userId }) {
                // Update existing receipt
                messages[index].readReceipts?[existingIndex] = receipt
                logger.info("🟣 ✅ Updated existing receipt at index \(existingIndex)")
            } else {
                // Add new receipt
                messages[index].readReceipts?.append(receipt)
                logger.info("🟣 ✅ Added new receipt (total receipts: \(self.messages[index].readReceipts?.count ?? 0))")
            }
        } else {
            logger.warning("🟣 ❌ Message NOT found in messages array")
            logger.info("🟣 Current messages: \(self.messages.map { $0.id.uuidString }.joined(separator: ", "))")
        }
    }
    
    /// Send a text message with optimistic UI and offline support
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

            // Cache successful message locally
            await messageSyncService.cacheMessage(sentMessage)
        } catch {
            logger.error("Failed to send message: \(error.localizedDescription)")

            // Move from optimistic to failed
            optimisticMessages.removeValue(forKey: localId)
            failedMessages[localId] = optimisticMessage

            // Keep message in list but mark it as failed
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index] = optimisticMessage
                logger.info("Updated existing message to failed state at index \(index)")
            } else {
                // Message not found - re-add it (shouldn't happen but defensive)
                messages.append(optimisticMessage)
                messages.sort { $0.createdAt < $1.createdAt }
                logger.warning("Message not found in array, re-added failed message")
            }

            // Add to outbox for retry
            await messageSyncService.addToOutbox(optimisticMessage)

            errorMessage = "Message failed to send. Will retry automatically."
            logger.info("Added message to outbox for retry: \(localId)")
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

    /// Sync pending messages from outbox
    func syncPendingMessages() async {
        logger.info("Syncing pending messages for conversation: \(self.conversation.id)")

        // Get outbox messages for this conversation
        do {
            let outboxMessages = try localStorage.fetchOutboxMessages()
            let conversationOutbox = outboxMessages.filter { $0.conversationId == self.conversation.id }

            guard !conversationOutbox.isEmpty else {
                logger.info("No pending messages to sync")
                return
            }

            logger.info("Found \(conversationOutbox.count) pending messages")

            for outboxMessage in conversationOutbox {
                await retryMessage(localId: outboxMessage.localId)
            }
        } catch {
            logger.error("Failed to fetch outbox messages: \(error.localizedDescription)")
        }
    }

    /// Retry sending a specific failed message
    public func retryMessage(localId: String) async {
        guard let failedMessage = failedMessages[localId] else {
            logger.warning("Attempted to retry message that's not in failed state: \(localId)")
            return
        }

        logger.info("Retrying message: \(localId)")

        // Move from failed back to optimistic
        failedMessages.removeValue(forKey: localId)
        optimisticMessages[localId] = failedMessage

        // Update UI to show as sending
        if let index = messages.firstIndex(where: { $0.localId == localId }) {
            messages[index] = failedMessage
        }

        do {
            // Attempt to send
            let sentMessage = try await messageService.sendMessage(
                conversationId: conversation.id,
                senderId: currentUserId,
                content: failedMessage.content ?? "",
                localId: localId
            )

            // Success - remove from optimistic and outbox
            optimisticMessages.removeValue(forKey: localId)
            try localStorage.removeFromOutbox(localId: localId)

            // Replace with server message
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index] = sentMessage
            }

            // Cache successful message
            await messageSyncService.cacheMessage(sentMessage)

            logger.info("✅ Successfully retried message: \(localId)")
        } catch {
            // Failed again - move back to failed state
            optimisticMessages.removeValue(forKey: localId)
            failedMessages[localId] = failedMessage

            // Update retry count in outbox
            do {
                try localStorage.updateOutboxRetry(localId: localId, error: error.localizedDescription)
            } catch {
                logger.error("Failed to update outbox retry count: \(error.localizedDescription)")
            }

            logger.error("❌ Retry failed for message: \(localId) - \(error.localizedDescription)")
        }
    }

    /// Get sync status for a message
    public func getSyncStatus(for message: Message) -> MessageSyncStatus {
        guard let localId = message.localId else {
            return .sent
        }

        if optimisticMessages[localId] != nil {
            return .sending
        }

        if failedMessages[localId] != nil {
            return .failed
        }

        return .sent
    }
    
    /// Mark messages as read
    func markMessagesAsRead() async {
        logger.info("🔴 markMessagesAsRead called")
        logger.info("🔴 Total messages: \(self.messages.count)")
        logger.info("🔴 Current user: \(self.currentUserId.uuidString)")

        let unreadMessages = messages.filter { message in
            message.senderId != currentUserId &&
            message.readReceipts?.contains(where: { $0.userId == currentUserId }) != true &&
            !markingAsRead.contains(message.id) // Skip if already marking
        }

        logger.info("🔴 Unread messages to mark: \(unreadMessages.count)")
        if unreadMessages.isEmpty {
            logger.info("🔴 No unread messages to mark - returning early")
            return
        }

        // Track messages we're about to mark
        let messageIds = Set(unreadMessages.map { $0.id })
        markingAsRead.formUnion(messageIds)

        defer {
            // Clean up tracking when done
            markingAsRead.subtract(messageIds)
        }

        for message in unreadMessages {
            logger.info("🔴 Marking message as read: \(message.id.uuidString)")
            do {
                try await messageService.markAsRead(messageId: message.id, userId: currentUserId)
                logger.info("🔴 ✅ Successfully marked message \(message.id.uuidString) as read")

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
                    logger.info("🔴 Updated local message with read receipt")
                }
            } catch {
                logger.error("🔴 ❌ Error marking message as read: \(error.localizedDescription)")
                // On error, remove from tracking so it can be retried
                markingAsRead.remove(message.id)
            }
        }

        logger.info("🔴 markMessagesAsRead completed")
    }
    
    /// Fetch read receipts for own messages (batch operation to prevent cascade)
    func fetchReadReceipts() async {
        let ownMessages = messages.filter { $0.senderId == currentUserId }
        guard !ownMessages.isEmpty else { return }

        // Batch fetch all receipts in one query
        let messageIds = ownMessages.map { $0.id }
        do {
            let allReceipts = try await messageService.fetchReadReceiptsForMessages(messageIds: messageIds)

            // Group receipts by message ID
            let receiptsByMessage = Dictionary(grouping: allReceipts, by: { $0.messageId })

            // Update all messages at once
            for (messageId, receipts) in receiptsByMessage {
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index].readReceipts = receipts
                }
            }

            logger.info("✅ Fetched \(allReceipts.count) read receipts for \(ownMessages.count) messages in single batch")
        } catch {
            logger.error("Error batch fetching read receipts: \(error)")
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

        // Cache incoming message for offline access
        Task {
            await messageSyncService.cacheMessage(message)
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

    /// Send photos with optional caption and offline support
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

                do {
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

                    // Cache successful message
                    await messageSyncService.cacheMessage(sentMessage)
                } catch {
                    logger.error("Failed to send photo message: \(error.localizedDescription)")

                    // Move from optimistic to failed
                    optimisticMessages.removeValue(forKey: localId)
                    failedMessages[localId] = optimisticMessage

                    // Keep message in list but mark it as failed
                    if let index = messages.firstIndex(where: { $0.localId == localId }) {
                        messages[index] = optimisticMessage
                        logger.info("Updated existing photo message to failed state at index \(index)")
                    } else {
                        // Message not found - re-add it
                        messages.append(optimisticMessage)
                        messages.sort { $0.createdAt < $1.createdAt }
                        logger.warning("Photo message not found in array, re-added failed message")
                    }

                    // Add to outbox for retry
                    await messageSyncService.addToOutbox(optimisticMessage)

                    logger.info("Added photo message to outbox for retry: \(localId)")
                }
            }
        } catch {
            errorMessage = "Failed to upload photos: \(error.localizedDescription)"
            logger.error("Error uploading photos: \(error)")
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

public enum MessageSyncStatus {
    case sending
    case sent
    case failed

    var icon: String {
        switch self {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .failed: return "exclamationmark.circle"
        }
    }

    var color: String {
        switch self {
        case .sending: return "secondary"
        case .sent: return "secondary"
        case .failed: return "red"
        }
    }

    var text: String {
        switch self {
        case .sending: return "Sending..."
        case .sent: return "Sent"
        case .failed: return "Failed"
        }
    }
}

