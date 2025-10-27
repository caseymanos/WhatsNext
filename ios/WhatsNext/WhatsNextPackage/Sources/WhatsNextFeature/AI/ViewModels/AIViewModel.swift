import Foundation
#if AI_FEATURES
import SwiftUI

@MainActor
final class AIViewModel: ObservableObject {
    @Published var selectedConversations: Set<UUID> = []
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    // Feature-specific state
    @Published var eventsByConversation: [UUID: [CalendarEvent]] = [:]
    @Published var decisionsByConversation: [UUID: [Decision]] = [:]
    @Published var priorityMessagesByConversation: [UUID: [PriorityMessage]] = [:]
    @Published var rsvpsByConversation: [UUID: [RSVPTracking]] = [:]
    @Published var deadlinesByConversation: [UUID: [Deadline]] = [:]
    @Published var proactiveInsights: ProactiveAssistantResponse?

    // Calendar sync state
    @Published var syncSettings: CalendarSyncSettings?
    @Published var isSyncing = false
    @Published var syncErrorMessage: String?
    @Published var syncProgress: SyncProgress?

    // Sync progress tracking
    public struct SyncProgress {
        public var current: Int
        public var total: Int
        public var currentItem: String
    }

    // Conflict detection state
    @Published var conflictsByConversation: [UUID: [SchedulingConflict]] = [:]
    @Published var isDetectingConflicts = false
    @Published var conflictDetectionError: String?

    // Current user ID (required for user-specific features)
    var currentUserId: UUID?

    private var service: AIServiceProtocol {
        DebugSettings.shared.useLiveAI ? SupabaseAIService() : MockAIService()
    }

    private let syncEngine = CalendarSyncEngine()
    private let conflictDetectionService = ConflictDetectionService.shared

    // MARK: - Calendar Events
    func analyzeSelectedForEvents() async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        var allExtractedEvents: [CalendarEvent] = []

