import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String?
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let createdAt: Date
    var lastSeen: Date?
    var status: UserStatus?
    var pushToken: String?
    
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

enum UserStatus: String, Codable {
    case online
    case away
    case offline
}

