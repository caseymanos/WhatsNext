import Foundation

/// Service for detecting scheduling conflicts using AI
actor ConflictDetectionService {
    static let shared = ConflictDetectionService()

    private init() {}

    struct ConflictAnalysisResult: Sendable {
        let summary: String
        let conflicts: [SchedulingConflict]
        let detectedCount: Int
        let stepsUsed: Int
    }

    /// Analyze a conversation for scheduling conflicts
    func detectConflicts(
        conversationId: UUID,
        daysAhead: Int = 14
    ) async throws -> ConflictAnalysisResult {
        let supabase = SupabaseClientService.shared.client

        // Call the edge function
        struct RequestBody: Encodable {
            let conversationId: String
            let daysAhead: Int
        }

        struct FunctionResponse: Codable {
            let summary: String
            let conflicts: [SchedulingConflictResponse]
            let detectedCount: Int
            let stats: Stats

            struct Stats: Codable {
                let stepsUsed: Int
            }
        }

        let requestBody = RequestBody(
            conversationId: conversationId.uuidString,
            daysAhead: daysAhead
        )

        let response: FunctionResponse = try await supabase.functions
            .invoke(
                "detect-conflicts-agent",
                options: .init(body: requestBody)
            )

        // Convert to domain models
        let conflicts = response.conflicts.map { $0.toDomain() }

        return ConflictAnalysisResult(
            summary: response.summary,
            conflicts: conflicts,
            detectedCount: response.detectedCount,
            stepsUsed: response.stats.stepsUsed
        )
    }
}

// MARK: - Models

struct SchedulingConflict: Identifiable, Sendable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let conflictType: ConflictType
    let severity: Severity
    let description: String
    let affectedItems: [String]
    let suggestedResolution: String
    let status: Status
    let createdAt: Date

    enum ConflictType: String, Codable, Sendable {
        case timeOverlap = "time_overlap"
        case deadlinePressure = "deadline_pressure"
        case travelTime = "travel_time"
        case capacity = "capacity"
        case timeUnclear = "time_unclear"
        case noBuffer = "no_buffer"
        case deadlineTight = "deadline_tight"

        var displayName: String {
            switch self {
            case .timeOverlap: return "Time Overlap"
            case .deadlinePressure: return "Deadline Pressure"
            case .travelTime: return "Travel Time"
            case .capacity: return "Schedule Overload"
            case .timeUnclear: return "Unclear Times"
            case .noBuffer: return "No Buffer"
            case .deadlineTight: return "Tight Deadline"
            }
        }

        var icon: String {
            switch self {
            case .timeOverlap: return "clock.badge.exclamationmark"
            case .deadlinePressure: return "exclamationmark.triangle"
            case .travelTime: return "car.circle"
            case .capacity: return "calendar.badge.exclamationmark"
            case .timeUnclear: return "questionmark.circle"
            case .noBuffer: return "clock.arrow.circlepath"
            case .deadlineTight: return "hourglass"
            }
        }
    }

    enum Severity: String, Codable, Sendable {
        case urgent = "urgent"
        case high = "high"
        case medium = "medium"
        case low = "low"

        var color: String {
            switch self {
            case .urgent: return "red"
            case .high: return "orange"
            case .medium: return "yellow"
            case .low: return "green"
            }
        }

        var sortOrder: Int {
            switch self {
            case .urgent: return 0
            case .high: return 1
            case .medium: return 2
            case .low: return 3
            }
        }
    }

    enum Status: String, Codable, Sendable {
        case unresolved = "unresolved"
        case resolved = "resolved"
        case dismissed = "dismissed"
    }
}

// Response model for decoding
struct SchedulingConflictResponse: Codable {
    let id: String
    let conversation_id: String
    let user_id: String
    let conflict_type: String
    let severity: String
    let description: String
    let affected_items: [String]
    let suggested_resolution: String
    let status: String
    let created_at: String

    func toDomain() -> SchedulingConflict {
        SchedulingConflict(
            id: UUID(uuidString: id) ?? UUID(),
            conversationId: UUID(uuidString: conversation_id) ?? UUID(),
            userId: UUID(uuidString: user_id) ?? UUID(),
            conflictType: SchedulingConflict.ConflictType(rawValue: conflict_type) ?? .timeOverlap,
            severity: SchedulingConflict.Severity(rawValue: severity) ?? .low,
            description: description,
            affectedItems: affected_items,
            suggestedResolution: suggested_resolution,
            status: SchedulingConflict.Status(rawValue: status) ?? .unresolved,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }
}