        for id in selectedConversations {
            do {
                let events = try await service.extractCalendarEvents(conversationId: id)
                eventsByConversation[id] = events
                allExtractedEvents.append(contentsOf: events)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Auto-sync after extraction if enabled
        if let settings = syncSettings, settings.autoSyncEnabled, !allExtractedEvents.isEmpty {
            await autoSyncEvents(allExtractedEvents)
        }
    }

    // MARK: - Decisions
    func analyzeSelectedForDecisions(daysBack: Int = 7) async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in selectedConversations {
            do {
                let decisions = try await service.trackDecisions(conversationId: id, daysBack: daysBack)
                decisionsByConversation[id] = decisions
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Priority Messages
    func analyzeSelectedForPriority() async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in selectedConversations {
            do {
                let messages = try await service.detectPriority(conversationId: id)
                priorityMessagesByConversation[id] = messages
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - RSVPs
    func analyzeSelectedForRSVPs() async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in selectedConversations {
            do {
                let (rsvps, _) = try await service.trackRSVPs(conversationId: id, userId: userId)
                rsvpsByConversation[id] = rsvps
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Deadlines
    func analyzeSelectedForDeadlines() async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in selectedConversations {
            do {
                let deadlines = try await service.extractDeadlines(conversationId: id, userId: userId)
                deadlinesByConversation[id] = deadlines
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Proactive Assistant
    func runProactiveAssistant(conversationId: UUID, query: String? = nil) async {
        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        do {
            let response = try await service.proactiveAssistant(
                conversationId: conversationId,
                userId: userId,
                query: query
            )
            proactiveInsights = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - All Features
    func analyzeAll(conversationId: UUID) async {
        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        // Run all analyses in parallel
        async let events = service.extractCalendarEvents(conversationId: conversationId)
        async let decisions = service.trackDecisions(conversationId: conversationId, daysBack: 7)
        async let priority = service.detectPriority(conversationId: conversationId)
        async let rsvps = service.trackRSVPs(conversationId: conversationId, userId: userId)
        async let deadlines = service.extractDeadlines(conversationId: conversationId, userId: userId)

        do {
            let (evts, decs, pri, (rsvList, _), ddls) = try await (events, decisions, priority, rsvps, deadlines)
            eventsByConversation[conversationId] = evts
            decisionsByConversation[conversationId] = decs
            priorityMessagesByConversation[conversationId] = pri
            rsvpsByConversation[conversationId] = rsvList
            deadlinesByConversation[conversationId] = ddls

            // Auto-sync if enabled
            await autoSyncIfEnabled(events: evts, deadlines: ddls)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Calendar Sync

    /// Load sync settings for current user
    func loadSyncSettings() async {
        guard let userId = currentUserId else { return }

        do {
            syncSettings = try await syncEngine.fetchSyncSettings(userId: userId)
        } catch {
            // Create default settings if none exist
            syncSettings = try? await syncEngine.createDefaultSettings(userId: userId)
        }
    }

    /// Update sync settings
    func updateSyncSettings(_ settings: CalendarSyncSettings) async throws {
        try await syncEngine.updateSyncSettings(settings)
        syncSettings = settings
    }

    /// Auto-sync events with progress tracking
    private func autoSyncEvents(_ events: [CalendarEvent]) async {
        guard let userId = currentUserId else { return }
        guard let settings = syncSettings, settings.hasAnySyncEnabled else { return }

        // Filter to only pending events (not yet synced)
        let pendingEvents = events.filter { $0.appleCalendarEventId == nil && $0.googleCalendarEventId == nil }
        guard !pendingEvents.isEmpty else { return }

        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
        }
        syncErrorMessage = nil

        for (index, event) in pendingEvents.enumerated() {
            // Update progress
            syncProgress = SyncProgress(
                current: index + 1,
                total: pendingEvents.count,
                currentItem: event.title
            )

            do {
                try await syncEngine.syncCalendarEvent(event, userId: userId)
            } catch {
                syncErrorMessage = error.localizedDescription
                // Continue syncing remaining events even if one fails
            }
        }
    }

    /// Auto-sync events and deadlines if enabled (used by analyzeAll)
    private func autoSyncIfEnabled(events: [CalendarEvent], deadlines: [Deadline]) async {
        guard let userId = currentUserId else { return }
        guard let settings = syncSettings else { return }
        guard settings.autoSyncEnabled && settings.hasAnySyncEnabled else { return }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        // Sync events
        for event in events {
            do {
                try await syncEngine.syncCalendarEvent(event, userId: userId)
            } catch {
                syncErrorMessage = error.localizedDescription
            }
        }

        // Sync deadlines
        if settings.appleRemindersEnabled {
            for deadline in deadlines {
                do {
                    try await syncEngine.syncDeadlineToReminders(deadline, userId: userId)
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Manually sync a specific event
    func syncEvent(_ event: CalendarEvent) async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            try await syncEngine.syncCalendarEvent(event, userId: userId)

            // Refresh events to show updated sync status
            if let conversationId = eventsByConversation.first(where: { $0.value.contains(where: { $0.id == event.id }) })?.key {
                await refreshEvents(conversationId: conversationId)
            }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Create event in Apple Calendar and return the event ID
    /// This is for the tap-to-open flow where we auto-sync before opening
    func createEventInCalendar(_ event: CalendarEvent) async throws -> String {
        guard let settings = syncSettings else {
            throw NSError(domain: "AIViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync settings not found"])
        }

        guard settings.appleCalendarEnabled else {
            throw NSError(domain: "AIViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Calendar sync is not enabled"])
        }

        // Get calendar name from category mapping
        let calendarName = settings.calendarName(for: event.category.rawValue)

        // Create event in Calendar app
        let eventKitService = EventKitService()
        let eventId = try await eventKitService.createEvent(from: event, calendarName: calendarName)

        // Update database with the external ID
        let supabase = SupabaseClientService.shared
        try await supabase.database
            .from("calendar_events")
            .update(["apple_calendar_event_id": eventId])
            .eq("id", value: event.id)
            .execute()

        return eventId
    }

    /// Update a specific event with its Apple Calendar ID after syncing
    /// This prevents duplicate calendar entries when tapping the same event multiple times
    func updateEventWithSyncId(eventId: UUID, appleCalendarEventId: String) {
        // Find the event in the dictionary and update it
        for (convId, events) in eventsByConversation {
            if let index = events.firstIndex(where: { $0.id == eventId }) {
                var updatedEvent = events[index]
                updatedEvent.appleCalendarEventId = appleCalendarEventId
                updatedEvent.syncStatus = "synced"

                // Update the array with the modified event
                var updatedEvents = events
                updatedEvents[index] = updatedEvent
                eventsByConversation[convId] = updatedEvents

                print("✅ Updated local event with sync ID: \(appleCalendarEventId)")
                return
            }
        }
    }

    /// Manually sync a specific deadline
    func syncDeadline(_ deadline: Deadline) async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            try await syncEngine.syncDeadlineToReminders(deadline, userId: userId)

            // Refresh deadlines to show updated sync status
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Sync all pending items
    func syncAllPending() async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            async let eventsSync = syncEngine.syncAllPendingEvents(userId: userId)
            async let deadlinesSync = syncEngine.syncAllPendingDeadlines(userId: userId)
            let (eventsResult, deadlinesResult) = try await (eventsSync, deadlinesSync)

            // Aggregate results
            let totalSuccess = eventsResult.successCount + deadlinesResult.successCount
            let totalFailures = eventsResult.failureCount + deadlinesResult.failureCount

            if totalFailures > 0 {
                // Show detailed error information
                var errorDetails = [String]()
                if !eventsResult.errors.isEmpty {
                    errorDetails.append("Events: \(eventsResult.errors.count) failed")
                }
                if !deadlinesResult.errors.isEmpty {
                    errorDetails.append("Deadlines: \(deadlinesResult.errors.count) failed")
                }

                syncErrorMessage = "Sync completed with \(totalFailures) errors. \(errorDetails.joined(separator: ", ")). Synced \(totalSuccess) successfully."
            } else if totalSuccess > 0 {
                // All successful
                syncErrorMessage = nil // Clear any previous errors
            }

            // Automatically trigger conflict detection after successful sync
            if totalSuccess > 0 {
                await detectConflictsForSelectedConversations()
            }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Process retry queue
    func processRetryQueue() async {
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await syncEngine.processSyncQueue(userId: userId)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Detect external changes from Apple Calendar/Reminders
    func detectExternalChanges() async {
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            async let calendarChanges = syncEngine.detectAndSyncExternalCalendarChanges(userId: userId)
            async let reminderChanges = syncEngine.detectAndSyncExternalReminderChanges(userId: userId)
            try await (calendarChanges, reminderChanges)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Refresh events for a conversation (used after sync to update status)
    private func refreshEvents(conversationId: UUID) async {
        do {
            let events = try await service.extractCalendarEvents(conversationId: conversationId)
            eventsByConversation[conversationId] = events
        } catch {
            // Silently fail - this is just a refresh
        }
    }

    /// Refresh deadlines for a conversation (used after sync to update status)
    private func refreshDeadlines(conversationId: UUID) async {
        guard let userId = currentUserId else { return }

        do {
            let deadlines = try await service.extractDeadlines(conversationId: conversationId, userId: userId)
            deadlinesByConversation[conversationId] = deadlines
        } catch {
            // Silently fail - this is just a refresh
        }
    }

    // MARK: - Deadline Actions

    /// Mark a deadline as completed
    func markDeadlineComplete(_ deadline: Deadline) async {
        do {
            let supabase = SupabaseClientService.shared

            // Update status to completed
            let now = ISO8601DateFormatter().string(from: Date())
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.completed.rawValue,
                    "completed_at": now
                ])
                .eq("id", value: deadline.id)
                .execute()

            // Update reminder if synced
            if let reminderId = deadline.appleReminderId {
                do {
                    var updatedDeadline = deadline
                    updatedDeadline.status = .completed
                    try await EventKitService().updateReminder(reminderId: reminderId, from: updatedDeadline)
                } catch {
                    // Silently fail reminder update
                }
            }

            // Refresh the deadline list
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            errorMessage = "Failed to mark as complete: \(error.localizedDescription)"
        }
    }

    /// Mark a deadline as pending (uncomplete)
    func markDeadlinePending(_ deadline: Deadline) async {
        do {
            let supabase = SupabaseClientService.shared

            // Update status to pending and clear completed_at
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.pending.rawValue,
                    "completed_at": ""  // Empty string to clear the timestamp
                ])
                .eq("id", value: deadline.id)
                .execute()

            // Update reminder if synced
            if let reminderId = deadline.appleReminderId {
                do {
                    var updatedDeadline = deadline
                    updatedDeadline.status = .pending
                    try await EventKitService().updateReminder(reminderId: reminderId, from: updatedDeadline)
                } catch {
                    // Silently fail reminder update
                }
            }

            // Refresh the deadline list
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            errorMessage = "Failed to mark as pending: \(error.localizedDescription)"
        }
    }

    // MARK: - Conflict Detection

    /// Detect scheduling conflicts for selected conversations
    func detectConflictsForSelectedConversations() async {
        guard !selectedConversations.isEmpty else { return }

        isDetectingConflicts = true
        defer { isDetectingConflicts = false }
        conflictDetectionError = nil

        for conversationId in selectedConversations {
            do {
                let result = try await conflictDetectionService.detectConflicts(conversationId: conversationId)
                conflictsByConversation[conversationId] = result.conflicts
            } catch {
                conflictDetectionError = error.localizedDescription
            }
        }
    }

    /// Get total count of unresolved conflicts across all conversations
    var totalUnresolvedConflictsCount: Int {
        conflictsByConversation.values
            .flatMap { $0 }
            .filter { $0.status != .resolved }
            .count
    }

    /// Get conflicts for a specific conversation
    func conflicts(for conversationId: UUID) -> [SchedulingConflict] {
        conflictsByConversation[conversationId] ?? []
    }
}

#endif


