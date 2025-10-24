import Foundation

/// Response from proactive-assistant Edge Function (multi-step agent)
public struct ProactiveAssistantResponse: Codable {
    public let message: String
    public let insights: ProactiveInsights
    public let toolsUsed: [ToolExecution]

    public struct ProactiveInsights: Codable {
        public let upcomingEvents: [CalendarEvent]
        public let pendingRSVPs: [RSVPTracking]
        public let upcomingDeadlines: [Deadline]
        public let schedulingConflicts: [SchedulingConflict]
    }

    public struct SchedulingConflict: Codable, Hashable {
        public let date: String
        public let event1: String
        public let event2: String
        public let reason: String
    }

    public struct ToolExecution: Codable {
        public let tool: String
        public let params: [String: String]?

        enum CodingKeys: String, CodingKey {
            case tool
            case params
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tool = try container.decode(String.self, forKey: .tool)
            // Params can be any JSON object, we'll simplify to string dict
            params = try container.decodeIfPresent([String: String].self, forKey: .params)
        }
    }
}

/// Request to proactive-assistant Edge Function
public struct ProactiveAssistantRequest: Codable {
    public let conversationId: String
    public let userId: String
    public let query: String?

    public init(conversationId: UUID, userId: UUID, query: String? = nil) {
        self.conversationId = conversationId.uuidString
        self.userId = userId.uuidString
        self.query = query
    }
}
