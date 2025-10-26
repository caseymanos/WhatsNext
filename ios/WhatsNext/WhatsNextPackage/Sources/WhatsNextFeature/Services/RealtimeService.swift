import Foundation
import Supabase
import Combine
import OSLog

/// Service for managing real-time subscriptions
final class RealtimeService {
    private let supabase = SupabaseClientService.shared
    private let logger = Logger(subsystem: "com.gauntletai.whatsnext", category: "RealtimeService")
    
    // Decoder configured for Supabase Realtime events
    // Handles both SQL timestamp and ISO8601 formats
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // NOTE: Do NOT use .convertFromSnakeCase here - our models have explicit CodingKeys
        // Using both causes conflicts where the decoder can't find keys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            
            // Format 1: SQL timestamp with space (what Postgres realtime actually sends)
            // Example: "2025-10-23 16:55:34.462"
            let sqlFormatter = DateFormatter()
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
            sqlFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = sqlFormatter.date(from: string) {
                return date
            }
            
            // Format 2: SQL timestamp without milliseconds
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = sqlFormatter.date(from: string) {
                return date
            }
            
            // Format 3: ISO8601 with T separator (fallback)
            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            isoFormatter.locale = Locale(identifier: "en_US_POSIX")
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = isoFormatter.date(from: string) {
                return date
            }
            
