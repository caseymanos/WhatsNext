import Foundation
import Supabase

public final class ConversationService {
    public init() {}
    private let supabase = SupabaseClientService.shared
    
    /// Fetch all conversations for the current user with participants
    public func fetchConversations(userId: UUID) async throws -> [Conversation] {
        // Fetch conversation IDs user is part of
        let participantRecords: [ConversationParticipant] = try await supabase.database
            .from("conversation_participants")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        let conversationIds = participantRecords.map { $0.conversationId }

        guard !conversationIds.isEmpty else {
            return []
        }

        // Fetch full conversation details
        var conversations: [Conversation] = try await supabase.database
            .from("conversations")
            .select()
            .in("id", values: conversationIds)
            .order("updated_at", ascending: false)
            .execute()
            .value

        // Fetch participants for all conversations
        for index in conversations.indices {
            let convParticipants: [ConversationParticipant] = try await supabase.database
                .from("conversation_participants")
                .select()
                .eq("conversation_id", value: conversations[index].id)
                .execute()
                .value

            let userIds = convParticipants.map { $0.userId }

            if !userIds.isEmpty {
                let users: [User] = try await supabase.database
                    .from("users")
                    .select()
                    .in("id", values: userIds)
                    .execute()
                    .value

                conversations[index].participants = users
            }
        }

        return conversations
    }
    
    /// Fetch a single conversation with participants
    func fetchConversation(conversationId: UUID) async throws -> Conversation {
        var conversation: Conversation = try await supabase.database
            .from("conversations")
            .select()
            .eq("id", value: conversationId)
            .single()
            .execute()
            .value
        
        // Fetch participants
        let participantRecords: [ConversationParticipant] = try await supabase.database
            .from("conversation_participants")
            .select()
            .eq("conversation_id", value: conversationId)
            .execute()
            .value
        
        let userIds = participantRecords.map { $0.userId }
        
        if !userIds.isEmpty {
            let users: [User] = try await supabase.database
                .from("users")
                .select()
                .in("id", values: userIds)
                .execute()
                .value
            
            conversation.participants = users
        }
        
        return conversation
    }
    
    /// Create a new 1:1 conversation
    func createDirectConversation(currentUserId: UUID, otherUserId: UUID) async throws -> Conversation {
        // Debug: Verify we have an active auth session
        do {
            let session = try await supabase.auth.session
            print("✅ ConversationService: Auth session valid - user_id=\(session.user.id)")
        } catch {
            print("❌ ConversationService: No valid auth session - \(error)")
            throw NSError(
                domain: "ConversationService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Must be signed in to create conversations. Please sign in and try again."]
            )
        }
        
        // Check if conversation already exists
        let existingParticipants: [ConversationParticipant] = try await supabase.database
            .from("conversation_participants")
            .select()
            .eq("user_id", value: currentUserId)
            .execute()
            .value
        
        for participant in existingParticipants {
            let conversationParticipants: [ConversationParticipant] = try await supabase.database
                .from("conversation_participants")
                .select()
                .eq("conversation_id", value: participant.conversationId)
                .execute()
                .value
            
            if conversationParticipants.count == 2 &&
               conversationParticipants.contains(where: { $0.userId == otherUserId }) {
                // Conversation already exists
                return try await fetchConversation(conversationId: participant.conversationId)
            }
        }
        
        // Create new conversation (no select to avoid RLS on immediate read)
        let newConversation = Conversation(
            id: UUID(),
            name: nil,
            avatarUrl: nil,
            isGroup: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        print("🔄 Attempting to insert conversation: \(newConversation.id)")
        do {
            try await supabase.database
                .from("conversations")
                .insert(newConversation)
                .execute()
            print("✅ Conversation inserted successfully")
        } catch {
            print("❌ Failed to insert conversation: \(error)")
            throw error
        }
        
        // Insert the current user as a participant first (satisfy RLS)
        let selfParticipant = ConversationParticipant(
            conversationId: newConversation.id,
            userId: currentUserId,
            joinedAt: Date(),
            lastReadAt: nil
        )
        
        try await supabase.database
            .from("conversation_participants")
            .insert(selfParticipant)
            .execute()
        
        // Insert the other participant
        let otherParticipant = ConversationParticipant(
            conversationId: newConversation.id,
            userId: otherUserId,
            joinedAt: Date(),
            lastReadAt: nil
        )
        
        try await supabase.database
            .from("conversation_participants")
            .insert(otherParticipant)
            .execute()
        
        // Now safe to read conversation by id
        return try await fetchConversation(conversationId: newConversation.id)
    }
    
    /// Create a group conversation
    func createGroupConversation(name: String, creatorId: UUID, participantIds: [UUID]) async throws -> Conversation {
        let newConversation = Conversation(
            id: UUID(),
            name: name,
            avatarUrl: nil,
            isGroup: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Insert conversation without selecting to avoid RLS on immediate read
        try await supabase.database
            .from("conversations")
            .insert(newConversation)
            .execute()
        
        // Insert creator first to establish membership
        let creatorParticipant = ConversationParticipant(
            conversationId: newConversation.id,
            userId: creatorId,
            joinedAt: Date(),
            lastReadAt: nil
        )
        
        try await supabase.database
            .from("conversation_participants")
            .insert(creatorParticipant)
            .execute()
        
        // Insert remaining participants (excluding creator to avoid duplicates)
        let otherParticipants = Set(participantIds).subtracting([creatorId]).map { userId in
            ConversationParticipant(
                conversationId: newConversation.id,
                userId: userId,
                joinedAt: Date(),
                lastReadAt: nil
            )
        }
        
        if !otherParticipants.isEmpty {
            try await supabase.database
                .from("conversation_participants")
                .insert(otherParticipants)
                .execute()
        }
        
        return try await fetchConversation(conversationId: newConversation.id)
    }
    
    /// Add participant to group conversation
    func addParticipant(conversationId: UUID, userId: UUID) async throws {
        let participant = ConversationParticipant(
            conversationId: conversationId,
            userId: userId,
            joinedAt: Date(),
            lastReadAt: nil
        )
        
        try await supabase.database
            .from("conversation_participants")
            .insert(participant)
            .execute()
    }
    
    /// Remove participant from group conversation
    func removeParticipant(conversationId: UUID, userId: UUID) async throws {
        try await supabase.database
            .from("conversation_participants")
            .delete()
            .eq("conversation_id", value: conversationId)
            .eq("user_id", value: userId)
            .execute()
    }
    
    /// Update last read timestamp for a conversation
    func updateLastRead(conversationId: UUID, userId: UUID) async throws {
        try await supabase.database
            .from("conversation_participants")
            .update(["last_read_at": Date()])
            .eq("conversation_id", value: conversationId)
            .eq("user_id", value: userId)
            .execute()
    }
}

