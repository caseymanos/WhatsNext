import Foundation

/// AI-extracted deadline or task from conversations
/// Corresponds to the deadlines table and extract-deadlines Edge Function
public struct Deadline: Codable, Identifiable, Hashable {
    public let id: UUID
    public let messageId: UUID?
    public let conversationId: UUID
    public let userId: UUID
    public let task: String
    public let deadline: Date
    public let category: DeadlineCategory
    public let priority: DeadlinePriority
    public let details: String?
    public var status: DeadlineStatus
    public let createdAt: Date
    public let completedAt: Date?

    // Reminder sync fields
    public var appleReminderId: String?
    public var syncStatus: String?
    public var lastSyncAttempt: Date?
    public var syncError: String?

    public enum DeadlineCategory: String, Codable {
        case school
        case bills
        case chores
        case forms
        case medical
        case work
        case other
    }

    public enum DeadlinePriority: String, Codable, Comparable {
        case urgent
        case high
        case medium
        case low

        public static func < (lhs: DeadlinePriority, rhs: DeadlinePriority) -> Bool {
            let order: [DeadlinePriority] = [.urgent, .high, .medium, .low]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }

    public enum DeadlineStatus: String, Codable {
        case pending
        case completed
        case cancelled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case userId = "user_id"
        case task
        case deadline
        case category
        case priority
        case details
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case appleReminderId = "apple_reminder_id"
        case syncStatus = "sync_status"
        case lastSyncAttempt = "last_sync_attempt"
        case syncError = "sync_error"
    }

    public init(
        id: UUID = UUID(),
        messageId: UUID? = nil,
        conversationId: UUID,
        userId: UUID,
        task: String,
        deadline: Date,
        category: DeadlineCategory,
        priority: DeadlinePriority,
        details: String? = nil,
        status: DeadlineStatus = .pending,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        appleReminderId: String? = nil,
        syncStatus: String? = nil,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.userId = userId
        self.task = task
        self.deadline = deadline
        self.category = category
        self.priority = priority
        self.details = details
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.appleReminderId = appleReminderId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    /// Get parsed sync status enum
    public var parsedSyncStatus: SyncStatus {
        guard let statusStr = syncStatus else { return .pending }
        return SyncStatus(rawValue: statusStr) ?? .pending
    }

    /// Check if synced to Apple Reminders
    public var isSynced: Bool {
        appleReminderId != nil
    }
}

/// Response from extract-deadlines Edge Function
public struct ExtractDeadlinesResponse: Codable {
    public let deadlines: [DeadlineData]

    public struct DeadlineData: Codable {
        public let messageId: String
        public let task: String
        public let deadline: String // ISO 8601
        public let category: Deadline.DeadlineCategory
        public let priority: Deadline.DeadlinePriority
        public let details: String?
        public let assignedTo: String?
    }
}
