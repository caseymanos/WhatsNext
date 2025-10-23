import Foundation
import Supabase
import Combine

/// Service for managing real-time subscriptions
final class RealtimeService {
    private let supabase = SupabaseClientService.shared
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

        let channel = await supabase.realtimeV2.channel("messages:\(conversationId)")

        // Subscribe to the channel
        try await channel.subscribe()
        messageChannels[conversationId] = channel

        // Listen for inserts in a background task
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601

                for try await insertion in channel.postgresChange(InsertAction.self, table: "messages") {
                    let message = try insertion.decodeRecord(as: Message.self, decoder: decoder)
                    // Filter by conversation ID
                    if message.conversationId == conversationId {
                        onMessage(message)
                    }
                }
            } catch {
                print("Error in message subscription: \(error)")
            }
        }
        subscriptionTasks[conversationId] = task
    }

    /// Unsubscribe from messages in a conversation
    func unsubscribeFromMessages(conversationId: UUID) async {
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
        // Clean up existing subscription if any
        if let existingChannel = typingChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        typingSubscriptionTasks[conversationId]?.cancel()

        let channel = await supabase.realtimeV2.channel("typing:\(conversationId)")

        // Subscribe to the channel
        try await channel.subscribe()
        typingChannels[conversationId] = channel

        // Listen for both inserts and updates in a background task
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601

                // Listen for all changes (insert, update, delete)
                for try await change in channel.postgresChange(AnyAction.self, table: "typing_indicators") {
                    switch change {
                    case .insert(let insertion):
                        if let indicator = try? insertion.decodeRecord(as: TypingIndicator.self, decoder: decoder),
                           indicator.conversationId == conversationId,
                           indicator.userId != excludeUserId {
                            onTyping(indicator)
                        }
                    case .update(let update):
                        if let indicator = try? update.decodeRecord(as: TypingIndicator.self, decoder: decoder),
                           indicator.conversationId == conversationId,
                           indicator.userId != excludeUserId {
                            onTyping(indicator)
                        }
                    case .delete:
                        break
                    }
                }
            } catch {
                print("Error in typing subscription: \(error)")
            }
        }
        typingSubscriptionTasks[conversationId] = task
    }

    /// Unsubscribe from typing indicators in a conversation
    func unsubscribeFromTypingIndicators(conversationId: UUID) async {
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
        // Clean up existing subscription if any
        conversationTask?.cancel()
        if let existingChannel = conversationChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }

        let channel = await supabase.realtimeV2.channel("conversation_updates:\(userId)")

        // Subscribe to the channel
        try await channel.subscribe()
        conversationChannel = channel

        // Listen for updates in a background task
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601

                for try await update in channel.postgresChange(UpdateAction.self, table: "conversations") {
                    let conversation = try update.decodeRecord(as: Conversation.self, decoder: decoder)
                    onUpdate(conversation)
                }
            } catch {
                print("Error in conversation subscription: \(error)")
            }
        }
        conversationTask = task
    }

    /// Subscribe to all messages for user's conversations (global subscription)
    func subscribeToAllMessages(
        userId: UUID,
        onMessage: @escaping (Message) -> Void
    ) async throws {
        // Clean up existing subscription if any
        globalMessagesTask?.cancel()
        if let existingChannel = globalMessagesChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        
        let channel = await supabase.realtimeV2.channel("global_messages:\(userId)")
        
        // Subscribe to the channel
        try await channel.subscribe()
        globalMessagesChannel = channel
        
        // Listen for all message inserts
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                
                for try await insertion in channel.postgresChange(InsertAction.self, table: "messages") {
                    let message = try insertion.decodeRecord(as: Message.self, decoder: decoder)
                    onMessage(message)
                }
            } catch {
                print("Error in global messages subscription: \(error)")
            }
        }
        globalMessagesTask = task
    }
    
    /// Subscribe to read receipts for a conversation
    func subscribeToReadReceipts(
        conversationId: UUID,
        onReadReceipt: @escaping (ReadReceipt) -> Void
    ) async throws {
        // Clean up existing subscription if any
        readReceiptsTask?.cancel()
        if let existingChannel = readReceiptsChannel {
            await supabase.realtimeV2.removeChannel(existingChannel)
        }
        
        let channel = await supabase.realtimeV2.channel("read_receipts:\(conversationId)")
        
        // Subscribe to the channel
        try await channel.subscribe()
        readReceiptsChannel = channel
        
        // Listen for read receipt inserts and updates
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                
                for try await change in channel.postgresChange(AnyAction.self, table: "read_receipts") {
                    switch change {
                    case .insert(let insertion):
                        if let receipt = try? insertion.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            onReadReceipt(receipt)
                        }
                    case .update(let update):
                        if let receipt = try? update.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            onReadReceipt(receipt)
                        }
                    case .delete:
                        break
                    }
                }
            } catch {
                print("Error in read receipts subscription: \(error)")
            }
        }
        readReceiptsTask = task
    }
    
    /// Unsubscribe from read receipts
    func unsubscribeFromReadReceipts(conversationId: UUID) async {
        readReceiptsTask?.cancel()
        readReceiptsTask = nil
        
        if let channel = readReceiptsChannel {
            await supabase.realtimeV2.removeChannel(channel)
            readReceiptsChannel = nil
        }
    }

    /// Clean up all subscriptions
    func cleanup() async {
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
