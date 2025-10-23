import Foundation

public struct Message: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let conversationId: UUID
    public let senderId: UUID
    public let content: String?
    public let messageType: MessageType
    public let mediaUrl: String?
    public let createdAt: Date
    public var updatedAt: Date?
    public var deletedAt: Date?
    public let localId: String?
    
    // Computed/joined fields
    public var sender: User?
    public var readReceipts: [ReadReceipt]?
    
    public enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content
        case messageType = "message_type"
        case mediaUrl = "media_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case localId = "local_id"
    }
    
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum MessageType: String, Codable {
    case text
    case image
    case video
    case audio
    case file
    case system
}

public struct ReadReceipt: Codable, Identifiable {
    public let messageId: UUID
    public let userId: UUID
    public let readAt: Date
    
    public var id: String {
        "\(messageId)_\(userId)"
    }
    
    public enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case userId = "user_id"
        case readAt = "read_at"
    }
}

public struct TypingIndicator: Codable, Identifiable {
    public let conversationId: UUID
    public let userId: UUID
    public let lastTyped: Date
    
    public var id: String {
        "\(conversationId)_\(userId)"
    }
    
    public enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case lastTyped = "last_typed"
    }
}

