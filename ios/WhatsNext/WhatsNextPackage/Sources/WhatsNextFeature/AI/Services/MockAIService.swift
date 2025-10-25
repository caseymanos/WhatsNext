import Foundation
#if AI_FEATURES

final class MockAIService: AIServiceProtocol {
    func extractCalendarEvents(conversationId: UUID) async throws -> [CalendarEvent] {
        let now = Date()
        let cal1 = CalendarEvent(
            id: UUID(),
            conversationId: conversationId,
            messageId: nil,
            title: "Team Standup",
            date: now.addingTimeInterval(3600),
            time: "10:00",
            location: "Conference Room A",
            description: "Daily standup meeting",
            category: .work,
            confidence: 0.95
        )
        let cal2 = CalendarEvent(
            id: UUID(),
            conversationId: conversationId,
            messageId: nil,
            title: "Dentist Appointment",
            date: now.addingTimeInterval(86400 * 2 + 3600 * 9),
            time: "14:30",
            location: "Downtown Clinic",
            description: "Regular checkup",
            category: .medical,
            confidence: 0.88
        )
        return [cal1, cal2]
    }

    func trackDecisions(conversationId: UUID, daysBack: Int) async throws -> [Decision] {
        return [
            Decision(
                conversationId: conversationId,
                decisionText: "Pizza for dinner on Friday",
                category: .food,
                decidedBy: nil,
                deadline: Date().addingTimeInterval(86400 * 2)
            ),
            Decision(
                conversationId: conversationId,
                decisionText: "Go to the zoo this weekend",
                category: .activity,
                decidedBy: nil,
                deadline: Date().addingTimeInterval(86400 * 5)
            ),
            Decision(
                conversationId: conversationId,
                decisionText: "Buy new backpack for school",
                category: .purchase,
                decidedBy: nil,
                deadline: Date().addingTimeInterval(86400 * 10)
            )
        ]
    }

    func detectPriority(conversationId: UUID) async throws -> [PriorityMessage] {
        return [
            PriorityMessage(
                messageId: UUID(),
                priority: .urgent,
                reason: "School permission slip due tomorrow",
                actionRequired: true
            ),
            PriorityMessage(
                messageId: UUID(),
                priority: .high,
                reason: "Doctor appointment needs to be rescheduled",
                actionRequired: true
            ),
            PriorityMessage(
                messageId: UUID(),
                priority: .medium,
                reason: "Grocery list for weekend shopping",
                actionRequired: false
            )
        ]
    }

    func trackRSVPs(conversationId: UUID, userId: UUID) async throws -> (rsvps: [RSVPTracking], summary: TrackRSVPsResponse.RSVPSummary) {
        let rsvp1 = RSVPTracking(
            messageId: UUID(),
            conversationId: conversationId,
            userId: userId,
            eventName: "Birthday Party at Sarah's",
            deadline: Date().addingTimeInterval(86400 * 3),
            eventDate: Date().addingTimeInterval(86400 * 7),
            status: .pending
        )
        let rsvp2 = RSVPTracking(
            messageId: UUID(),
            conversationId: conversationId,
            userId: userId,
            eventName: "School Play Rehearsal",
            deadline: Date().addingTimeInterval(86400 * 1),
            eventDate: Date().addingTimeInterval(86400 * 5),
            status: .pending
        )

        let summary = TrackRSVPsResponse.RSVPSummary(
            newCount: 2,
            totalPending: 2,
            pendingRSVPs: [rsvp1, rsvp2]
        )

        return ([rsvp1, rsvp2], summary)
    }

    func extractDeadlines(conversationId: UUID, userId: UUID) async throws -> [Deadline] {
        return [
            Deadline(
                conversationId: conversationId,
                userId: userId,
                task: "Submit permission slip for field trip",
                deadline: Date().addingTimeInterval(86400),
                category: .school,
                priority: .urgent,
                details: "Needs parent signature"
            ),
            Deadline(
                conversationId: conversationId,
                userId: userId,
                task: "Pay electricity bill",
                deadline: Date().addingTimeInterval(86400 * 5),
                category: .bills,
                priority: .high,
                details: "$150 due"
            ),
            Deadline(
                conversationId: conversationId,
                userId: userId,
                task: "Fill out health insurance form",
                deadline: Date().addingTimeInterval(86400 * 14),
                category: .forms,
                priority: .medium,
                details: "For annual enrollment"
            )
        ]
    }

    func proactiveAssistant(conversationId: UUID, userId: UUID, query: String?) async throws -> ProactiveAssistantResponse {
        let events = try await extractCalendarEvents(conversationId: conversationId)
        let rsvpResult = try await trackRSVPs(conversationId: conversationId, userId: userId)
        let deadlines = try await extractDeadlines(conversationId: conversationId, userId: userId)

        let insights = ProactiveAssistantResponse.ProactiveInsights(
            upcomingEvents: events,
            pendingRSVPs: rsvpResult.rsvps,
            upcomingDeadlines: deadlines,
            schedulingConflicts: []
        )

        let toolsUsed = [
            ProactiveAssistantResponse.ToolExecution(tool: "getRecentMessages", params: nil),
            ProactiveAssistantResponse.ToolExecution(tool: "getCalendarEvents", params: nil),
            ProactiveAssistantResponse.ToolExecution(tool: "getPendingRSVPs", params: nil),
            ProactiveAssistantResponse.ToolExecution(tool: "getDeadlines", params: nil)
        ]

        return ProactiveAssistantResponse(
            message: "You have 2 upcoming events, 2 pending RSVPs, and 3 deadlines. Your most urgent task is submitting the permission slip tomorrow.",
            insights: insights,
            toolsUsed: toolsUsed
        )
    }
}

extension ProactiveAssistantResponse.ToolExecution {
    init(tool: String, params: [String: String]?) {
        self.tool = tool
        self.params = params
    }
}

#endif


