import Foundation

/// Item in the calendar sync retry queue
/// Corresponds to the calendar_sync_queue table
public struct SyncQueueItem: Codable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let itemType: SyncItemType
    public let itemId: UUID
    public let operation: SyncOperation
    public let targetSystem: SyncTarget
    public var retryCount: Int
    public let maxRetries: Int
    public var lastError: String?
    public var nextRetryAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case itemType = "item_type"
        case itemId = "item_id"
        case operation
        case targetSystem = "target_system"
        case retryCount = "retry_count"
        case maxRetries = "max_retries"
        case lastError = "last_error"
        case nextRetryAt = "next_retry_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        itemType: SyncItemType,
        itemId: UUID,
        operation: SyncOperation,
        targetSystem: SyncTarget,
        retryCount: Int = 0,
        maxRetries: Int = 3,
        lastError: String? = nil,
        nextRetryAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.itemType = itemType
        self.itemId = itemId
        self.operation = operation
        self.targetSystem = targetSystem
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.lastError = lastError
        self.nextRetryAt = nextRetryAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Check if this item has exceeded max retries
    public var hasExceededMaxRetries: Bool {
        retryCount >= maxRetries
    }

    /// Check if this item is ready to retry
    public var isReadyToRetry: Bool {
        guard let nextRetry = nextRetryAt else { return true }
        return Date() >= nextRetry
    }

    /// Calculate next retry time with exponential backoff
    public mutating func scheduleNextRetry() {
        retryCount += 1
        // Exponential backoff: 1min, 5min, 15min
        let backoffSeconds: TimeInterval
        switch retryCount {
        case 1:
            backoffSeconds = 60 // 1 minute
        case 2:
            backoffSeconds = 300 // 5 minutes
        default:
            backoffSeconds = 900 // 15 minutes
        }
        nextRetryAt = Date().addingTimeInterval(backoffSeconds)
    }
}

/// External calendar change tracking
/// Corresponds to the calendar_external_changes table
public struct ExternalCalendarChange: Codable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let externalSystem: SyncTarget
    public let externalId: String
    public let changeType: ExternalChangeType
    public let changeData: [String: AnyCodable]?
    public var processed: Bool
    public var processedAt: Date?
    public let detectedAt: Date
    public let createdAt: Date

    public enum ExternalChangeType: String, Codable {
        case created
        case updated
        case deleted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case externalSystem = "external_system"
        case externalId = "external_id"
        case changeType = "change_type"
        case changeData = "change_data"
        case processed
        case processedAt = "processed_at"
        case detectedAt = "detected_at"
        case createdAt = "created_at"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        externalSystem: SyncTarget,
        externalId: String,
        changeType: ExternalChangeType,
        changeData: [String: AnyCodable]? = nil,
        processed: Bool = false,
        processedAt: Date? = nil,
        detectedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.externalSystem = externalSystem
        self.externalId = externalId
        self.changeType = changeType
        self.changeData = changeData
        self.processed = processed
        self.processedAt = processedAt
        self.detectedAt = detectedAt
        self.createdAt = createdAt
    }
}

/// Helper for encoding/decoding arbitrary JSON
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
