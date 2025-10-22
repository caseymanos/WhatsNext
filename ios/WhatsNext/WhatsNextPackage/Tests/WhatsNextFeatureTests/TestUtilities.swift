import Foundation
@testable import WhatsNextFeature

// MARK: - Test Utilities and Mocks
//
// This file provides mock objects, test factories, and helper utilities
// for writing clean, maintainable tests.

// MARK: - Test Data Factories

/// Factory for creating test users with realistic data
enum TestUserFactory {
    static func createUser(
        id: UUID = UUID(),
        email: String = "test@example.com",
        username: String = "testuser",
        displayName: String? = "Test User",
        status: UserStatus = .online
    ) -> User {
        User(
            id: id,
            email: email,
            username: username,
            displayName: displayName,
            avatarUrl: nil,
            createdAt: Date(),
            lastSeen: Date(),
            status: status,
            pushToken: nil
        )
    }

    static func createUsers(count: Int) -> [User] {
        (0..<count).map { index in
            createUser(
                email: "user\(index)@example.com",
                username: "user\(index)",
                displayName: "User \(index)"
            )
        }
    }

    static func createUserWithUsername(_ username: String) -> User {
        createUser(
            email: "\(username)@example.com",
            username: username,
            displayName: username.capitalized
        )
    }
}

/// Factory for creating test conversations
enum TestConversationFactory {
    static func createDirectConversation(
        id: UUID = UUID(),
        participants: [User]? = nil,
        lastMessage: Message? = nil
    ) -> Conversation {
        Conversation(
            id: id,
            name: nil,
            avatarUrl: nil,
            isGroup: false,
            createdAt: Date(),
            updatedAt: Date(),
            participants: participants,
            lastMessage: lastMessage,
            unreadCount: nil
        )
    }

    static func createGroupConversation(
        id: UUID = UUID(),
        name: String = "Test Group",
        participants: [User]? = nil,
        participantCount: Int = 3
    ) -> Conversation {
        let actualParticipants = participants ?? TestUserFactory.createUsers(count: participantCount)

        return Conversation(
            id: id,
            name: name,
            avatarUrl: nil,
            isGroup: true,
            createdAt: Date(),
            updatedAt: Date(),
            participants: actualParticipants,
            lastMessage: nil,
            unreadCount: nil
        )
    }

    static func createConversationWithMessages(
        messageCount: Int,
        isGroup: Bool = false
    ) -> (conversation: Conversation, messages: [Message]) {
        let conversation = isGroup
            ? createGroupConversation()
            : createDirectConversation()

        let messages = TestMessageFactory.createMessages(
            count: messageCount,
            conversationId: conversation.id,
            senderId: UUID()
        )

        return (conversation, messages)
    }
}

/// Factory for creating test messages
enum TestMessageFactory {
    static func createMessage(
        id: UUID = UUID(),
        conversationId: UUID,
        senderId: UUID,
        content: String = "Test message",
        messageType: MessageType = .text,
        createdAt: Date = Date(),
        localId: String? = nil
    ) -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            messageType: messageType,
            mediaUrl: nil,
            createdAt: createdAt,
            updatedAt: nil,
            deletedAt: nil,
            localId: localId ?? UUID().uuidString,
            sender: nil,
            readReceipts: nil
        )
    }

    static func createMessages(
        count: Int,
        conversationId: UUID,
        senderId: UUID
    ) -> [Message] {
        (0..<count).map { index in
            createMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: "Message \(index + 1)",
                createdAt: Date().addingTimeInterval(TimeInterval(index))
            )
        }
    }

    static func createOptimisticMessage(
        conversationId: UUID,
        senderId: UUID,
        content: String
    ) -> Message {
        createMessage(
            id: UUID(), // Will be replaced by server
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            localId: UUID().uuidString
        )
    }

    static func createMediaMessage(
        conversationId: UUID,
        senderId: UUID,
        mediaUrl: String = "https://example.com/image.jpg"
    ) -> Message {
        Message(
            id: UUID(),
            conversationId: conversationId,
            senderId: senderId,
            content: nil,
            messageType: .image,
            mediaUrl: mediaUrl,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil,
            localId: UUID().uuidString,
            sender: nil,
            readReceipts: nil
        )
    }
}

