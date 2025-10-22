import Foundation
import Supabase
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Service for managing real-time subscriptions
final class RealtimeService {
    private let supabase = SupabaseClientService.shared
    private var messageChannels: [UUID: RealtimeChannelV2] = [:]
    private var typingChannels: [UUID: RealtimeChannelV2] = [:]
    private var conversationChannel: RealtimeChannelV2?
    private var subscriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var typingSubscriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var conversationTask: Task<Void, Never>?
    
    // Track which conversation is currently open to avoid notifying for it
    var currentOpenConversationId: UUID?

    /// Subscribe to messages in a conversation
    func subscribeToMessages(
        conversationId: UUID,
        currentUserId: UUID,
        conversationName: String,
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
                    // Filter by conversation ID and exclude own messages
                    if message.conversationId == conversationId && message.senderId != currentUserId {
                        onMessage(message)
                        
                        // Handle notification/banner for incoming message
                        await self.handleIncomingMessageNotification(
                            message: message,
                            conversationId: conversationId,
                            conversationName: conversationName
                        )
                    } else if message.conversationId == conversationId {
                        // Still call onMessage for own messages (for optimistic UI updates)
                        onMessage(message)
                    }
                }
            } catch {
                print("Error in message subscription: \(error)")
            }
        }
        subscriptionTasks[conversationId] = task
    }
    
    /// Handle incoming message notification/banner
    private func handleIncomingMessageNotification(
        message: Message,
        conversationId: UUID,
        conversationName: String
    ) async {
        // Get sender name
        let senderName = message.sender?.displayName 
            ?? message.sender?.username 
            ?? "Someone"
        
        let messageContent = message.content ?? "[Media]"
        
        #if canImport(UIKit)
        // Check app state
        let appState = await UIApplication.shared.applicationState
        
        if appState == .active {
            // App is in foreground - show in-app banner only if not viewing this conversation
            if currentOpenConversationId != conversationId {
                await MainActor.run {
                    InAppBannerManager.shared.showBanner(
                        conversationId: conversationId,
                        conversationName: conversationName,
                        senderName: senderName,
                        messageContent: messageContent
                    )
                }
            }
        } else {
            // App is in background or inactive - send local notification
            await PushNotificationService.shared.scheduleLocalNotification(
                conversationId: conversationId,
                conversationName: conversationName,
                senderName: senderName,
                messageContent: messageContent
            )
        }
        #else
        // macOS or other platforms - just send local notification
        await PushNotificationService.shared.scheduleLocalNotification(
            conversationId: conversationId,
            conversationName: conversationName,
            senderName: senderName,
            messageContent: messageContent
        )
        #endif
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
    
    /// Subscribe to all messages across all conversations (for conversation list updates)
    func subscribeToAllMessages(
        userId: UUID,
        onMessage: @escaping (Message) -> Void
    ) async throws {
        let channel = await supabase.realtimeV2.channel("all_messages:\(userId)")
        
        // Subscribe to the channel
        try await channel.subscribe()
        
        // Store in a separate channel if needed, or reuse conversationChannel
        // For now, we'll create a task to listen
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
                print("Error in all messages subscription: \(error)")
            }
        }
        
        // Store the task so it can be cancelled later
        subscriptionTasks[UUID()] = task
        
        // Store the channel for cleanup
        messageChannels[UUID()] = channel
    }
    
    /// Subscribe to read receipts for messages in a conversation
    func subscribeToReadReceipts(
        conversationId: UUID,
        onReceipt: @escaping (ReadReceipt) -> Void
    ) async throws {
        let channel = await supabase.realtimeV2.channel("read_receipts:\(conversationId)")
        
        // Subscribe to the channel
        try await channel.subscribe()
        
        // Listen for read receipt inserts/updates
        let task = Task {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                
                // Listen for both inserts and updates (upserts)
                for try await change in channel.postgresChange(AnyAction.self, table: "read_receipts") {
                    switch change {
                    case .insert(let insertion):
                        if let receipt = try? insertion.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            onReceipt(receipt)
                        }
                    case .update(let update):
                        if let receipt = try? update.decodeRecord(as: ReadReceipt.self, decoder: decoder) {
                            onReceipt(receipt)
                        }
                    case .delete:
                        break
                    }
                }
            } catch {
                print("Error in read receipts subscription: \(error)")
            }
        }
        
        // Store the task for this conversation
        subscriptionTasks[conversationId] = task
        
        // Store the channel for cleanup
        messageChannels[conversationId] = channel
    }
    
    /// Unsubscribe from read receipts for a conversation
    func unsubscribeFromReadReceipts(conversationId: UUID) async {
        subscriptionTasks[conversationId]?.cancel()
        subscriptionTasks.removeValue(forKey: conversationId)
        
        if let channel = messageChannels[conversationId] {
            await supabase.realtimeV2.removeChannel(channel)
            messageChannels.removeValue(forKey: conversationId)
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

        // Clear dictionaries
        messageChannels.removeAll()
        typingChannels.removeAll()
        subscriptionTasks.removeAll()
        typingSubscriptionTasks.removeAll()
        conversationChannel = nil
        conversationTask = nil
    }
}
