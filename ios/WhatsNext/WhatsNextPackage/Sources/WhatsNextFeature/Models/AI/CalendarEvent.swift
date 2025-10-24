import Foundation

/// AI-extracted calendar event from conversation messages
/// Corresponds to the calendar_events table and extract-calendar-events Edge Function
public struct CalendarEvent: Codable, Identifiable, Hashable {
    public let id: UUID
    public let conversationId: UUID
    public let messageId: UUID?
    public let title: String
    public let date: Date
    public let time: String? // HH:MM format
    public let location: String?
    public let description: String?
    public let category: EventCategory
    public let confidence: Double
    public var confirmed: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public enum EventCategory: String, Codable {
        case school
        case medical
        case social
        case sports
        case work
        case other
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case title
        case date
        case time
        case location
        case description
        case category
        case confidence
        case confirmed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        messageId: UUID? = nil,
        title: String,
        date: Date,
        time: String? = nil,
        location: String? = nil,
        description: String? = nil,
        category: EventCategory,
        confidence: Double,
        confirmed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.messageId = messageId
        self.title = title
        self.date = date
        self.time = time
        self.location = location
        self.description = description
        self.category = category
        self.confidence = confidence
        self.confirmed = confirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Response from extract-calendar-events Edge Function
public struct ExtractCalendarEventsResponse: Codable {
    public let events: [CalendarEventData]

    public struct CalendarEventData: Codable {
        public let title: String
        public let date: String // YYYY-MM-DD
        public let time: String? // HH:MM
        public let location: String?
        public let description: String?
        public let category: CalendarEvent.EventCategory
        public let confidence: Double
    }
}
