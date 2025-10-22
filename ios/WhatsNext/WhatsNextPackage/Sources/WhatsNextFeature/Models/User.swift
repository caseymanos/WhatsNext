import Foundation

public struct User: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let email: String?
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let createdAt: Date
    public var lastSeen: Date?
    public var status: UserStatus?
    public var pushToken: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case lastSeen = "last_seen"
        case status
        case pushToken = "push_token"
    }
}

public enum UserStatus: String, Codable {
    case online
    case away
    case offline
}

