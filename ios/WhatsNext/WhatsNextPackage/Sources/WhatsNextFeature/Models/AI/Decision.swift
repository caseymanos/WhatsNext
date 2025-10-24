import Foundation

/// AI-tracked decision from family/group conversations
/// Corresponds to the decisions table and track-decisions Edge Function
public struct Decision: Codable, Identifiable, Hashable {
    public let id: UUID
    public let conversationId: UUID
    public let messageId: UUID?
    public let decisionText: String
    public let category: DecisionCategory
    public let decidedBy: UUID?
    public let deadline: Date?
    public let createdAt: Date

    public enum DecisionCategory: String, Codable {
        case activity
        case schedule
        case purchase
        case policy
        case food
        case other
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case decisionText = "decision_text"
        case category
        case decidedBy = "decided_by"
        case deadline
        case createdAt = "created_at"
    }

    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        messageId: UUID? = nil,
        decisionText: String,
        category: DecisionCategory,
        decidedBy: UUID? = nil,
        deadline: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.messageId = messageId
        self.decisionText = decisionText
        self.category = category
        self.decidedBy = decidedBy
        self.deadline = deadline
        self.createdAt = createdAt
    }
}

/// Response from track-decisions Edge Function
public struct TrackDecisionsResponse: Codable {
    public let decisions: [DecisionData]

    public struct DecisionData: Codable {
        public let decisionText: String
        public let category: Decision.DecisionCategory
        public let decidedBy: String?
        public let deadline: String? // YYYY-MM-DD
        public let messageReference: String?
    }
}
