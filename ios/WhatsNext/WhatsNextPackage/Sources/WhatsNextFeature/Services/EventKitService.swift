import Foundation
import EventKit

/// Service for managing Apple Calendar events and Reminders using EventKit
final class EventKitService {
    private let eventStore = EKEventStore()
    private let permissionService = CalendarPermissionService.shared

    // MARK: - Error Handling

    enum CalendarServiceError: LocalizedError {
        case permissionDenied
        case calendarNotFound(String)
        case eventNotFound(String)
        case reminderNotFound(String)
        case creationFailed(String)
        case updateFailed(String)
        case deletionFailed(String)
        case invalidData(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Calendar or Reminders permission not granted"
            case .calendarNotFound(let name):
                return "Calendar '\(name)' not found"
            case .eventNotFound(let id):
                return "Event with ID '\(id)' not found"
            case .reminderNotFound(let id):
                return "Reminder with ID '\(id)' not found"
            case .creationFailed(let reason):
                return "Failed to create item: \(reason)"
            case .updateFailed(let reason):
                return "Failed to update item: \(reason)"
            case .deletionFailed(let reason):
                return "Failed to delete item: \(reason)"
            case .invalidData(let reason):
                return "Invalid data: \(reason)"
            }
        }
    }

    // MARK: - Calendar Operations

    /// Get all available calendars for events
    func getAvailableCalendars() async throws -> [EKCalendar] {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        return eventStore.calendars(for: .event)
    }

    /// Find calendar by name
    func findCalendar(name: String) async throws -> EKCalendar? {
        let calendars = try await getAvailableCalendars()
        return calendars.first { $0.title == name }
    }

    /// Create calendar event from AI-detected event
    func createEvent(
        from aiEvent: CalendarEvent,
        calendarName: String?
    ) async throws -> String {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        // Find target calendar
        let calendar: EKCalendar
        if let name = calendarName, let found = try await findCalendar(name: name) {
            calendar = found
        } else {
            // Use default calendar
            guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
                throw CalendarServiceError.calendarNotFound("default")
            }
            calendar = defaultCalendar
        }

        // Create EKEvent
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = aiEvent.title
        event.notes = aiEvent.description
        event.location = aiEvent.location

        // Set start date/time
        var startDate = aiEvent.date
        if let timeStr = aiEvent.time {
            startDate = combineDateTime(date: aiEvent.date, time: timeStr) ?? aiEvent.date
        }
        event.startDate = startDate

        // Default 1-hour duration for timed events, all-day for no time
        if aiEvent.time != nil {
            event.endDate = startDate.addingTimeInterval(3600) // 1 hour
        } else {
            event.endDate = startDate
            event.isAllDay = true
        }

        // Save event
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw CalendarServiceError.creationFailed(error.localizedDescription)
        }
    }

    /// Update existing calendar event
    func updateEvent(
        eventId: String,
        from aiEvent: CalendarEvent
    ) async throws {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarServiceError.eventNotFound(eventId)
        }

        event.title = aiEvent.title
        event.notes = aiEvent.description
        event.location = aiEvent.location

        // Update start date/time
        var startDate = aiEvent.date
        if let timeStr = aiEvent.time {
            startDate = combineDateTime(date: aiEvent.date, time: timeStr) ?? aiEvent.date
        }
        event.startDate = startDate

        if aiEvent.time != nil {
            event.endDate = startDate.addingTimeInterval(3600)
            event.isAllDay = false
        } else {
            event.endDate = startDate
            event.isAllDay = true
        }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw CalendarServiceError.updateFailed(error.localizedDescription)
        }
    }

    /// Delete calendar event
    func deleteEvent(eventId: String) async throws {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarServiceError.eventNotFound(eventId)
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            throw CalendarServiceError.deletionFailed(error.localizedDescription)
        }
    }

    /// Find event by ID
    func findEvent(eventId: String) async throws -> EKEvent? {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        return eventStore.event(withIdentifier: eventId)
    }

    // MARK: - Reminders Operations

    /// Get default reminders list
    func getDefaultRemindersList() async throws -> EKCalendar {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        guard let defaultList = eventStore.defaultCalendarForNewReminders() else {
            throw CalendarServiceError.calendarNotFound("default reminders list")
        }

        return defaultList
    }

    /// Get all available reminder lists
    func getAvailableReminderLists() async throws -> [EKCalendar] {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        return eventStore.calendars(for: .reminder)
    }

    /// Find reminder list by name
    func findReminderList(name: String) async throws -> EKCalendar? {
        let lists = try await getAvailableReminderLists()
        return lists.first { $0.title == name }
    }

    /// Create reminder from deadline
    func createReminder(
        from deadline: Deadline,
        listName: String?
    ) async throws -> String {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        // Find target list
        let list: EKCalendar
        if let name = listName, let found = try await findReminderList(name: name) {
            list = found
        } else {
            list = try await getDefaultRemindersList()
        }

        // Create EKReminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = deadline.task
        reminder.notes = deadline.details

        // Set priority based on deadline priority
        switch deadline.priority {
        case .urgent:
            reminder.priority = 1 // High
        case .high:
            reminder.priority = 5 // Medium
        case .medium:
            reminder.priority = 5
        case .low:
            reminder.priority = 9 // Low
        }

        // Set due date
        let dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: deadline.deadline
        )
        reminder.dueDateComponents = dueDateComponents

        // Set completion status
        reminder.isCompleted = deadline.status == .completed

        // Save reminder
        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw CalendarServiceError.creationFailed(error.localizedDescription)
        }
    }

    /// Update existing reminder
    func updateReminder(
        reminderId: String,
        from deadline: Deadline
    ) async throws {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw CalendarServiceError.reminderNotFound(reminderId)
        }

        reminder.title = deadline.task
        reminder.notes = deadline.details

        switch deadline.priority {
        case .urgent:
            reminder.priority = 1
        case .high:
            reminder.priority = 5
        case .medium:
            reminder.priority = 5
        case .low:
            reminder.priority = 9
        }

        let dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: deadline.deadline
        )
        reminder.dueDateComponents = dueDateComponents
        reminder.isCompleted = deadline.status == .completed

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw CalendarServiceError.updateFailed(error.localizedDescription)
        }
    }

    /// Delete reminder
    func deleteReminder(reminderId: String) async throws {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw CalendarServiceError.reminderNotFound(reminderId)
        }

        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw CalendarServiceError.deletionFailed(error.localizedDescription)
        }
    }

    /// Find reminder by ID
    func findReminder(reminderId: String) async throws -> EKReminder? {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        return eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder
    }

    // MARK: - Two-Way Sync Detection

    /// Detect external changes to events in date range
    func detectExternalEventChanges(
        startDate: Date,
        endDate: Date,
        trackedEventIds: [String]
    ) async throws -> [ExternalEventChange] {
        guard await permissionService.isCalendarAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        var changes: [ExternalEventChange] = []

        // Get all events in range
        let calendars = try await getAvailableCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate)

        // Find tracked events that were deleted
        let currentEventIds = Set(events.map { $0.eventIdentifier })
        for trackedId in trackedEventIds {
            if !currentEventIds.contains(trackedId) {
                changes.append(ExternalEventChange(
                    externalId: trackedId,
                    changeType: .deleted,
                    event: nil
                ))
            }
        }

        // Find events that were created or updated externally
        for event in events {
            if !trackedEventIds.contains(event.eventIdentifier) {
                changes.append(ExternalEventChange(
                    externalId: event.eventIdentifier,
                    changeType: .created,
                    event: event
                ))
            }
        }

        return changes
    }

    /// Detect external changes to reminders
    func detectExternalReminderChanges(
        trackedReminderIds: [String]
    ) async throws -> [ExternalReminderChange] {
        guard await permissionService.isRemindersAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        var changes: [ExternalReminderChange] = []

        // Fetch all reminders
        let lists = try await getAvailableReminderLists()
        let predicate = eventStore.predicateForReminders(in: lists)

        return try await withThrowingTaskGroup(of: [ExternalReminderChange].self) { group in
            // Add timeout task (5 seconds to prevent hangs)
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                // Timeout reached - return empty array
                return []
            }

            // Add actual fetch task
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    self.eventStore.fetchReminders(matching: predicate) { reminders in
                        guard let reminders = reminders else {
                            continuation.resume(returning: [])
                            return
                        }

                        // Find tracked reminders that were deleted
                        let currentReminderIds = Set(reminders.map { $0.calendarItemIdentifier })
                        for trackedId in trackedReminderIds {
                            if !currentReminderIds.contains(trackedId) {
                                changes.append(ExternalReminderChange(
                                    externalId: trackedId,
                                    changeType: .deleted,
                                    reminder: nil
                                ))
                            }
                        }

                        // Find reminders that were created or updated externally
                        for reminder in reminders {
                            if !trackedReminderIds.contains(reminder.calendarItemIdentifier) {
                                changes.append(ExternalReminderChange(
                                    externalId: reminder.calendarItemIdentifier,
                                    changeType: .created,
                                    reminder: reminder
                                ))
                            }
                        }

                        continuation.resume(returning: changes)
                    }
                }
            }

            // Return whichever completes first, cancel the other
            if let result = try await group.next() {
                group.cancelAll()
                return result
            }
            return []
        }
    }

    // MARK: - Helpers

    /// Combine date and time string (HH:MM format)
    private func combineDateTime(date: Date, time: String) -> Date? {
        let components = time.split(separator: ":")
        // Handle both HH:MM and HH:MM:SS formats
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = hour
        dateComponents.minute = minute

        return Calendar.current.date(from: dateComponents)
    }
}

// MARK: - External Change Models

struct ExternalEventChange {
    let externalId: String
    let changeType: ChangeType
    let event: EKEvent?

    enum ChangeType {
        case created
        case updated
        case deleted
    }
}

struct ExternalReminderChange {
    let externalId: String
    let changeType: ChangeType
    let reminder: EKReminder?

    enum ChangeType {
        case created
        case updated
        case deleted
    }
}
