import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class ConversationListViewModel: ObservableObject {
    @Published public var conversations: [Conversation] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    
    private let conversationService = ConversationService()
    private let messageService = MessageService()
    private let globalRealtimeManager = GlobalRealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentUserId: UUID?
    
    // Track app lifecycle for refreshing when app returns to foreground
    public init() {
        setupAppLifecycleObserver()
        setupGlobalRealtimeObservers()
    }
    
    deinit {
        // Cleanup is handled by GlobalRealtimeManager
    }
    
    private func setupAppLifecycleObserver() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshConversationsOnForeground()
                }
            }
            .store(in: &cancellables)
        #endif
    }
    
    private func refreshConversationsOnForeground() async {
        // Only refresh if we already have conversations loaded
        guard !conversations.isEmpty else { return }
        
        // Silently refresh last messages without showing loading indicator
        await fetchLastMessages()
    }
    
    /// Fetch all conversations for current user
    public func fetchConversations(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        currentUserId = userId
        defer { isLoading = false }
        
        do {
            conversations = try await conversationService.fetchConversations(userId: userId)
            
            // Fetch last message for each conversation
            await fetchLastMessages()
            
            // Start global realtime manager if not already active
            if !globalRealtimeManager.isActive {
                do {
                    try await globalRealtimeManager.start(userId: userId, conversations: conversations)
                    print("✅ GlobalRealtimeManager started successfully")
                } catch {
                    print("⚠️ Failed to start GlobalRealtimeManager: \(error)")
                }
            } else {
                // Update global manager with conversations list
                globalRealtimeManager.updateConversations(conversations)
            }
        } catch {
            errorMessage = "Failed to load conversations"
            print("Error fetching conversations: \(error)")
        }
    }
    
    /// Fetch last message for each conversation
    func fetchLastMessages() async {
        for index in conversations.indices {
            do {
                let messages = try await messageService.fetchMessages(
                    conversationId: conversations[index].id,
                    limit: 1
                )
                if let lastMessage = messages.last {
                    conversations[index].lastMessage = lastMessage
                }
            } catch {
                print("Error fetching last message for conversation \(conversations[index].id): \(error)")
            }
        }
    }

    /// Delete conversations (swipe-to-delete)
    func deleteConversations(at offsets: IndexSet, currentUserId: UUID) async {
        let idsToDelete = offsets.compactMap { idx in
            conversations.indices.contains(idx) ? conversations[idx].id : nil
        }
        
        // Optimistic UI
        conversations.remove(atOffsets: offsets)
        
        for convId in idsToDelete {
            do {
                try await conversationService.removeParticipant(conversationId: convId, userId: currentUserId)
            } catch {
                print("Failed to delete conversation participation: \(error)")
            }
        }
    }
    
    /// Create a new direct conversation
    func createDirectConversation(currentUserId: UUID, otherUserId: UUID) async -> Conversation? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let conversation = try await conversationService.createDirectConversation(
                currentUserId: currentUserId,
                otherUserId: otherUserId
            )
            
            // Add to list if not already present
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: 0)
            }
            
            return conversation
        } catch {
            errorMessage = "Failed to create conversation"
            print("Error creating conversation: \(error)")
            return nil
        }
    }
    
    /// Create a new group conversation
    func createGroupConversation(name: String, creatorId: UUID, participantIds: [UUID]) async -> Conversation? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let conversation = try await conversationService.createGroupConversation(
                name: name,
                creatorId: creatorId,
                participantIds: participantIds
            )
            
            conversations.insert(conversation, at: 0)
            return conversation
        } catch {
            errorMessage = "Failed to create group"
            print("Error creating group: \(error)")
            return nil
        }
    }
    
    /// Get display name for a conversation
    func displayName(for conversation: Conversation, currentUserId: UUID) -> String {
        if conversation.isGroup {
            return conversation.name ?? "Group Chat"
        } else {
            // For 1:1, show other user's name
            if let otherUser = conversation.participants?.first(where: { $0.id != currentUserId }) {
                return otherUser.displayName ?? otherUser.username ?? otherUser.email ?? "Unknown User"
            }
            return "Direct Message"
        }
    }
    
    /// Get avatar URL for a conversation
    func avatarUrl(for conversation: Conversation, currentUserId: UUID) -> String? {
        if conversation.isGroup {
            return conversation.avatarUrl
        } else {
            // For 1:1, show other user's avatar
            return conversation.participants?.first(where: { $0.id != currentUserId })?.avatarUrl
        }
    }
    
    /// Setup observers for global real-time events
    private func setupGlobalRealtimeObservers() {
        // Observe all messages to update conversation list
        globalRealtimeManager.messagePublisher
            .sink { [weak self] message in
                Task { @MainActor [weak self] in
                    await self?.handleNewMessage(message)
                }
            }
            .store(in: &cancellables)
        
        // Observe conversation metadata updates
        globalRealtimeManager.conversationUpdatePublisher
            .sink { [weak self] conversation in
                Task { @MainActor [weak self] in
                    await self?.handleConversationUpdate(conversation)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Handle conversation update from realtime
    private func handleConversationUpdate(_ updated: Conversation) async {
        if let index = conversations.firstIndex(where: { $0.id == updated.id }) {
            // Update existing conversation
            var updatedConv = updated
            // Preserve existing data like participants and last message
            updatedConv.participants = conversations[index].participants
            updatedConv.lastMessage = conversations[index].lastMessage
            
            conversations[index] = updatedConv
            
            // Move to top if updated
            let conv = conversations.remove(at: index)
            conversations.insert(conv, at: 0)
            
            // Refresh last message
            await fetchLastMessage(for: conv.id)
        }
    }
    
    /// Handle new message from realtime
    private func handleNewMessage(_ message: Message) async {
        guard let userId = currentUserId else { return }
        
        // Find the conversation for this message
        if let index = conversations.firstIndex(where: { $0.id == message.conversationId }) {
            // Update last message
            conversations[index].lastMessage = message
            conversations[index].updatedAt = message.createdAt
            
            // Move to top
            let conv = conversations.remove(at: index)
            conversations.insert(conv, at: 0)
            
            // Note: Notifications are now handled by GlobalRealtimeManager
        } else {
            // New conversation - refresh list
            await fetchConversations(userId: userId)
        }
    }
    
    /// Fetch last message for a specific conversation
    private func fetchLastMessage(for conversationId: UUID) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        
        do {
            let messages = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: 1
            )
            if let lastMessage = messages.last {
                conversations[index].lastMessage = lastMessage
            }
        } catch {
            print("Error fetching last message: \(error)")
        }
    }
}

