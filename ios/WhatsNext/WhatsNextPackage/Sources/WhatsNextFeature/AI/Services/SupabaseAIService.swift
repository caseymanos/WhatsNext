import Foundation
import Supabase
#if AI_FEATURES

struct ExtractCalendarEventsRequest: Encodable {
    let conversationId: String
    let daysBack: Int
}

struct TrackDecisionsRequest: Encodable {
    let conversationId: String
    let daysBack: Int
}

struct DetectPriorityRequest: Encodable {
    let conversationId: String
}

struct TrackRSVPsRequest: Encodable {
    let conversationId: String
    let userId: String
}

struct ExtractDeadlinesRequest: Encodable {
    let conversationId: String
    let userId: String
}

enum SupabaseAIError: Error, LocalizedError {
    case invalidResponse
    case notAuthenticated
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI function"
        case .notAuthenticated: return "You must be signed in to use AI"
        case .backend(let m): return m
        }
    }
}

final class SupabaseAIService: AIServiceProtocol {
    private let client = SupabaseClientService.shared

    func extractCalendarEvents(conversationId: UUID) async throws -> [CalendarEvent] {
        // Ensure we have a session so Authorization header is present
        let _ = try await client.auth.session

        let payload = ExtractCalendarEventsRequest(
            conversationId: conversationId.uuidString,
            daysBack: 7
        )

        do {
            let response: ExtractCalendarEventsResponse = try await client.client.functions
                .invoke("extract-calendar-events", options: .init(body: payload))

            // Map to CalendarEvent model
            let mapped: [CalendarEvent] = response.events.map { e in
                // Parse date from YYYY-MM-DD string
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let parsedDate = formatter.date(from: e.date) ?? Date()

                return CalendarEvent(
                    id: UUID(),
                    conversationId: conversationId,
                    messageId: nil,
                    title: e.title,
                    date: parsedDate,
                    time: e.time,
                    location: e.location,
                    description: e.description,
                    category: e.category,
                    confidence: e.confidence
                )
            }
            return mapped
        } catch {
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }

    func trackDecisions(conversationId: UUID, daysBack: Int) async throws -> [Decision] {
        let _ = try await client.auth.session

        let payload = TrackDecisionsRequest(
            conversationId: conversationId.uuidString,
            daysBack: daysBack
        )

        do {
            let response: TrackDecisionsResponse = try await client.client.functions
                .invoke("track-decisions", options: .init(body: payload))

            let mapped: [Decision] = response.decisions.map { d in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let deadline = d.deadline.flatMap { formatter.date(from: $0) }

                return Decision(
                    conversationId: conversationId,
                    decisionText: d.decisionText,
                    category: d.category,
                    decidedBy: d.decidedBy.flatMap { UUID(uuidString: $0) },
                    deadline: deadline
                )
            }
            return mapped
        } catch {
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }

    func detectPriority(conversationId: UUID) async throws -> [PriorityMessage] {
        let _ = try await client.auth.session

        let payload = DetectPriorityRequest(conversationId: conversationId.uuidString)

        do {
            let response: DetectPriorityResponse = try await client.client.functions
                .invoke("detect-priority", options: .init(body: payload))

            let mapped: [PriorityMessage] = response.priorityMessages.map { p in
                PriorityMessage(
                    messageId: UUID(uuidString: p.messageId) ?? UUID(),
                    priority: p.priority,
                    reason: p.reason,
                    actionRequired: p.actionRequired
                )
            }
            return mapped
        } catch {
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }

    func trackRSVPs(conversationId: UUID, userId: UUID) async throws -> (rsvps: [RSVPTracking], summary: TrackRSVPsResponse.RSVPSummary) {
        let _ = try await client.auth.session

        let payload = TrackRSVPsRequest(
            conversationId: conversationId.uuidString,
            userId: userId.uuidString
        )

        do {
            let response: TrackRSVPsResponse = try await client.client.functions
                .invoke("track-rsvps", options: .init(body: payload))

            return (response.summary.pendingRSVPs, response.summary)
        } catch {
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }

    func extractDeadlines(conversationId: UUID, userId: UUID) async throws -> [Deadline] {
        let _ = try await client.auth.session

        let payload = ExtractDeadlinesRequest(
            conversationId: conversationId.uuidString,
            userId: userId.uuidString
        )

        do {
            let response: ExtractDeadlinesResponse = try await client.client.functions
                .invoke("extract-deadlines", options: .init(body: payload))

            let isoFormatter = ISO8601DateFormatter()
            let mapped: [Deadline] = response.deadlines.map { d in
                let deadline = isoFormatter.date(from: d.deadline) ?? Date()

                return Deadline(
                    messageId: UUID(uuidString: d.messageId),
                    conversationId: conversationId,
                    userId: userId,
                    task: d.task,
                    deadline: deadline,
                    category: d.category,
                    priority: d.priority,
                    details: d.details
                )
            }
            return mapped
        } catch {
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }

    func proactiveAssistant(conversationId: UUID, userId: UUID, query: String?) async throws -> ProactiveAssistantResponse {
        let _ = try await client.auth.session

        let payload = ProactiveAssistantRequest(
            conversationId: conversationId,
            query: query
        )

        do {
            let response: ProactiveAssistantResponse = try await client.client.functions
                .invoke("proactive-assistant", options: .init(body: payload))

            return response
        } catch let error as FunctionsError {
            // Debug logging to see what we're getting
            print("[SupabaseAIService] proactiveAssistant FunctionsError: \(error)")

            // Extract data from FunctionsError
            switch error {
            case .httpError(let code, let data):
                print("[SupabaseAIService] HTTP Error \(code) with \(data.count) bytes")

                // Try to decode the JSON error response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String {
                    print("[SupabaseAIService] Extracted error message: \(errorMessage)")
                    throw SupabaseAIError.backend(errorMessage)
                }

                // If JSON parsing failed, try raw string
                if let errorString = String(data: data, encoding: .utf8) {
                    print("[SupabaseAIService] Raw error response: \(errorString)")
                    throw SupabaseAIError.backend(errorString)
                }

                // Fall back to generic message
                throw SupabaseAIError.backend("Edge Function returned error \(code)")

            case .relayError:
                throw SupabaseAIError.backend("Function relay error")

            @unknown default:
                throw SupabaseAIError.backend(error.localizedDescription)
            }
        } catch {
            // Handle non-FunctionsError cases
            print("[SupabaseAIService] Non-FunctionsError: \(error)")
            throw SupabaseAIError.backend(error.localizedDescription)
        }
    }
}

#endif


