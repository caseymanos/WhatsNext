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

    // Calendar sync fields
    public var appleCalendarEventId: String?
    public var googleCalendarEventId: String?
    public var syncStatus: String?
    public var lastSyncAttempt: Date?
    public var syncError: String?

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
        case appleCalendarEventId = "apple_calendar_event_id"
        case googleCalendarEventId = "google_calendar_event_id"
        case syncStatus = "sync_status"
        case lastSyncAttempt = "last_sync_attempt"
        case syncError = "sync_error"
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
        updatedAt: Date = Date(),
        appleCalendarEventId: String? = nil,
        googleCalendarEventId: String? = nil,
        syncStatus: String? = nil,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
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
        self.appleCalendarEventId = appleCalendarEventId
        self.googleCalendarEventId = googleCalendarEventId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    /// Get parsed sync status enum
    public var parsedSyncStatus: SyncStatus {
        guard let statusStr = syncStatus else { return .pending }
        return SyncStatus(rawValue: statusStr) ?? .pending
    }

    /// Check if synced to any system
    public var isSynced: Bool {
        appleCalendarEventId != nil || googleCalendarEventId != nil
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
