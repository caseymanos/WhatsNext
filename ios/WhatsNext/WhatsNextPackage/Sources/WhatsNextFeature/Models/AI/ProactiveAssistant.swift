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
        // Params is not strictly typed since it can contain mixed types - ignore it for now

        enum CodingKeys: String, CodingKey {
            case tool
        }

        public init(tool: String) {
            self.tool = tool
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tool = try container.decode(String.self, forKey: .tool)
            // Skip params decoding to avoid type mismatch errors
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tool, forKey: .tool)
        }
    }
}

/// Request to proactive-assistant Edge Function
public struct ProactiveAssistantRequest: Codable {
    public let conversationId: String
    public let query: String?

    public init(conversationId: UUID, query: String? = nil) {
        self.conversationId = conversationId.uuidString
        self.query = query
    }
}
