import Foundation
import EventKit
import OSLog

/// Service for managing calendar and reminders permissions
/// Follows the PushNotificationService pattern for consistency
@MainActor
public final class CalendarPermissionService: NSObject {
    public static let shared = CalendarPermissionService()

    private let logger = Logger(subsystem: "com.gauntletai.whatsnext", category: "CalendarPermissions")
    private let eventStore = EKEventStore()

    @Published public var isCalendarAuthorized = false
    @Published public var isRemindersAuthorized = false

    private override init() {
        super.init()
        logger.info("CalendarPermissionService initialized")
    }

    // MARK: - Authorization Status Check

    /// Check current authorization status for calendar and reminders
    public func checkAuthorizationStatus() async -> (calendar: EKAuthorizationStatus, reminders: EKAuthorizationStatus) {
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        let remindersStatus = EKEventStore.authorizationStatus(for: .reminder)

        isCalendarAuthorized = (calendarStatus == .fullAccess)
        isRemindersAuthorized = (remindersStatus == .fullAccess)

        logger.info("Calendar authorization: \(calendarStatus.rawValue), Reminders: \(remindersStatus.rawValue)")

        return (calendarStatus, remindersStatus)
    }

    /// Check if calendar permission is authorized
    public func isCalendarAuthorizationFullAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        isCalendarAuthorized = (status == .fullAccess)
        return isCalendarAuthorized
    }

    /// Check if reminders permission is authorized
    public func isRemindersAuthorizationFullAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        isRemindersAuthorized = (status == .fullAccess)
        return isRemindersAuthorized
    }

    // MARK: - Request Authorization

    /// Request calendar authorization
    /// Shows system permission dialog if not yet determined
    public func requestCalendarAuthorization() async throws {
        logger.info("Requesting calendar authorization")

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isCalendarAuthorized = granted

            if granted {
                logger.info("Calendar authorization granted")
            } else {
                logger.warning("Calendar authorization denied")
            }
        } catch {
            logger.error("Calendar authorization request failed: \(error.localizedDescription)")
            throw CalendarPermissionError.authorizationFailed(error)
        }
    }

    /// Request reminders authorization
    /// Shows system permission dialog if not yet determined
    public func requestRemindersAuthorization() async throws {
        logger.info("Requesting reminders authorization")

        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            isRemindersAuthorized = granted

            if granted {
                logger.info("Reminders authorization granted")
            } else {
                logger.warning("Reminders authorization denied")
            }
        } catch {
            logger.error("Reminders authorization request failed: \(error.localizedDescription)")
            throw CalendarPermissionError.authorizationFailed(error)
        }
    }

    /// Request both calendar and reminders authorization
    /// Useful for onboarding flow
    public func requestAllPermissions() async throws {
        logger.info("Requesting all calendar permissions")

        // Request calendar first
        try await requestCalendarAuthorization()

        // Then request reminders
        try await requestRemindersAuthorization()

        logger.info("All permissions requested. Calendar: \(isCalendarAuthorized), Reminders: \(isRemindersAuthorized)")
    }

    // MARK: - Settings Navigation

    /// Open system settings to calendar permissions
    /// Call this when user needs to manually enable permissions
    public func openSettings() {
        logger.info("Opening system settings for calendar permissions")

        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

// MARK: - Errors

public enum CalendarPermissionError: LocalizedError {
    case authorizationFailed(Error)
    case calendarAccessDenied
    case remindersAccessDenied
    case notDetermined

    public var errorDescription: String? {
        switch self {
        case .authorizationFailed(let error):
            return "Failed to authorize calendar access: \(error.localizedDescription)"
        case .calendarAccessDenied:
            return "Calendar access denied. Please enable in Settings."
        case .remindersAccessDenied:
            return "Reminders access denied. Please enable in Settings."
        case .notDetermined:
            return "Calendar permissions not yet requested"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .authorizationFailed:
            return "Please try again or check your system settings."
        case .calendarAccessDenied, .remindersAccessDenied:
            return "Go to Settings > WhatsNext > Calendars to enable access."
        case .notDetermined:
            return "Please grant calendar access when prompted."
        }
    }
}
