import Foundation

/// AI-detected priority message requiring user attention
/// Corresponds to the priority_messages table and detect-priority Edge Function
public struct PriorityMessage: Codable, Identifiable, Hashable {
    public let messageId: UUID
    public let priority: Priority
    public let reason: String
    public let actionRequired: Bool
    public var dismissed: Bool
    public let createdAt: Date

    public var id: UUID { messageId }

    public enum Priority: String, Codable, Comparable {
        case urgent
        case high
        case medium

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.urgent, .high, .medium]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case priority
        case reason
        case actionRequired = "action_required"
        case dismissed
        case createdAt = "created_at"
    }

    public init(
        messageId: UUID,
        priority: Priority,
        reason: String,
        actionRequired: Bool,
        dismissed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.messageId = messageId
        self.priority = priority
        self.reason = reason
        self.actionRequired = actionRequired
        self.dismissed = dismissed
        self.createdAt = createdAt
    }
}

/// Response from detect-priority Edge Function
public struct DetectPriorityResponse: Codable {
    public let priorityMessages: [PriorityMessageData]

    public struct PriorityMessageData: Codable {
        public let messageId: String
        public let priority: PriorityMessage.Priority
        public let reason: String
        public let actionRequired: Bool
    }
}
