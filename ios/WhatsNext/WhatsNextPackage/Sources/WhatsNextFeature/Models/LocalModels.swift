import Foundation
import SwiftData

/// Local cached message for offline support
@Model
final class LocalMessage {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var senderId: UUID
    var content: String?
    var messageType: String
    var mediaUrl: String?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var localId: String?
    
    // Offline sync state
    var syncStatus: String // "synced", "pending", "failed"
    var lastSyncAttempt: Date?
    var syncError: String?
    
    init(
        id: UUID,
        conversationId: UUID,
        senderId: UUID,
        content: String?,
        messageType: String,
        mediaUrl: String?,
        createdAt: Date,
        updatedAt: Date?,
        deletedAt: Date?,
        localId: String?,
        syncStatus: String = "pending",
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.localId = localId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }
    
    /// Convert from remote Message to LocalMessage
    static func from(_ message: Message) -> LocalMessage {
        LocalMessage(
            id: message.id,
            conversationId: message.conversationId,
            senderId: message.senderId,
            content: message.content,
            messageType: message.messageType.rawValue,
            mediaUrl: message.mediaUrl,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            deletedAt: message.deletedAt,
            localId: message.localId,
            syncStatus: "synced"
        )
    }
    
    /// Convert to remote Message
    func toMessage() -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            messageType: MessageType(rawValue: messageType) ?? .text,
            mediaUrl: mediaUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            localId: localId
        )
    }
}

/// Local cached conversation
@Model
final class LocalConversation {
    @Attribute(.unique) var id: UUID
    var name: String?
    var avatarUrl: String?
    var isGroup: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Cached metadata
    var lastMessageContent: String?
    var lastMessageDate: Date?
    var unreadCount: Int
    
    init(
        id: UUID,
        name: String?,
        avatarUrl: String?,
        isGroup: Bool,
        createdAt: Date,
        updatedAt: Date,
        lastMessageContent: String? = nil,
        lastMessageDate: Date? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isGroup = isGroup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageContent = lastMessageContent
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
    }
    
    /// Convert from remote Conversation to LocalConversation
    static func from(_ conversation: Conversation) -> LocalConversation {
        LocalConversation(
            id: conversation.id,
            name: conversation.name,
            avatarUrl: conversation.avatarUrl,
            isGroup: conversation.isGroup,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            lastMessageContent: conversation.lastMessage?.content,
            lastMessageDate: conversation.lastMessage?.createdAt,
            unreadCount: conversation.unreadCount ?? 0
        )
    }
    
    /// Convert to remote Conversation
    func toConversation() -> Conversation {
        Conversation(
            id: id,
            name: name,
            avatarUrl: avatarUrl,
            isGroup: isGroup,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Outbox entry for messages pending sync
@Model
final class OutboxMessage {
    @Attribute(.unique) var localId: String
    var conversationId: UUID
    var senderId: UUID
    var content: String
    var messageType: String
    var mediaUrl: String?
    var createdAt: Date
    var retryCount: Int
    var lastRetryAt: Date?
    var error: String?
    
    init(
        localId: String,
        conversationId: UUID,
        senderId: UUID,
        content: String,
        messageType: String,
        mediaUrl: String?,
        createdAt: Date,
        retryCount: Int = 0,
        lastRetryAt: Date? = nil,
        error: String? = nil
    ) {
        self.localId = localId
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.error = error
    }
}