// MARK: - Mock Services

/// Mock AuthService for testing authentication flows
final class MockAuthService {
    var shouldSucceed = true
    var mockUser: User?
    var callCount = 0

    func signUp(email: String, password: String, username: String?, displayName: String?) async throws -> User {
        callCount += 1

        if shouldSucceed {
            let user = TestUserFactory.createUser(
                email: email,
                username: username ?? "testuser",
                displayName: displayName
            )
            mockUser = user
            return user
        } else {
            throw AuthError.invalidCredentials
        }
    }

    func signIn(email: String, password: String) async throws -> User {
        callCount += 1

        if shouldSucceed, let user = mockUser {
            return user
        } else {
            throw AuthError.invalidCredentials
        }
    }

    func getCurrentUser() async throws -> User? {
        return mockUser
    }

    func signOut(userId: UUID?) async throws {
        callCount += 1
        mockUser = nil
    }
}

/// Mock UserService for testing profile operations
final class MockUserService {
    var availableUsernames: Set<String> = []
    var callCount = 0

    func checkUsernameAvailability(username: String, excludeUserId: UUID? = nil) async throws -> Bool {
        callCount += 1
        return !availableUsernames.contains(username)
    }

    func validateUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 && trimmed.count <= 20 else { return false }

        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: trimmed)
    }

    func updateUsername(userId: UUID, username: String) async throws {
        callCount += 1
        guard validateUsername(username) else {
            throw UserServiceError.usernameInvalid
        }

        let isAvailable = try await checkUsernameAvailability(username: username, excludeUserId: userId)
        guard isAvailable else {
            throw UserServiceError.usernameTaken
        }

        // Success - add to taken usernames
        availableUsernames.insert(username)
    }
}

/// Mock MessageService for testing message operations
final class MockMessageService {
    var messages: [UUID: [Message]] = [:]
    var shouldSucceed = true
    var sendDelay: TimeInterval = 0.1
    var callCount = 0

    func fetchMessages(conversationId: UUID, limit: Int = 50) async throws -> [Message] {
        callCount += 1
        return messages[conversationId] ?? []
    }

    func sendMessage(
        conversationId: UUID,
        senderId: UUID,
        content: String,
        localId: String
    ) async throws -> Message {
        callCount += 1

        // Simulate network delay
        try await Task.sleep(for: .seconds(sendDelay))

        if shouldSucceed {
            let message = TestMessageFactory.createMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: content,
                localId: localId
            )

            // Store message
            if messages[conversationId] == nil {
                messages[conversationId] = []
            }
            messages[conversationId]?.append(message)

            return message
        } else {
            throw MessageServiceError.sendFailed
        }
    }

    func markAsRead(messageId: UUID, userId: UUID) async throws {
        callCount += 1
        // Mock implementation
    }
}

/// Mock ConversationService for testing conversation operations
final class MockConversationService {
    var conversations: [Conversation] = []
    var shouldSucceed = true
    var callCount = 0

    func fetchConversations(userId: UUID) async throws -> [Conversation] {
        callCount += 1
        return conversations
    }

    func createDirectConversation(currentUserId: UUID, otherUserId: UUID) async throws -> Conversation {
        callCount += 1

        if shouldSucceed {
            let conversation = TestConversationFactory.createDirectConversation()
            conversations.append(conversation)
            return conversation
        } else {
            throw ConversationServiceError.creationFailed
        }
    }

    func createGroupConversation(
        creatorId: UUID,
        participantIds: [UUID],
        name: String?
    ) async throws -> Conversation {
        callCount += 1

        if shouldSucceed {
            let conversation = TestConversationFactory.createGroupConversation(name: name ?? "Test Group")
            conversations.append(conversation)
            return conversation
        } else {
            throw ConversationServiceError.creationFailed
        }
    }
}

/// Mock RealtimeService for testing real-time features
final class MockRealtimeService {
    var subscriptions: [UUID: (Message) -> Void] = [:]
    var typingCallbacks: [UUID: (TypingIndicator) -> Void] = [:]

