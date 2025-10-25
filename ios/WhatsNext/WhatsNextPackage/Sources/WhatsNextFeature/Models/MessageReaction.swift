import Foundation

public struct MessageReaction: Codable, Identifiable, Equatable, Hashable {
    public let messageId: UUID
    public let userId: UUID
    public let emoji: String
    public let createdAt: Date

    // For display: user info populated separately
    public var user: User?

    public var id: String {
        "\(messageId)_\(userId)_\(emoji)"
    }

    public enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case userId = "user_id"
        case emoji
        case createdAt = "created_at"
    }

    public static let allowedEmojis = ["👍", "❤️", "😂", "😮", "😢", "😡"]

    public init(messageId: UUID, userId: UUID, emoji: String, createdAt: Date, user: User? = nil) {
        self.messageId = messageId
        self.userId = userId
        self.emoji = emoji
        self.createdAt = createdAt
        self.user = user
    }
}
