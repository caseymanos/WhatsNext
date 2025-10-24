import Foundation

/// RSVP tracking for events mentioned in conversations
/// Corresponds to the rsvp_tracking table and track-rsvps Edge Function
public struct RSVPTracking: Codable, Identifiable, Hashable {
    public let id: UUID
    public let messageId: UUID
    public let conversationId: UUID
    public let userId: UUID
    public let eventName: String
    public let requestedBy: UUID?
    public let deadline: Date?
    public let eventDate: Date?
    public var status: RSVPStatus
    public var response: String?
    public let createdAt: Date
    public let respondedAt: Date?

    public enum RSVPStatus: String, Codable {
        case pending
        case yes
        case no
        case maybe
    }

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case userId = "user_id"
        case eventName = "event_name"
        case requestedBy = "requested_by"
        case deadline
        case eventDate = "event_date"
        case status
        case response
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }

    public init(
        id: UUID = UUID(),
        messageId: UUID,
        conversationId: UUID,
        userId: UUID,
        eventName: String,
        requestedBy: UUID? = nil,
        deadline: Date? = nil,
        eventDate: Date? = nil,
        status: RSVPStatus = .pending,
        response: String? = nil,
        createdAt: Date = Date(),
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.userId = userId
        self.eventName = eventName
        self.requestedBy = requestedBy
        self.deadline = deadline
        self.eventDate = eventDate
        self.status = status
        self.response = response
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
}

/// Response from track-rsvps Edge Function
public struct TrackRSVPsResponse: Codable {
    public let rsvps: [RSVPData]
    public let summary: RSVPSummary

    public struct RSVPData: Codable {
        public let messageId: String
        public let eventName: String
        public let requestedBy: String?
        public let deadline: String? // ISO 8601
        public let eventDate: String? // ISO 8601
        public let recipientMentions: [String]?
    }

    public struct RSVPSummary: Codable {
        public let newCount: Int
        public let totalPending: Int
        public let pendingRSVPs: [RSVPTracking]
    }
}
