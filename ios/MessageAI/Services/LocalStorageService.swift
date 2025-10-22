import Foundation
import SwiftData

@MainActor
final class LocalStorageService {
    static let shared = LocalStorageService()
    
    let container: ModelContainer
    let context: ModelContext
    
    private init() {
        let schema = Schema([
            LocalMessage.self,
            LocalConversation.self,
            OutboxMessage.self
        ])
        
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    // MARK: - Messages
    
    /// Save a message locally
    func saveMessage(_ message: Message) throws {
        let localMessage = LocalMessage.from(message)
        context.insert(localMessage)
        try context.save()
    }
    
    /// Fetch local messages for a conversation
    func fetchMessages(conversationId: UUID) throws -> [LocalMessage] {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.conversationId == conversationId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
    
    /// Delete a local message
    func deleteMessage(id: UUID) throws {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.id == id }
        )
        if let message = try context.fetch(descriptor).first {
            context.delete(message)
            try context.save()
        }
    }
    
    /// Update message sync status
    func updateMessageSyncStatus(localId: String, status: String, error: String? = nil) throws {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.localId == localId }
        )
        if let message = try context.fetch(descriptor).first {
            message.syncStatus = status
            message.lastSyncAttempt = Date()
            message.syncError = error
            try context.save()
        }
    }
    
    // MARK: - Conversations
    
    /// Save a conversation locally
    func saveConversation(_ conversation: Conversation) throws {
        let localConversation = LocalConversation.from(conversation)
        context.insert(localConversation)
        try context.save()
    }
    
    /// Fetch all local conversations
    func fetchConversations() throws -> [LocalConversation] {
        let descriptor = FetchDescriptor<LocalConversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
    
    /// Update conversation metadata
    func updateConversation(id: UUID, lastMessage: Message?) throws {
        let descriptor = FetchDescriptor<LocalConversation>(
            predicate: #Predicate { $0.id == id }
        )
        if let conversation = try context.fetch(descriptor).first {
            conversation.lastMessageContent = lastMessage?.content
            conversation.lastMessageDate = lastMessage?.createdAt
            conversation.updatedAt = Date()
            try context.save()
        }
    }
    
    // MARK: - Outbox
    
    /// Add message to outbox
    func addToOutbox(_ message: Message) throws {
        let outboxMessage = OutboxMessage(
            localId: message.localId ?? UUID().uuidString,
            conversationId: message.conversationId,
            senderId: message.senderId,
            content: message.content ?? "",
            messageType: message.messageType.rawValue,
            mediaUrl: message.mediaUrl,
            createdAt: message.createdAt
        )
        context.insert(outboxMessage)
        try context.save()
    }
    
    /// Fetch all outbox messages
    func fetchOutboxMessages() throws -> [OutboxMessage] {
        let descriptor = FetchDescriptor<OutboxMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
    
    /// Remove message from outbox
    func removeFromOutbox(localId: String) throws {
        let descriptor = FetchDescriptor<OutboxMessage>(
            predicate: #Predicate { $0.localId == localId }
        )
        if let message = try context.fetch(descriptor).first {
            context.delete(message)
            try context.save()
        }
    }
    
    /// Update outbox retry count
    func updateOutboxRetry(localId: String, error: String) throws {
        let descriptor = FetchDescriptor<OutboxMessage>(
            predicate: #Predicate { $0.localId == localId }
        )
        if let message = try context.fetch(descriptor).first {
            message.retryCount += 1
            message.lastRetryAt = Date()
            message.error = error
            try context.save()
        }
    }
    
    // MARK: - Clear Cache
    
    /// Clear all local data
    func clearAll() throws {
        try context.delete(model: LocalMessage.self)
        try context.delete(model: LocalConversation.self)
        try context.delete(model: OutboxMessage.self)
        try context.save()
    }
}

