import Foundation

struct Conversation: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String?
    var avatarUrl: String?
    let isGroup: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Computed/joined fields (not in DB)
    var participants: [User]?
    var lastMessage: Message?
    var unreadCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}

struct ConversationParticipant: Codable, Identifiable {
    let conversationId: UUID
    let userId: UUID
    let joinedAt: Date
    var lastReadAt: Date?
    
    var id: String {
        "\(conversationId)_\(userId)"
    }
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case lastReadAt = "last_read_at"
    }
}

