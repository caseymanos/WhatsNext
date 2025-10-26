import Foundation
import Supabase
import OSLog

/// Orchestrates calendar and reminder synchronization between app and external systems
@MainActor
final class CalendarSyncEngine {
    private let supabase = SupabaseClientService.shared
    private let eventKitService = EventKitService()
    private let googleService = GoogleCalendarService()
    private let permissionService = CalendarPermissionService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "CalendarSyncEngine")

    // MARK: - Error Handling

    enum SyncError: LocalizedError {
        case noSettings
        case noSyncEnabled
        case permissionDenied(String)
        case syncFailed(String)
        case googleNotConfigured

        var errorDescription: String? {
            switch self {
            case .noSettings:
                return "Sync settings not found for user"
            case .noSyncEnabled:
                return "No sync targets enabled"
            case .permissionDenied(let target):
                return "Permission denied for \(target)"
            case .syncFailed(let reason):
                return "Sync failed: \(reason)"
            case .googleNotConfigured:
                return "Google Calendar not configured"
            }
        }
    }

    // MARK: - Sync Settings Management

    /// Fetch user's sync settings
    func fetchSyncSettings(userId: UUID) async throws -> CalendarSyncSettings {
        let settings: CalendarSyncSettings = try await supabase.database
            .from("calendar_sync_settings")
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value

        return settings
    }

    /// Update sync settings
    func updateSyncSettings(_ settings: CalendarSyncSettings) async throws {
        try await supabase.database
            .from("calendar_sync_settings")
            .upsert(settings)
            .execute()
    }

    /// Create default settings for new user
    func createDefaultSettings(userId: UUID) async throws -> CalendarSyncSettings {
        let settings = CalendarSyncSettings.defaultSettings(for: userId)

        try await supabase.database
            .from("calendar_sync_settings")
            .insert(settings)
            .execute()

        return settings
    }

    // MARK: - Calendar Event Sync

    /// Sync a calendar event to all enabled targets
    func syncCalendarEvent(
        _ event: CalendarEvent,
        userId: UUID
    ) async throws {
        let settings = try await fetchSyncSettings(userId: userId)

        guard settings.hasAnySyncEnabled else {
            throw SyncError.noSyncEnabled
        }

        // Update sync status to syncing
        try await updateEventSyncStatus(
            eventId: event.id,
            status: .syncing,
            error: nil
        )

        var syncErrors: [String] = []

        // Sync to Apple Calendar
        if settings.appleCalendarEnabled {
            do {
                try await syncToAppleCalendar(event: event, settings: settings)
            } catch {
                syncErrors.append("Apple Calendar: \(error.localizedDescription)")
                try? await addToSyncQueue(
                    userId: userId,
                    itemType: .calendarEvent,
                    itemId: event.id,
                    operation: event.appleCalendarEventId == nil ? .create : .update,
                    targetSystem: .appleCalendar,
                    error: error.localizedDescription
                )
            }
        }

        // Sync to Google Calendar
        if settings.googleCalendarEnabled {
            do {
                try await syncToGoogleCalendar(event: event, settings: settings)
            } catch {
                syncErrors.append("Google Calendar: \(error.localizedDescription)")
                try? await addToSyncQueue(
                    userId: userId,
                    itemType: .calendarEvent,
                    itemId: event.id,
                    operation: event.googleCalendarEventId == nil ? .create : .update,
                    targetSystem: .googleCalendar,
                    error: error.localizedDescription
                )
            }
        }

        // Update final sync status
        if syncErrors.isEmpty {
            try await updateEventSyncStatus(
                eventId: event.id,
                status: .synced,
                error: nil
            )
        } else {
            try await updateEventSyncStatus(
                eventId: event.id,
                status: .failed,
                error: syncErrors.joined(separator: "; ")
            )
        }
    }

    /// Sync to Apple Calendar
    private func syncToAppleCalendar(
        event: CalendarEvent,
        settings: CalendarSyncSettings
    ) async throws {
        guard await permissionService.isCalendarAuthorized else {
            throw SyncError.permissionDenied("Apple Calendar")
        }

        // Get calendar name from category mapping or use default
        let calendarName = settings.calendarName(for: event.category.rawValue)

        if let existingId = event.appleCalendarEventId {
            // Update existing event
            try await eventKitService.updateEvent(eventId: existingId, from: event)
        } else {
            // Create new event
            let eventId = try await eventKitService.createEvent(from: event, calendarName: calendarName)

            // Update database with external ID
            try await supabase.database
                .from("calendar_events")
                .update(["apple_calendar_event_id": eventId])
                .eq("id", value: event.id)
                .execute()
        }
    }

    /// Sync to Google Calendar
    private func syncToGoogleCalendar(
        event: CalendarEvent,
        settings: CalendarSyncSettings
    ) async throws {
        guard settings.isGoogleCalendarConfigured else {
            throw SyncError.googleNotConfigured
        }

        guard let accessToken = settings.googleAccessToken,
              let refreshToken = settings.googleRefreshToken,
              let tokenExpiry = settings.googleTokenExpiry,
              let calendarId = settings.googleCalendarId else {
            throw SyncError.googleNotConfigured
        }

        // Check and refresh token if needed
        var credentials = GoogleOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: tokenExpiry,
            scope: "https://www.googleapis.com/auth/calendar"
        )

        if credentials.willExpireSoon {
            // Refresh the access token
            logger.info("Google access token expiring soon, refreshing...")

            // Use server client ID for token refresh (web client ID from Google Cloud Console)
            let clientId = "169626497145-480k40j56rc3ufluv8i8o6sr2cp5gki0.apps.googleusercontent.com"

            do {
                // For mobile apps, Google allows refresh without client secret in certain configurations
                // If this fails, the app needs proper OAuth 2.0 configuration in Google Cloud Console
                credentials = try await googleService.refreshAccessToken(
                    refreshToken: refreshToken,
                    clientId: clientId,
                    clientSecret: "" // Mobile apps typically don't need this
                )

                // Update settings with new tokens
                var updatedSettings = settings
                updatedSettings.googleAccessToken = credentials.accessToken
                updatedSettings.googleTokenExpiry = credentials.expiresAt

                try await supabase.database
                    .from("calendar_sync_settings")
                    .update([
                        "google_access_token": credentials.accessToken,
                        "google_token_expiry": ISO8601DateFormatter().string(from: credentials.expiresAt)
                    ])
                    .eq("user_id", value: userId)
                    .execute()

                logger.info("Successfully refreshed Google access token")
            } catch {
                logger.error("Failed to refresh Google token: \(error.localizedDescription)")
                throw SyncError.googleNotConfigured
            }
        }

        // Convert to Google Calendar format
        let googleEvent = GoogleCalendarEvent.from(aiEvent: event)

        if let existingId = event.googleCalendarEventId {
            // Update existing event
            _ = try await googleService.updateEvent(
                calendarId: calendarId,
                eventId: existingId,
                event: googleEvent,
                credentials: credentials
            )
        } else {
            // Create new event
            let response = try await googleService.createEvent(
                calendarId: calendarId,
                event: googleEvent,
                credentials: credentials
            )

            // Update database with external ID
            try await supabase.database
                .from("calendar_events")
                .update(["google_calendar_event_id": response.id])
                .eq("id", value: event.id)
                .execute()
        }
    }

    // MARK: - Reminder Sync

    /// Sync a deadline to Apple Reminders
    func syncDeadlineToReminders(
        _ deadline: Deadline,
        userId: UUID
    ) async throws {
        let settings = try await fetchSyncSettings(userId: userId)

        guard settings.appleRemindersEnabled else {
            return
        }

        guard await permissionService.isRemindersAuthorized else {
            throw SyncError.permissionDenied("Apple Reminders")
        }

        // Update sync status to syncing
        try await updateDeadlineSyncStatus(
            deadlineId: deadline.id,
            status: .syncing,
            error: nil
        )

        do {
            // Get calendar name from category mapping or use default
            let listName = settings.calendarName(for: deadline.category.rawValue)

            if let existingId = deadline.appleReminderId {
                // Update existing reminder
                try await eventKitService.updateReminder(reminderId: existingId, from: deadline)
            } else {
                // Create new reminder
                let reminderId = try await eventKitService.createReminder(from: deadline, listName: listName)

                // Update database with external ID
                try await supabase.database
                    .from("deadlines")
                    .update(["apple_reminder_id": reminderId])
                    .eq("id", value: deadline.id)
                    .execute()
            }

            try await updateDeadlineSyncStatus(
                deadlineId: deadline.id,
                status: .synced,
                error: nil
            )
        } catch {
            try await updateDeadlineSyncStatus(
                deadlineId: deadline.id,
                status: .failed,
                error: error.localizedDescription
            )

            try await addToSyncQueue(
                userId: userId,
                itemType: .deadline,
                itemId: deadline.id,
                operation: deadline.appleReminderId == nil ? .create : .update,
                targetSystem: .appleReminders,
                error: error.localizedDescription
            )

            throw error
        }
    }

    // MARK: - Sync Queue Management

    /// Add failed sync to retry queue
    private func addToSyncQueue(
        userId: UUID,
        itemType: SyncItemType,
        itemId: UUID,
        operation: SyncOperation,
        targetSystem: SyncTarget,
        error: String
    ) async throws {
        var queueItem = SyncQueueItem(
            userId: userId,
            itemType: itemType,
            itemId: itemId,
            operation: operation,
            targetSystem: targetSystem,
            retryCount: 0,
            maxRetries: 3,
            lastError: error
        )
        queueItem.scheduleNextRetry()

        try await supabase.database
            .from("calendar_sync_queue")
            .insert(queueItem)
            .execute()
    }

    /// Process pending items in sync queue
    func processSyncQueue(userId: UUID) async throws {
        let queueItems: [SyncQueueItem] = try await supabase.database
            .from("calendar_sync_queue")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        for var item in queueItems {
            // Skip if not ready to retry
            guard item.isReadyToRetry else { continue }

            // Skip if exceeded max retries
            guard !item.hasExceededMaxRetries else {
                try await removeFromSyncQueue(itemId: item.id)
                continue
            }

            // Retry sync based on item type
            do {
                switch item.itemType {
                case .calendarEvent:
                    let event: CalendarEvent = try await supabase.database
                        .from("calendar_events")
                        .select()
                        .eq("id", value: item.itemId)
                        .single()
                        .execute()
                        .value
                    try await syncCalendarEvent(event, userId: userId)

                case .deadline:
                    let deadline: Deadline = try await supabase.database
                        .from("deadlines")
                        .select()
                        .eq("id", value: item.itemId)
                        .single()
                        .execute()
                        .value
                    try await syncDeadlineToReminders(deadline, userId: userId)

                case .rsvp:
                    // RSVP sync not yet implemented - skip for now
                    logger.info("Skipping RSVP sync (not yet implemented): \(item.itemId)")
                }

                // Success - remove from queue
                try await removeFromSyncQueue(itemId: item.id)
            } catch {
                // Failed - update retry info
                item.scheduleNextRetry()
                item.lastError = error.localizedDescription

                try await supabase.database
                    .from("calendar_sync_queue")
                    .update(item)
                    .eq("id", value: item.id)
                    .execute()
            }
        }
    }

    /// Remove item from sync queue
    private func removeFromSyncQueue(itemId: UUID) async throws {
        try await supabase.database
            .from("calendar_sync_queue")
            .delete()
            .eq("id", value: itemId)
            .execute()
    }

    // MARK: - Two-Way Sync Detection

    /// Detect and process external changes from Apple Calendar
    func detectAndSyncExternalCalendarChanges(userId: UUID) async throws {
        let settings = try await fetchSyncSettings(userId: userId)

        guard settings.appleCalendarEnabled else { return }
        guard await permissionService.isCalendarAuthorized else { return }

        // Get all tracked events for user (only those synced to Apple Calendar)
        let trackedEvents: [CalendarEvent] = try await supabase.database
            .from("calendar_events")
            .select()
            .eq("user_id", value: userId)
            .not("apple_calendar_event_id", operator: .is, value: "null")
            .execute()
            .value

        let trackedIds = trackedEvents.compactMap { $0.appleCalendarEventId }

        // Detect changes in last 90 days
        let startDate = Date().addingTimeInterval(-90 * 24 * 3600)
        let endDate = Date().addingTimeInterval(365 * 24 * 3600)

        let changes = try await eventKitService.detectExternalEventChanges(
            startDate: startDate,
            endDate: endDate,
            trackedEventIds: trackedIds
        )

        // Process deletions
        for change in changes where change.changeType == .deleted {
            // Find the event in our database
            if let event = trackedEvents.first(where: { $0.appleCalendarEventId == change.externalId }) {
                // Mark as deleted in our system
                try await supabase.database
                    .from("calendar_events")
                    .update([
                        "apple_calendar_event_id": nil,
                        "sync_status": SyncStatus.pending.rawValue
                    ])
                    .eq("id", value: event.id)
                    .execute()
            }
        }
    }

    /// Detect and process external changes from Apple Reminders
    func detectAndSyncExternalReminderChanges(userId: UUID) async throws {
        let settings = try await fetchSyncSettings(userId: userId)

        guard settings.appleRemindersEnabled else { return }
        guard await permissionService.isRemindersAuthorized else { return }

        // Get all tracked reminders for user (only those synced to Apple Reminders)
        let trackedDeadlines: [Deadline] = try await supabase.database
            .from("deadlines")
            .select()
            .eq("user_id", value: userId)
            .not("apple_reminder_id", operator: .is, value: "null")
            .execute()
            .value

        let trackedIds = trackedDeadlines.compactMap { $0.appleReminderId }

        let changes = try await eventKitService.detectExternalReminderChanges(
            trackedReminderIds: trackedIds
        )

        // Process deletions
        for change in changes where change.changeType == .deleted {
            if let deadline = trackedDeadlines.first(where: { $0.appleReminderId == change.externalId }) {
                // Mark as deleted in our system
                try await supabase.database
                    .from("deadlines")
                    .update([
                        "apple_reminder_id": nil,
                        "sync_status": SyncStatus.pending.rawValue
                    ])
                    .eq("id", value: deadline.id)
                    .execute()
            }
        }
    }

    // MARK: - Sync Status Updates

    /// Update sync status for calendar event
    private func updateEventSyncStatus(
        eventId: UUID,
        status: SyncStatus,
        error: String?
    ) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await supabase.database
            .from("calendar_events")
            .update([
                "sync_status": status.rawValue,
                "last_sync_attempt": now,
                "sync_error": error ?? ""
            ])
            .eq("id", value: eventId)
            .execute()
    }

    /// Update sync status for deadline
    private func updateDeadlineSyncStatus(
        deadlineId: UUID,
        status: SyncStatus,
        error: String?
    ) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await supabase.database
            .from("deadlines")
            .update([
                "sync_status": status.rawValue,
                "last_sync_attempt": now,
                "sync_error": error ?? ""
            ])
            .eq("id", value: deadlineId)
            .execute()
    }

    // MARK: - Bulk Sync

    /// Sync all pending calendar events for user
    func syncAllPendingEvents(userId: UUID) async throws {
        let pendingEvents: [CalendarEvent] = try await supabase.database
            .from("calendar_events")
            .select()
            .eq("user_id", value: userId)
            .or("sync_status.eq.pending,sync_status.is.null")
            .execute()
            .value

        for event in pendingEvents {
            try? await syncCalendarEvent(event, userId: userId)
        }
    }

    /// Sync all pending deadlines for user
    func syncAllPendingDeadlines(userId: UUID) async throws {
        let pendingDeadlines: [Deadline] = try await supabase.database
            .from("deadlines")
            .select()
            .eq("user_id", value: userId)
            .or("sync_status.eq.pending,sync_status.is.null")
            .execute()
            .value

        for deadline in pendingDeadlines {
            try? await syncDeadlineToReminders(deadline, userId: userId)
        }
    }
}