    func subscribeToMessages(conversationId: UUID, callback: @escaping (Message) -> Void) async throws {
        subscriptions[conversationId] = callback
    }

    func unsubscribeFromMessages(conversationId: UUID) async {
        subscriptions.removeValue(forKey: conversationId)
    }

    func subscribeToTypingIndicators(conversationId: UUID, callback: @escaping (TypingIndicator) -> Void) async throws {
        typingCallbacks[conversationId] = callback
    }

    // Test helper: Simulate receiving a message
    func simulateMessageReceived(_ message: Message) {
        if let callback = subscriptions[message.conversationId] {
            callback(message)
        }
    }

    // Test helper: Simulate typing indicator
    func simulateTypingIndicator(_ indicator: TypingIndicator) {
        if let callback = typingCallbacks[indicator.conversationId] {
            callback(indicator)
        }
    }
}

// MARK: - Test Helpers

/// Helper for async test operations
enum AsyncTestHelper {
    /// Wait for a condition to be true, with timeout
    static func waitFor(
        timeout: TimeInterval = 5.0,
        condition: @escaping () async -> Bool
    ) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        return false
    }

    /// Wait for a specific duration
    static func wait(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Helper for generating test data
enum TestDataHelper {
    static func randomEmail() -> String {
        "test_\(UUID().uuidString.prefix(8))@example.com"
    }

    static func randomUsername() -> String {
        "user_\(UUID().uuidString.prefix(8))"
    }

    static func randomDisplayName() -> String {
        let firstNames = ["Alice", "Bob", "Charlie", "Diana", "Eve"]
        let lastNames = ["Smith", "Johnson", "Williams", "Brown", "Jones"]

        let first = firstNames.randomElement() ?? "Test"
        let last = lastNames.randomElement() ?? "User"

        return "\(first) \(last)"
    }

    static func createTestUsers(_ count: Int) -> [User] {
        (0..<count).map { _ in
            TestUserFactory.createUser(
                email: randomEmail(),
                username: randomUsername(),
                displayName: randomDisplayName()
            )
        }
    }
}

/// Helper for validation testing
enum ValidationTestHelper {
    static let validUsernames = [
        "alice",
        "bob_123",
        "user_test",
        "JohnDoe",
        "test123"
    ]

    static let invalidUsernames = [
        "ab",                           // Too short
        "a",                            // Too short
        "this_is_way_too_long_username", // Too long
        "user@name",                    // Invalid character
        "user-name",                    // Invalid character
        "user.name",                    // Invalid character
        "user name",                    // Space
        "",                             // Empty
        "  ",                           // Whitespace
    ]

    static let validEmails = [
        "test@example.com",
        "user.name@example.com",
        "user+tag@example.co.uk"
    ]

    static let invalidEmails = [
        "notanemail",
        "@example.com",
        "user@",
        "user name@example.com"
    ]
}

// MARK: - Mock Errors

enum MockServiceError: Error {
    case networkFailure
    case timeout
    case unauthorized
    case notFound
}

enum MessageServiceError: Error {
    case sendFailed
    case fetchFailed
}

enum ConversationServiceError: Error {
    case creationFailed
    case notFound
}

// MARK: - Test Configuration

/// Configuration for test environment
struct TestConfiguration {
    static let defaultTimeout: TimeInterval = 5.0
    static let shortTimeout: TimeInterval = 1.0
    static let longTimeout: TimeInterval = 10.0

    static let testSupabaseURL = "https://test.supabase.co"
    static let testAnonKey = "test_anon_key"

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

// MARK: - Assertion Helpers

/// Custom assertions for common test scenarios
enum TestAssertions {
    static func assertMessagesEqual(_ messages1: [Message], _ messages2: [Message]) -> Bool {
        guard messages1.count == messages2.count else { return false }

        return zip(messages1, messages2).allSatisfy { msg1, msg2 in
            msg1.id == msg2.id &&
            msg1.content == msg2.content &&
            msg1.senderId == msg2.senderId
        }
    }

    static func assertConversationsEqual(_ conv1: Conversation, _ conv2: Conversation) -> Bool {
        conv1.id == conv2.id &&
        conv1.name == conv2.name &&
        conv1.isGroup == conv2.isGroup
    }
}
