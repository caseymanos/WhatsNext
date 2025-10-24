import Foundation

/// User and AI-generated reminder
/// Corresponds to the reminders table
public struct Reminder: Codable, Identifiable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let title: String
    public let reminderTime: Date
    public let priority: ReminderPriority
    public var status: ReminderStatus
    public let createdBy: ReminderCreator
    public let createdAt: Date

    public enum ReminderPriority: String, Codable {
        case urgent
        case high
        case medium
        case low
    }

    public enum ReminderStatus: String, Codable {
        case pending
        case sent
        case dismissed
    }

    public enum ReminderCreator: String, Codable {
        case ai
        case user
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case reminderTime = "reminder_time"
        case priority
        case status
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        title: String,
        reminderTime: Date,
        priority: ReminderPriority,
        status: ReminderStatus = .pending,
        createdBy: ReminderCreator = .user,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.reminderTime = reminderTime
        self.priority = priority
        self.status = status
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}
