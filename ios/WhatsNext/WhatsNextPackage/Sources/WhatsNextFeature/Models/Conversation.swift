import Foundation

public struct Conversation: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String?
    public var avatarUrl: String?
    public let isGroup: Bool
    public let createdAt: Date
    public var updatedAt: Date
    
    // Computed/joined fields (not in DB)
    public var participants: [User]?
    public var lastMessage: Message?
    public var unreadCount: Int?
    
    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.lastMessage?.id == rhs.lastMessage?.id
    }
    
    public init(id: UUID, name: String? = nil, avatarUrl: String? = nil, isGroup: Bool, createdAt: Date, updatedAt: Date, participants: [User]? = nil, lastMessage: Message? = nil, unreadCount: Int? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isGroup = isGroup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
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

