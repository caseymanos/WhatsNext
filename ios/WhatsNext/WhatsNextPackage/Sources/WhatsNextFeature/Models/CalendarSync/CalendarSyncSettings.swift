import Foundation

/// User preferences for calendar and reminder synchronization
/// Corresponds to the calendar_sync_settings table
public struct CalendarSyncSettings: Codable, Identifiable {
    public let userId: UUID

    // Feature toggles
    public var appleCalendarEnabled: Bool
    public var googleCalendarEnabled: Bool
    public var appleRemindersEnabled: Bool

    // Category to calendar mapping
    // Maps AI event categories to user's calendar names
    // Example: {"school": "Work", "medical": "Personal", "social": "Family"}
    public var categoryCalendarMapping: [String: String]

    // Google Calendar OAuth credentials
    public var googleCalendarId: String?
    public var googleAccessToken: String?
    public var googleRefreshToken: String?
    public var googleTokenExpiry: Date?

    // Sync preferences
    public var autoSyncEnabled: Bool
    public var syncToAllParticipants: Bool

    // Timestamps
    public let createdAt: Date
    public let updatedAt: Date

    public var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case appleCalendarEnabled = "apple_calendar_enabled"
        case googleCalendarEnabled = "google_calendar_enabled"
        case appleRemindersEnabled = "apple_reminders_enabled"
        case categoryCalendarMapping = "category_calendar_mapping"
        case googleCalendarId = "google_calendar_id"
        case googleAccessToken = "google_access_token"
        case googleRefreshToken = "google_refresh_token"
        case googleTokenExpiry = "google_token_expiry"
        case autoSyncEnabled = "auto_sync_enabled"
        case syncToAllParticipants = "sync_to_all_participants"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        userId: UUID,
        appleCalendarEnabled: Bool = true,
        googleCalendarEnabled: Bool = false,
        appleRemindersEnabled: Bool = true,
        categoryCalendarMapping: [String: String] = [:],
        googleCalendarId: String? = nil,
        googleAccessToken: String? = nil,
        googleRefreshToken: String? = nil,
        googleTokenExpiry: Date? = nil,
        autoSyncEnabled: Bool = true,
        syncToAllParticipants: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.appleCalendarEnabled = appleCalendarEnabled
        self.googleCalendarEnabled = googleCalendarEnabled
        self.appleRemindersEnabled = appleRemindersEnabled
        self.categoryCalendarMapping = categoryCalendarMapping
        self.googleCalendarId = googleCalendarId
        self.googleAccessToken = googleAccessToken
        self.googleRefreshToken = googleRefreshToken
        self.googleTokenExpiry = googleTokenExpiry
        self.autoSyncEnabled = autoSyncEnabled
        self.syncToAllParticipants = syncToAllParticipants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Default settings for a new user
    public static func defaultSettings(for userId: UUID) -> CalendarSyncSettings {
        CalendarSyncSettings(
            userId: userId,
            appleCalendarEnabled: true,
            googleCalendarEnabled: false,
            appleRemindersEnabled: true,
            categoryCalendarMapping: [:],
            autoSyncEnabled: true,
            syncToAllParticipants: true
        )
    }

    /// Check if Google Calendar is properly configured
    /// Note: This only checks calendar ID. OAuth tokens are stored securely in Keychain.
    public var isGoogleCalendarConfigured: Bool {
        googleCalendarEnabled &&
        googleCalendarId != nil
        // OAuth tokens are now in Keychain (not in settings) for security
    }

    /// Check if any sync target is enabled
    public var hasAnySyncEnabled: Bool {
        appleCalendarEnabled || googleCalendarEnabled || appleRemindersEnabled
    }

    /// Get calendar name for a given category
    public func calendarName(for category: String) -> String? {
        categoryCalendarMapping[category]
    }
}

/// Request/update struct for calendar sync settings
public struct CalendarSyncSettingsUpdate: Encodable {
    public let userId: UUID?
    public let appleCalendarEnabled: Bool?
    public let googleCalendarEnabled: Bool?
    public let appleRemindersEnabled: Bool?
    public let categoryCalendarMapping: [String: String]?
    public let googleCalendarId: String?
    public let googleAccessToken: String?
    public let googleRefreshToken: String?
    public let googleTokenExpiry: Date?
    public let autoSyncEnabled: Bool?
    public let syncToAllParticipants: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case appleCalendarEnabled = "apple_calendar_enabled"
        case googleCalendarEnabled = "google_calendar_enabled"
        case appleRemindersEnabled = "apple_reminders_enabled"
        case categoryCalendarMapping = "category_calendar_mapping"
        case googleCalendarId = "google_calendar_id"
        case googleAccessToken = "google_access_token"
        case googleRefreshToken = "google_refresh_token"
        case googleTokenExpiry = "google_token_expiry"
        case autoSyncEnabled = "auto_sync_enabled"
        case syncToAllParticipants = "sync_to_all_participants"
    }

    public init(
        userId: UUID? = nil,
        appleCalendarEnabled: Bool? = nil,
        googleCalendarEnabled: Bool? = nil,
        appleRemindersEnabled: Bool? = nil,
        categoryCalendarMapping: [String: String]? = nil,
        googleCalendarId: String? = nil,
        googleAccessToken: String? = nil,
        googleRefreshToken: String? = nil,
        googleTokenExpiry: Date? = nil,
        autoSyncEnabled: Bool? = nil,
        syncToAllParticipants: Bool? = nil
    ) {
        self.userId = userId
        self.appleCalendarEnabled = appleCalendarEnabled
        self.googleCalendarEnabled = googleCalendarEnabled
        self.appleRemindersEnabled = appleRemindersEnabled
        self.categoryCalendarMapping = categoryCalendarMapping
        self.googleCalendarId = googleCalendarId
        self.googleAccessToken = googleAccessToken
        self.googleRefreshToken = googleRefreshToken
        self.googleTokenExpiry = googleTokenExpiry
        self.autoSyncEnabled = autoSyncEnabled
        self.syncToAllParticipants = syncToAllParticipants
    }
}
