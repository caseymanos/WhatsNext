import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let content: String?
    let messageType: MessageType
    let mediaUrl: String?
    let createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    let localId: String?
    
    // Computed/joined fields
    var sender: User?
    var readReceipts: [ReadReceipt]?
    
    enum CodingKeys: String, CodingKey {
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
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageType: String, Codable {
    case text
    case image
    case video
    case audio
    case file
    case system
}

struct ReadReceipt: Codable, Identifiable {
    let messageId: UUID
    let userId: UUID
    let readAt: Date
    
    var id: String {
        "\(messageId)_\(userId)"
    }
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case userId = "user_id"
        case readAt = "read_at"
    }
}

struct TypingIndicator: Codable, Identifiable {
    let conversationId: UUID
    let userId: UUID
    let lastTyped: Date
    
    var id: String {
        "\(conversationId)_\(userId)"
    }
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case lastTyped = "last_typed"
    }
}

