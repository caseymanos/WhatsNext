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

    // Current user ID (required for user-specific features)
    var currentUserId: UUID?

    private var service: AIServiceProtocol {
        DebugSettings.shared.useLiveAI ? SupabaseAIService() : MockAIService()
    }

    private let syncEngine = CalendarSyncEngine()

    // MARK: - Calendar Events
    func analyzeSelectedForEvents() async {
        guard !selectedConversations.isEmpty else {
            errorMessage = "Select at least one conversation"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in selectedConversations {
            do {
                let events = try await service.extractCalendarEvents(conversationId: id)
                eventsByConversation[id] = events
            } catch {
                errorMessage = error.localizedDescription
            }
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

    /// Auto-sync events and deadlines if enabled
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
            try await (eventsSync, deadlinesSync)
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
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.completed.rawValue,
                    "completed_at": Date()
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

            // Update status to pending
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.pending.rawValue,
                    "completed_at": NSNull()
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
}

#endif


