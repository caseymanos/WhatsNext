import Foundation

/// Service for managing Google Calendar events via Google Calendar API v3
final class GoogleCalendarService {
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    // MARK: - Error Handling

    enum GoogleCalendarError: LocalizedError {
        case notAuthenticated
        case tokenExpired
        case invalidCredentials
        case calendarNotFound(String)
        case eventNotFound(String)
        case apiError(statusCode: Int, message: String)
        case networkError(Error)
        case decodingError(Error)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated with Google Calendar"
            case .tokenExpired:
                return "Google Calendar access token expired"
            case .invalidCredentials:
                return "Invalid Google Calendar credentials"
            case .calendarNotFound(let id):
                return "Calendar with ID '\(id)' not found"
            case .eventNotFound(let id):
                return "Event with ID '\(id)' not found"
            case .apiError(let statusCode, let message):
                return "Google Calendar API error (\(statusCode)): \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Google Calendar API"
            }
        }
    }

    // MARK: - Authentication

    /// Check if credentials are valid and not expired
    func validateCredentials(_ credentials: GoogleOAuthCredentials) -> Bool {
        return !credentials.isExpired
    }

    /// Refresh access token using refresh token
    func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String
    ) async throws -> GoogleOAuthCredentials {
        let url = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            let tokenResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

            return GoogleOAuthCredentials(
                accessToken: tokenResponse.accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
                scope: tokenResponse.scope ?? "https://www.googleapis.com/auth/calendar"
            )
        } catch let error as GoogleCalendarError {
            throw error
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    // MARK: - Calendar Operations

    /// List all calendars for the authenticated user
    func listCalendars(credentials: GoogleOAuthCredentials) async throws -> [GoogleCalendar] {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let url = URL(string: "\(baseURL)/users/me/calendarList")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            let calendarList = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
            return calendarList.items
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    /// Get specific calendar by ID
    func getCalendar(
        calendarId: String,
        credentials: GoogleOAuthCredentials
    ) async throws -> GoogleCalendar {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let url = URL(string: "\(baseURL)/calendars/\(encodedId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw GoogleCalendarError.calendarNotFound(calendarId)
                }
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            return try JSONDecoder().decode(GoogleCalendar.self, from: data)
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    // MARK: - Event Operations

    /// Create event in Google Calendar
    func createEvent(
        calendarId: String,
        event: GoogleCalendarEvent,
        credentials: GoogleOAuthCredentials
    ) async throws -> GoogleCalendarEventResponse {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let url = URL(string: "\(baseURL)/calendars/\(encodedId)/events")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(event)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            return try JSONDecoder().decode(GoogleCalendarEventResponse.self, from: data)
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    /// Update existing event in Google Calendar
    func updateEvent(
        calendarId: String,
        eventId: String,
        event: GoogleCalendarEvent,
        credentials: GoogleOAuthCredentials
    ) async throws -> GoogleCalendarEventResponse {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(event)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw GoogleCalendarError.eventNotFound(eventId)
                }
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            return try JSONDecoder().decode(GoogleCalendarEventResponse.self, from: data)
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    /// Delete event from Google Calendar
    func deleteEvent(
        calendarId: String,
        eventId: String,
        credentials: GoogleOAuthCredentials
    ) async throws {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw GoogleCalendarError.eventNotFound(eventId)
                }
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as GoogleCalendarError {
            throw error
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    /// Get event from Google Calendar
    func getEvent(
        calendarId: String,
        eventId: String,
        credentials: GoogleOAuthCredentials
    ) async throws -> GoogleCalendarEvent {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw GoogleCalendarError.eventNotFound(eventId)
                }
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            return try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }

    /// List events in date range for two-way sync detection
    func listEvents(
        calendarId: String,
        timeMin: Date,
        timeMax: Date,
        credentials: GoogleOAuthCredentials
    ) async throws -> [GoogleCalendarEvent] {
        guard !credentials.isExpired else {
            throw GoogleCalendarError.tokenExpired
        }

        let formatter = ISO8601DateFormatter()
        let timeMinStr = formatter.string(from: timeMin)
        let timeMaxStr = formatter.string(from: timeMax)

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedCalendarId)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMinStr),
            URLQueryItem(name: "timeMax", value: timeMaxStr),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        guard let url = components.url else {
            throw GoogleCalendarError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            let eventList = try JSONDecoder().decode(GoogleCalendarEventListResponse.self, from: data)
            return eventList.items
        } catch let error as GoogleCalendarError {
            throw error
        } catch let error as DecodingError {
            throw GoogleCalendarError.decodingError(error)
        } catch {
            throw GoogleCalendarError.networkError(error)
        }
    }
}

// MARK: - Supporting Models

private struct TokenRefreshResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let scope: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

private struct GoogleCalendarEventListResponse: Codable {
    let items: [GoogleCalendarEvent]
}
