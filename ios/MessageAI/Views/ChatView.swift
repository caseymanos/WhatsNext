import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    let currentUserId: UUID
    
    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showGroupSettings = false
    @FocusState private var isInputFocused: Bool
    
    init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation, currentUserId: currentUserId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(
                                message: message,
                                isCurrentUser: message.senderId == currentUserId,
                                isOptimistic: viewModel.optimisticMessages[message.localId ?? ""] != nil,
                                receiptStatus: viewModel.getReceiptStatus(for: message),
                                isGroupChat: conversation.isGroup,
                                senderName: getSenderName(for: message)
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // Scroll to bottom when new message arrives
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Typing Indicator
            if !viewModel.typingUsers.isEmpty {
                HStack {
                    TypingIndicatorView()
                    Text("Someone is typing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            // Input Bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onChange(of: messageText) { _, newValue in
                        if !newValue.isEmpty {
                            Task {
                                await viewModel.sendTypingIndicator()
                            }
                        }
                    }
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend || viewModel.isSending)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(conversationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if conversation.isGroup {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showGroupSettings = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showGroupSettings) {
            NavigationStack {
                GroupSettingsView(conversation: conversation, currentUserId: currentUserId)
            }
        }
        .task {
            await viewModel.fetchMessages()
            await viewModel.fetchReadReceipts()
        }
        .onAppear {
            Task {
                await viewModel.markMessagesAsRead()
            }
        }
        .onDisappear {
            Task {
                await viewModel.markMessagesAsRead()
            }
        }
    }
    
    private var conversationName: String {
        if conversation.isGroup {
            return conversation.name ?? "Group Chat"
        } else {
            if let otherUser = conversation.participants?.first(where: { $0.id != currentUserId }) {
                return otherUser.displayName ?? otherUser.username ?? otherUser.email ?? "Chat"
            }
            return "Chat"
        }
    }
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func sendMessage() {
        let text = messageText
        messageText = ""
        
        Task {
            await viewModel.sendMessage(text)
        }
    }
    
    private func getSenderName(for message: Message) -> String? {
        guard conversation.isGroup && message.senderId != currentUserId else {
            return nil
        }
        
        // Try to get sender from message
        if let sender = message.sender {
            return sender.displayName ?? sender.username ?? sender.email
        }
        
        // Try to find sender in conversation participants
        if let sender = conversation.participants?.first(where: { $0.id == message.senderId }) {
            return sender.displayName ?? sender.username ?? sender.email
        }
        
        return "Unknown"
    }
}

struct MessageRow: View {
    let message: Message
    let isCurrentUser: Bool
    let isOptimistic: Bool
    let receiptStatus: MessageReceiptStatus
    let isGroupChat: Bool
    let senderName: String?
    
    var body: some View {
        HStack {
            if isCurrentUser { Spacer() }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Show sender name in groups for other users' messages
                if isGroupChat && !isCurrentUser, let senderName = senderName {
                    Text(senderName)
                        .font(.caption)
                        .foregroundStyle(senderColor)
                        .padding(.horizontal, 4)
                }
                
                Text(message.content ?? "")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                    .opacity(isOptimistic ? 0.6 : 1.0)
                
                HStack(spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if isOptimistic {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isCurrentUser {
                        // Show read receipt status
                        if !receiptStatus.icon.isEmpty {
                            Image(systemName: receiptStatus.icon)
                                .font(.caption2)
                                .foregroundStyle(receiptStatus.color == "blue" ? .blue : .secondary)
                        }
                        
                        if case .readBySome(let count) = receiptStatus {
                            Text("(\(count))")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            
            if !isCurrentUser { Spacer() }
        }
    }
    
    // Generate a consistent color for the sender based on their ID
    private var senderColor: Color {
        guard let senderName = senderName else { return .secondary }
        
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]
        let hash = abs(senderName.hashValue)
        let index = hash % colors.count
        return colors[index]
    }
}

struct TypingIndicatorView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(
            conversation: Conversation(
                id: UUID(),
                name: "Test Chat",
                avatarUrl: nil,
                isGroup: false,
                createdAt: Date(),
                updatedAt: Date(),
                participants: [],
                lastMessage: nil
            ),
            currentUserId: UUID()
        )
    }
}

