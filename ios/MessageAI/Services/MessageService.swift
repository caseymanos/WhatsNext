import Foundation
import Supabase

final class MessageService {
    private let supabase = SupabaseClientService.shared
    
    /// Fetch messages for a conversation
    func fetchMessages(conversationId: UUID, limit: Int = 50, before: Date? = nil) async throws -> [Message] {
        var query = supabase.database
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId)
            .is("deleted_at", value: nil)

        if let before = before {
            query = query.lt("created_at", value: before)
        }

        let messages: [Message] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return messages.reversed() // Return in chronological order
    }
    
    /// Send a text message
    func sendMessage(
        conversationId: UUID,
        senderId: UUID,
        content: String,
        localId: String? = nil
    ) async throws -> Message {
        let message = Message(
            id: UUID(),
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            messageType: .text,
            mediaUrl: nil,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil,
            localId: localId ?? UUID().uuidString
        )
        
        let insertedMessage: Message = try await supabase.database
            .from("messages")
            .insert(message)
            .select()
            .single()
            .execute()
            .value
        
        return insertedMessage
    }
    
    /// Send a media message
    func sendMediaMessage(
        conversationId: UUID,
        senderId: UUID,
        messageType: MessageType,
        mediaUrl: String,
        content: String? = nil,
        localId: String? = nil
    ) async throws -> Message {
        let message = Message(
            id: UUID(),
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            messageType: messageType,
            mediaUrl: mediaUrl,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil,
            localId: localId ?? UUID().uuidString
        )
        
        let insertedMessage: Message = try await supabase.database
            .from("messages")
            .insert(message)
            .select()
            .single()
            .execute()
            .value
        
        return insertedMessage
    }
    
    /// Delete a message (soft delete)
    func deleteMessage(messageId: UUID) async throws {
        try await supabase.database
            .from("messages")
            .update(["deleted_at": Date()])
            .eq("id", value: messageId)
            .execute()
    }
    
    /// Mark message as read
    func markAsRead(messageId: UUID, userId: UUID) async throws {
        let readReceipt = ReadReceipt(
            messageId: messageId,
            userId: userId,
            readAt: Date()
        )
        
        try await supabase.database
            .from("read_receipts")
            .upsert(readReceipt)
            .execute()
    }
    
    /// Fetch read receipts for a message
    func fetchReadReceipts(messageId: UUID) async throws -> [ReadReceipt] {
        let receipts: [ReadReceipt] = try await supabase.database
            .from("read_receipts")
            .select()
            .eq("message_id", value: messageId)
            .execute()
            .value
        
        return receipts
    }
    
    /// Update or create typing indicator
    func updateTypingIndicator(conversationId: UUID, userId: UUID) async throws {
        let indicator = TypingIndicator(
            conversationId: conversationId,
            userId: userId,
            lastTyped: Date()
        )
        
        try await supabase.database
            .from("typing_indicators")
            .upsert(indicator)
            .execute()
    }
    
    /// Fetch active typing indicators for a conversation
    func fetchTypingIndicators(conversationId: UUID, excludeUserId: UUID) async throws -> [TypingIndicator] {
        let fiveSecondsAgo = Date().addingTimeInterval(-5)
        
        let indicators: [TypingIndicator] = try await supabase.database
            .from("typing_indicators")
            .select()
            .eq("conversation_id", value: conversationId)
            .neq("user_id", value: excludeUserId)
            .gt("last_typed", value: fiveSecondsAgo)
            .execute()
            .value
        
        return indicators
    }
}