            // Format 4: ISO8601 without milliseconds
            isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = isoFormatter.date(from: string) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date from: \(string)")
        }
        return decoder
    }()
    private var messageChannels: [UUID: RealtimeChannelV2] = [:]
    private var typingChannels: [UUID: RealtimeChannelV2] = [:]
    private var conversationChannel: RealtimeChannelV2?
    private var globalMessagesChannel: RealtimeChannelV2?
    private var readReceiptsChannel: RealtimeChannelV2?
    private var subscriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var typingSubscriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var conversationTask: Task<Void, Never>?
    private var globalMessagesTask: Task<Void, Never>?
    private var readReceiptsTask: Task<Void, Never>?
    
    // Track which conversation is currently open (for notification filtering)
    var currentOpenConversationId: UUID?

    /// Subscribe to messages in a conversation
    func subscribeToMessages(
        conversationId: UUID,
        onMessage: @escaping (Message) -> Void
    ) async throws {
        // Clean up existing subscription if any
        if let existingChannel = messageChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        subscriptionTasks[conversationId]?.cancel()

        let channel = await supabase.realtimeV2.channel("conversation:\(conversationId):messages")
        
        logger.info("Subscribing to messages for conversation: \(conversationId.uuidString)")

        // IMPORTANT: Set up listener BEFORE subscribing to channel
        let task = Task {
            // Use SDK's default decoder - it's pre-configured for Supabase
            do {
                for try await insertion in channel.postgresChange(
                    InsertAction.self, 
                    table: "messages",
                    filter: .eq("conversation_id", value: conversationId)
                ) {
                    do {
                        let message = try insertion.decodeRecord(as: Message.self, decoder: decoder)
                        logger.info("Received message insert: \(message.id.uuidString) for conversation: \(message.conversationId.uuidString)")
                        onMessage(message)
                    } catch {
                        logger.error("Failed to decode message: \(error.localizedDescription)")
                        logger.debug("Raw record: \(insertion.record)")
                    }
                }
            } catch {
                logger.error("Error in message subscription stream: \(error.localizedDescription)")
            }
        }
        subscriptionTasks[conversationId] = task

        // Subscribe to the channel AFTER listener is set up
        await channel.subscribe()
        messageChannels[conversationId] = channel
        
        // Monitor subscription status
        Task { [weak self] in
            for await status in await channel.statusChange {
                self?.logger.info("Message channel status: \(String(describing: status))")
            }
        }
        
        logger.info("Successfully initiated messages subscription")
    }

    /// Unsubscribe from messages in a conversation
    func unsubscribeFromMessages(conversationId: UUID) async {
        logger.info("Unsubscribing from messages for conversation: \(conversationId.uuidString)")
        subscriptionTasks[conversationId]?.cancel()
        subscriptionTasks.removeValue(forKey: conversationId)

        if let channel = messageChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(channel)
            messageChannels.removeValue(forKey: conversationId)
        }
    }

    /// Subscribe to typing indicators in a conversation
    func subscribeToTypingIndicators(
        conversationId: UUID,
        excludeUserId: UUID,
        onTyping: @escaping (TypingIndicator) -> Void
    ) async throws {
        logger.info("Subscribing to typing indicators for conversation: \(conversationId.uuidString)")
        // Clean up existing subscription if any
        if let existingChannel = typingChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        typingSubscriptionTasks[conversationId]?.cancel()

        let channel = await supabase.realtimeV2.channel("conversation:\(conversationId):typing")

        // IMPORTANT: Set up listener BEFORE subscribing to channel
        let task = Task {
            // Use SDK's default decoder
            do {
                for try await change in channel.postgresChange(
                    AnyAction.self, 
                    table: "typing_indicators",
                    filter: .eq("conversation_id", value: conversationId)
                ) {
                    switch change {
                    case .insert(let insertion):
                        if let indicator = try? insertion.decodeRecord(as: TypingIndicator.self, decoder: decoder),
                           indicator.userId != excludeUserId {
                            logger.info("Received typing indicator (insert): user \(indicator.userId.uuidString)")
                            onTyping(indicator)
                        }
                    case .update(let update):
                        if let indicator = try? update.decodeRecord(as: TypingIndicator.self, decoder: decoder),
                           indicator.userId != excludeUserId {
                            logger.info("Received typing indicator (update): user \(indicator.userId.uuidString)")
                            onTyping(indicator)
                        }
                    case .delete:
                        break
                    }
                }
            } catch {
                logger.error("Error in typing subscription: \(error.localizedDescription)")
            }
        }
        typingSubscriptionTasks[conversationId] = task

        // Subscribe to the channel AFTER listener is set up
        await channel.subscribe()
        typingChannels[conversationId] = channel
        
        // Monitor subscription status
        Task { [weak self] in
            for await status in await channel.statusChange {
                self?.logger.info("Typing channel status: \(String(describing: status))")
            }
        }
    }

    /// Unsubscribe from typing indicators in a conversation
    func unsubscribeFromTypingIndicators(conversationId: UUID) async {
        logger.info("Unsubscribing from typing indicators for conversation: \(conversationId.uuidString)")
        typingSubscriptionTasks[conversationId]?.cancel()
        typingSubscriptionTasks.removeValue(forKey: conversationId)

        if let channel = typingChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(channel)
            typingChannels.removeValue(forKey: conversationId)
        }
    }

    /// Subscribe to conversation list updates
    func subscribeToConversationUpdates(
        userId: UUID,
        onUpdate: @escaping (Conversation) -> Void
    ) async throws {
        logger.info("Subscribing to conversation updates for user: \(userId.uuidString)")
        // Clean up existing subscription if any
        conversationTask?.cancel()
        if let existingChannel = conversationChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }

        let channel = await supabase.realtimeV2.channel("user:\(userId):conversations")

        // IMPORTANT: Set up listener BEFORE subscribing to channel
        let task = Task {
            // Use SDK's default decoder
            do {
                for try await update in channel.postgresChange(UpdateAction.self, table: "conversations") {
                    do {
                        logger.info("🔶 Attempting to decode conversation from realtime")
                        logger.info("🔶 Raw record keys: \(update.record.keys.sorted())")
                        logger.info("🔶 Raw record values: \(update.record)")

                        let conversation = try update.decodeRecord(as: Conversation.self, decoder: decoder)
                        logger.info("🔶 ✅ Successfully decoded conversation: \(conversation.id.uuidString)")
                        // Client-side filtering will be done in GlobalRealtimeManager
                        onUpdate(conversation)
                    } catch let DecodingError.keyNotFound(key, context) {
                        logger.error("❌ CONV: Missing key '\(key.stringValue)'")
                        logger.error("❌ CONV Context: \(context.debugDescription)")
                    } catch let DecodingError.typeMismatch(type, context) {
                        logger.error("❌ CONV: Type mismatch for '\(type)'")
                        logger.error("❌ CONV Context: \(context.debugDescription)")
                    } catch let DecodingError.valueNotFound(type, context) {
                        logger.error("❌ CONV: Value not found for '\(type)'")
                        logger.error("❌ CONV Context: \(context.debugDescription)")
                    } catch let DecodingError.dataCorrupted(context) {
                        logger.error("❌ CONV: Data corrupted")
                        logger.error("❌ CONV Context: \(context.debugDescription)")
                    } catch {
                        logger.error("❌ Failed to decode conversation: \(error.localizedDescription)")
                        logger.error("❌ Error type: \(type(of: error))")
                        logger.debug("Raw record: \(update.record)")
                    }
                }
            } catch {
                logger.error("Error in conversation subscription stream: \(error.localizedDescription)")
            }
        }
        conversationTask = task

        // Subscribe to the channel AFTER listener is set up
        await channel.subscribe()
        conversationChannel = channel
        
        // Monitor subscription status
        Task { [weak self] in
            for await status in await channel.statusChange {
                self?.logger.info("Conversation channel status: \(String(describing: status))")
            }
        }
        
        logger.info("Successfully initiated conversation updates subscription")
    }

    /// Subscribe to all messages for user's conversations (global subscription)
    /// This relies on RLS policies to filter messages to only user's conversations
    func subscribeToAllMessages(
        userId: UUID,
        onMessage: @escaping (Message) -> Void
    ) async throws {
        logger.info("Subscribing to all messages for user: \(userId.uuidString)")
        // Clean up existing subscription if any
        globalMessagesTask?.cancel()
        if let existingChannel = globalMessagesChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        
        let channel = await supabase.realtimeV2.channel("user:\(userId):messages")
        
        // IMPORTANT: Set up listener BEFORE subscribing to channel
        let task = Task {
            // Use SDK's default decoder
            do {
                for try await insertion in channel.postgresChange(InsertAction.self, table: "messages") {
                    do {
                        logger.info("🔷 Attempting to decode message from realtime")
                        logger.info("🔷 Raw record keys: \(insertion.record.keys.sorted())")
                        logger.info("🔷 Raw record values: \(insertion.record)")

                        let message = try insertion.decodeRecord(as: Message.self, decoder: decoder)
                        logger.info("🔷 ✅ Successfully decoded message: \(message.id.uuidString) for conversation: \(message.conversationId.uuidString)")
                        onMessage(message)
                    } catch let DecodingError.keyNotFound(key, context) {
                        logger.error("❌ Missing key '\(key.stringValue)' in message")
                        logger.error("❌ Context: \(context.debugDescription)")
                        logger.error("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    } catch let DecodingError.typeMismatch(type, context) {
                        logger.error("❌ Type mismatch for type '\(type)' in message")
                        logger.error("❌ Context: \(context.debugDescription)")
                        logger.error("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    } catch let DecodingError.valueNotFound(type, context) {
                        logger.error("❌ Value not found for type '\(type)' in message")
                        logger.error("❌ Context: \(context.debugDescription)")
                        logger.error("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    } catch let DecodingError.dataCorrupted(context) {
                        logger.error("❌ Data corrupted in message")
                        logger.error("❌ Context: \(context.debugDescription)")
                        logger.error("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    } catch {
                        logger.error("❌ Failed to decode global message: \(error.localizedDescription)")
                        logger.error("❌ Error type: \(type(of: error))")
                        logger.debug("Raw record keys: \(insertion.record.keys)")
                    }
                }
            } catch {
                logger.error("Error in global messages subscription stream: \(error.localizedDescription)")
            }
        }
        globalMessagesTask = task
        
        // Subscribe to the channel AFTER listener is set up
        await channel.subscribe()
        globalMessagesChannel = channel
        
        // Monitor subscription status
        Task { [weak self] in
            for await status in await channel.statusChange {
                self?.logger.info("Global messages channel status: \(String(describing: status))")
            }
        }
        
        logger.info("Successfully initiated global messages subscription")
    }
    
    /// Subscribe to read receipts for a conversation
    func subscribeToReadReceipts(
        conversationId: UUID,
        onReadReceipt: @escaping (ReadReceipt) -> Void
    ) async throws {
        logger.info("Subscribing to read receipts for conversation: \(conversationId.uuidString)")
        // Clean up existing subscription if any
        readReceiptsTask?.cancel()
        if let existingChannel = readReceiptsChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        
        let channel = await supabase.realtimeV2.channel("conversation:\(conversationId):receipts")
        
        // IMPORTANT: Set up listener BEFORE subscribing to channel
        let task = Task {
            // Use SDK's default decoder
            do {
                for try await change in channel.postgresChange(AnyAction.self, table: "read_receipts") {
                    switch change {
                    case .insert(let insertion):
                        if let receipt = try? insertion.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            logger.info("Received read receipt (insert): message \(receipt.messageId.uuidString)")
                            // Will be filtered by conversation membership in handler
                            onReadReceipt(receipt)
                        }
                    case .update(let update):
                        if let receipt = try? update.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            logger.info("Received read receipt (update): message \(receipt.messageId.uuidString)")
                            onReadReceipt(receipt)
                        }
                    case .delete:
                        break
                    }
                }
            } catch {
                logger.error("Error in read receipts subscription: \(error.localizedDescription)")
            }
        }
        readReceiptsTask = task
        
        // Subscribe to the channel AFTER listener is set up
        await channel.subscribe()
        readReceiptsChannel = channel
        
        // Monitor subscription status
        Task { [weak self] in
            for await status in await channel.statusChange {
                self?.logger.info("Read receipts channel status: \(String(describing: status))")
            }
        }
        
        logger.info("Successfully initiated read receipts subscription")
    }
    
    /// Unsubscribe from read receipts
    func unsubscribeFromReadReceipts(conversationId: UUID) async {
        logger.info("Unsubscribing from read receipts for conversation: \(conversationId.uuidString)")
        readReceiptsTask?.cancel()
        readReceiptsTask = nil
        
        if let channel = readReceiptsChannel {
            await supabase.realtimeV2.removeChannel(channel)
            readReceiptsChannel = nil
        }
    }

    /// Clean up all subscriptions
    func cleanup() async {
        logger.info("Cleaning up all subscriptions")
        // Cancel all tasks
        for (_, task) in subscriptionTasks {
            task.cancel()
        }
        for (_, task) in typingSubscriptionTasks {
            task.cancel()
        }
        conversationTask?.cancel()
        globalMessagesTask?.cancel()
        readReceiptsTask?.cancel()

        // Remove all channels
        for (_, channel) in messageChannels {
            await supabase.realtimeV2.removeChannel(channel)
        }
        for (_, channel) in typingChannels {
            await supabase.realtimeV2.removeChannel(channel)
        }
        if let channel = conversationChannel {
            await supabase.realtimeV2.removeChannel(channel)
        }
        if let channel = globalMessagesChannel {
            await supabase.realtimeV2.removeChannel(channel)
        }
        if let channel = readReceiptsChannel {
            await supabase.realtimeV2.removeChannel(channel)
        }

        // Clear dictionaries
        messageChannels.removeAll()
        typingChannels.removeAll()
        subscriptionTasks.removeAll()
        typingSubscriptionTasks.removeAll()
        conversationChannel = nil
        conversationTask = nil
        globalMessagesChannel = nil
        globalMessagesTask = nil
        readReceiptsChannel = nil
        readReceiptsTask = nil
        currentOpenConversationId = nil
    }
}
