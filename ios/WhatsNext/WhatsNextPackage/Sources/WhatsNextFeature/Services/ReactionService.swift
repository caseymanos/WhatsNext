import Foundation
import Supabase

enum ReactionServiceError: LocalizedError {
    case invalidEmoji
    case notFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidEmoji:
            return "Invalid emoji selected"
        case .notFound:
            return "Reaction not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

public final class ReactionService {
    private let supabase = SupabaseClientService.shared

    public init() {}

    /// Add reaction to message
    public func addReaction(messageId: UUID, userId: UUID, emoji: String) async throws {
        guard MessageReaction.allowedEmojis.contains(emoji) else {
            throw ReactionServiceError.invalidEmoji
        }

        struct ReactionInsert: Encodable {
            let message_id: UUID
            let user_id: UUID
            let emoji: String
        }

        let reaction = ReactionInsert(
            message_id: messageId,
            user_id: userId,
            emoji: emoji
        )

        do {
            try await supabase.database
                .from("message_reactions")
                .insert(reaction)
                .execute()
        } catch {
            throw ReactionServiceError.networkError(error)
        }
    }

    /// Remove reaction from message
    public func removeReaction(messageId: UUID, userId: UUID, emoji: String) async throws {
        do {
            try await supabase.database
                .from("message_reactions")
                .delete()
                .eq("message_id", value: messageId)
                .eq("user_id", value: userId)
                .eq("emoji", value: emoji)
                .execute()
        } catch {
            throw ReactionServiceError.networkError(error)
        }
    }

    /// Fetch reactions for a single message
    public func fetchReactions(messageId: UUID) async throws -> [MessageReaction] {
        do {
            let reactions: [MessageReaction] = try await supabase.database
                .from("message_reactions")
                .select()
                .eq("message_id", value: messageId)
                .execute()
                .value

            return reactions
        } catch {
            throw ReactionServiceError.networkError(error)
        }
    }

    /// Fetch reactions for multiple messages (batch operation)
    public func fetchReactionsForMessages(_ messageIds: [UUID]) async throws -> [UUID: [MessageReaction]] {
        guard !messageIds.isEmpty else { return [:] }

        do {
            let reactions: [MessageReaction] = try await supabase.database
                .from("message_reactions")
                .select()
                .in("message_id", values: messageIds)
                .execute()
                .value

            // Group reactions by message ID
            var grouped: [UUID: [MessageReaction]] = [:]
            for reaction in reactions {
                if grouped[reaction.messageId] == nil {
                    grouped[reaction.messageId] = []
                }
                grouped[reaction.messageId]?.append(reaction)
            }

            return grouped
        } catch {
            throw ReactionServiceError.networkError(error)
        }
    }

    /// Toggle reaction (add if doesn't exist, remove if exists)
    public func toggleReaction(messageId: UUID, userId: UUID, emoji: String) async throws {
        guard MessageReaction.allowedEmojis.contains(emoji) else {
            throw ReactionServiceError.invalidEmoji
        }

        do {
            // Check if reaction exists
            let existing: [MessageReaction] = try await supabase.database
                .from("message_reactions")
                .select()
                .eq("message_id", value: messageId)
                .eq("user_id", value: userId)
                .eq("emoji", value: emoji)
                .execute()
                .value

            if existing.isEmpty {
                // Add reaction
                try await addReaction(messageId: messageId, userId: userId, emoji: emoji)
            } else {
                // Remove reaction
                try await removeReaction(messageId: messageId, userId: userId, emoji: emoji)
            }
        } catch {
            throw ReactionServiceError.networkError(error)
        }
    }
}
