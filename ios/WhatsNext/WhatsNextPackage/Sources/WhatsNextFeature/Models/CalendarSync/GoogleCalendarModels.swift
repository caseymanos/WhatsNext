import Foundation

/// Google OAuth credentials
public struct GoogleOAuthCredentials: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let scope: String

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scope: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// Check if the access token has expired
    public var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Check if token will expire soon (within 5 minutes)
    public var willExpireSoon: Bool {
        Date().addingTimeInterval(300) >= expiresAt
    }
}

/// Google Calendar metadata
public struct GoogleCalendar: Codable, Identifiable, Hashable {
    public let id: String
    public let summary: String // Display name
    public let description: String?
    public let timeZone: String?
    public let colorId: String?
    public let backgroundColor: String?
    public let foregroundColor: String?
    public let accessRole: String? // "owner", "writer", "reader"
    public let primary: Bool

    public init(
        id: String,
        summary: String,
        description: String? = nil,
        timeZone: String? = nil,
        colorId: String? = nil,
        backgroundColor: String? = nil,
        foregroundColor: String? = nil,
        accessRole: String? = nil,
        primary: Bool = false
    ) {
        self.id = id
        self.summary = summary
        self.description = description
        self.timeZone = timeZone
        self.colorId = colorId
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.accessRole = accessRole
        self.primary = primary
    }

    /// Check if user can write to this calendar
    public var canWrite: Bool {
        accessRole == "owner" || accessRole == "writer"
    }
}

/// Google Calendar event (simplified for API communication)
public struct GoogleCalendarEvent: Codable {
    public let id: String?
    public let summary: String
    public let description: String?
    public let location: String?
    public let start: GoogleEventDateTime
    public let end: GoogleEventDateTime
    public let timeZone: String?

    public init(
        id: String? = nil,
        summary: String,
        description: String? = nil,
        location: String? = nil,
        start: GoogleEventDateTime,
        end: GoogleEventDateTime,
        timeZone: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.description = description
        self.location = location
        self.start = start
        self.end = end
        self.timeZone = timeZone
    }

    /// Create from WhatsNext CalendarEvent
    public static func from(
        aiEvent: CalendarEvent,
        timeZone: String = TimeZone.current.identifier
    ) -> GoogleCalendarEvent {
        // Combine date and time
        var startDateTime = aiEvent.date
        if let timeStr = aiEvent.time {
            // Parse HH:MM format
            let components = timeStr.split(separator: ":")
            if components.count == 2,
               let hour = Int(components[0]),
               let minute = Int(components[1]) {
                var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: aiEvent.date)
                dateComponents.hour = hour
                dateComponents.minute = minute
                if let combined = Calendar.current.date(from: dateComponents) {
                    startDateTime = combined
                }
            }
        }

        // Default 1-hour duration
        let endDateTime = startDateTime.addingTimeInterval(3600)

        return GoogleCalendarEvent(
            summary: aiEvent.title,
            description: aiEvent.description,
            location: aiEvent.location,
            start: GoogleEventDateTime(dateTime: startDateTime, timeZone: timeZone),
            end: GoogleEventDateTime(dateTime: endDateTime, timeZone: timeZone),
            timeZone: timeZone
        )
    }
}

/// Google Calendar event date/time
public struct GoogleEventDateTime: Codable {
    public let dateTime: String? // ISO 8601 format with timezone
    public let date: String? // YYYY-MM-DD format for all-day events
    public let timeZone: String?

    public init(dateTime: Date, timeZone: String) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZone)
        self.dateTime = formatter.string(from: dateTime)
        self.date = nil
        self.timeZone = timeZone
    }

    public init(date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.date = formatter.string(from: date)
        self.dateTime = nil
        self.timeZone = nil
    }
}

/// Google Calendar API responses
public struct GoogleCalendarListResponse: Codable {
    public let items: [GoogleCalendar]
}

public struct GoogleCalendarEventResponse: Codable {
    public let id: String
    public let htmlLink: String?
}
