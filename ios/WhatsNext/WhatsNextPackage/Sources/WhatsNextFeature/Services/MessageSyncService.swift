import Foundation
import Combine

/// Service for syncing messages between local storage and remote server
@MainActor
final class MessageSyncService: ObservableObject {
    static let shared = MessageSyncService()
    
    @Published var isSyncing = false
    @Published var syncError: String?
    
    private let localStorage = LocalStorageService.shared
    private let messageService = MessageService()
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNetworkObserver()
    }
    
    /// Setup observer for network changes
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.syncOutbox()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Sync outbox messages to server
    func syncOutbox() async {
        guard networkMonitor.isConnected else {
            print("No network connection, skipping sync")
            return
        }
        
        guard !isSyncing else {
            print("Already syncing, skipping")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let outboxMessages = try localStorage.fetchOutboxMessages()
            
            guard !outboxMessages.isEmpty else {
                print("Outbox is empty")
                return
            }
            
            print("Syncing \(outboxMessages.count) messages from outbox")
            
            for outboxMessage in outboxMessages {
                do {
                    // Attempt to send message
                    let sentMessage = try await messageService.sendMessage(
                        conversationId: outboxMessage.conversationId,
                        senderId: outboxMessage.senderId,
                        content: outboxMessage.content,
                        localId: outboxMessage.localId
                    )
                    
                    // Save to local storage as synced
                    try localStorage.saveMessage(sentMessage)
                    
                    // Remove from outbox
                    try localStorage.removeFromOutbox(localId: outboxMessage.localId)
                    
                    print("Successfully synced message: \(outboxMessage.localId)")
                } catch {
                    // Update retry count
                    try localStorage.updateOutboxRetry(
                        localId: outboxMessage.localId,
                        error: error.localizedDescription
                    )
                    print("Failed to sync message \(outboxMessage.localId): \(error)")
                    
                    // Stop syncing on first error to preserve order
                    syncError = "Failed to sync some messages"
                    break
                }
            }
        } catch {
            syncError = "Failed to access outbox: \(error.localizedDescription)"
            print("Error syncing outbox: \(error)")
        }
    }
    
    /// Cache a message locally
    func cacheMessage(_ message: Message) async {
        do {
            try localStorage.saveMessage(message)
        } catch {
            print("Failed to cache message: \(error)")
        }
    }
    
    /// Add message to outbox for offline sending
    func addToOutbox(_ message: Message) async {
        do {
            try localStorage.addToOutbox(message)
            
            // Try to sync immediately if connected
            if networkMonitor.isConnected {
                await syncOutbox()
            }
        } catch {
            print("Failed to add message to outbox: \(error)")
        }
    }
    
    /// Fetch cached messages for a conversation
    func fetchCachedMessages(conversationId: UUID) -> [Message] {
        do {
            let localMessages = try localStorage.fetchMessages(conversationId: conversationId)
            return localMessages.map { $0.toMessage() }
        } catch {
            print("Failed to fetch cached messages: \(error)")
            return []
        }
    }
    
    /// Sync messages from server and update cache
    func syncMessagesFromServer(conversationId: UUID) async throws {
        let remoteMessages = try await messageService.fetchMessages(conversationId: conversationId)
        
        // Cache all fetched messages
        for message in remoteMessages {
            try localStorage.saveMessage(message)
        }
    }
}

