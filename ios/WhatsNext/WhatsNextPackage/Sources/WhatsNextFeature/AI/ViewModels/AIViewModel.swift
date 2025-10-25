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

    // Current user ID (required for user-specific features)
    var currentUserId: UUID?

    private var service: AIServiceProtocol {
        DebugSettings.shared.useLiveAI ? SupabaseAIService() : MockAIService()
    }

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif


