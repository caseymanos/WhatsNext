import Foundation

/// Sync status for calendar events and reminders
public enum SyncStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case syncing = "syncing"
    case synced = "synced"
    case failed = "failed"

    /// Human-readable description
    public var description: String {
        switch self {
        case .pending:
            return "Waiting to sync"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .failed:
            return "Sync failed"
        }
    }

    /// Icon name for UI display
    public var iconName: String {
        switch self {
        case .pending:
            return "clock"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Color for UI display
    public var colorName: String {
        switch self {
        case .pending:
            return "gray"
        case .syncing:
            return "blue"
        case .synced:
            return "green"
        case .failed:
            return "red"
        }
    }
}

/// Target system for sync operations
public enum SyncTarget: String, Codable, CaseIterable {
    case appleCalendar = "apple_calendar"
    case googleCalendar = "google_calendar"
    case appleReminders = "apple_reminders"

    public var displayName: String {
        switch self {
        case .appleCalendar:
            return "Apple Calendar"
        case .googleCalendar:
            return "Google Calendar"
        case .appleReminders:
            return "Apple Reminders"
        }
    }

    public var iconName: String {
        switch self {
        case .appleCalendar:
            return "calendar"
        case .googleCalendar:
            return "calendar.badge.clock"
        case .appleReminders:
            return "checklist"
        }
    }
}

/// Sync operation type
public enum SyncOperation: String, Codable {
    case create
    case update
    case delete
}

/// Item type for sync operations
public enum SyncItemType: String, Codable {
    case calendarEvent = "calendar_event"
    case deadline = "deadline"
    case rsvp = "rsvp"
}
