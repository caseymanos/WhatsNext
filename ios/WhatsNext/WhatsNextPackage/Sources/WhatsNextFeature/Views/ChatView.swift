import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    let currentUserId: UUID

    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showGroupSettings = false
    @FocusState private var isInputFocused: Bool
    @State private var selectedImages: [UIImage] = []
    @State private var photoCaption = ""
    @State private var previousMessageCount = 0 // Track previous count to detect new messages

    init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation, currentUserId: currentUserId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Offline indicator
            if !viewModel.isOnline {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("No connection. Messages will send when online.")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange)
            }

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
                                syncStatus: viewModel.getSyncStatus(for: message),
                                isGroupChat: conversation.isGroup,
                                senderName: getSenderName(for: message),
                                currentUserId: currentUserId,
                                readReceipts: message.readReceipts ?? [],
                                onRetry: {
                                    if let localId = message.localId {
                                        Task {
                                            await viewModel.retryMessage(localId: localId)
                                        }
                                    }
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    // OPTIMIZATION: Only animate scroll for truly NEW messages, not on view reappearance
                    let isNewMessage = previousMessageCount > 0 && newCount == previousMessageCount + 1
                    previousMessageCount = newCount

                    if let lastMessage = viewModel.messages.last {
                        if isNewMessage {
                            // Animate only for new incoming messages
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        } else {
                            // Instant scroll on initial load or view reappearance (no cascade)
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
            
            // Photo preview
            if !selectedImages.isEmpty {
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button {
                                        selectedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .background(Circle().fill(.black.opacity(0.6)))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Caption field for photos
                    TextField("Add a caption...", text: $photoCaption, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .lineLimit(1...3)
                        .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }

            // Input Bar
            HStack(spacing: 12) {
                // Photo button
                PhotoPickerButton(selectedImages: $selectedImages)

                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .onChange(of: messageText) { _, newValue in
                        if !newValue.isEmpty {
                            Task {
                                await viewModel.sendTypingIndicator()
                            }
                        }
                    }

                Button {
                    if !selectedImages.isEmpty {
                        sendPhotoMessage()
                    } else {
                        sendMessage()
                    }
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(
                        avatarUrl: avatarUrl,
                        displayName: conversationName,
                        size: .small
                    )
                    Text(conversationName)
                        .font(.headline)
                }
            }

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

    private var avatarUrl: String? {
        if conversation.isGroup {
            return conversation.avatarUrl
        } else {
            return conversation.participants?.first(where: { $0.id != currentUserId })?.avatarUrl
        }
    }

    private var canSend: Bool {
        if !selectedImages.isEmpty {
            return true
        }
        return !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let text = messageText
        messageText = ""

        Task {
            await viewModel.sendMessage(text)
        }
    }

    private func sendPhotoMessage() {
        let images = selectedImages
        let caption = photoCaption.isEmpty ? nil : photoCaption

        selectedImages = []
        photoCaption = ""

        Task {
            await viewModel.sendPhotos(images, caption: caption)
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
    let syncStatus: MessageSyncStatus
    let isGroupChat: Bool
    let senderName: String?
    let currentUserId: UUID
    let readReceipts: [ReadReceipt]
    let onRetry: () -> Void

    @State private var reactions: [MessageReaction] = []
    @State private var showReadReceiptDetails = false
    private let reactionService = ReactionService()

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

                // Photo message
                if message.messageType == .image {
                    VStack(alignment: .leading, spacing: 4) {
                        if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 200, height: 200)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: 250, maxHeight: 250)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 200, height: 200)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }

                        // Caption
                        if let caption = message.content, !caption.isEmpty {
                            Text(caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                                .foregroundStyle(isCurrentUser ? .white : .primary)
                                .cornerRadius(16)
                        }
                    }
                    .opacity(isOptimistic ? 0.6 : 1.0)
                } else {
                    // Text message
                    Text(message.content ?? "")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(isCurrentUser ? .white : .primary)
                        .cornerRadius(16)
                        .opacity(isOptimistic ? 0.6 : 1.0)
                        .contextMenu {
                            ForEach(MessageReaction.allowedEmojis, id: \.self) { emoji in
                                Button {
                                    Task {
                                        await toggleReaction(emoji: emoji)
                                    }
                                } label: {
                                    Text(emoji)
                                }
                            }
                        }
                }

                // Display reactions
                if !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(groupedReactions, id: \.emoji) { group in
                            ReactionBubble(
                                emoji: group.emoji,
                                count: group.count,
                                hasUserReacted: group.hasUserReacted
                            ) {
                                Task {
                                    await toggleReaction(emoji: group.emoji)
                                }
                            }
                        }
                    }
                }
                
                HStack(spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isCurrentUser {
                        // Show sync status (sending/failed) or receipt status (sent)
                        switch syncStatus {
                        case .sending:
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                        case .failed:
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)

                                Button {
                                    onRetry()
                                } label: {
                                    Text("Retry")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }

                        case .sent:
                            // Show read receipt status for sent messages
                            if !receiptStatus.icon.isEmpty {
                                Button {
                                    showReadReceiptDetails.toggle()
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: receiptStatus.icon)
                                            .font(.caption2)
                                            .foregroundStyle(receiptStatus.color == "blue" ? .blue : .secondary)

                                        if case .readBySome(let count) = receiptStatus {
                                            Text("(\(count))")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showReadReceiptDetails) {
                                    ReadReceiptDetailsView(readReceipts: readReceipts)
                                        .presentationCompactAdaptation(.popover)
                                }
                            }
                        }
                    }
                }
            }
            
            if !isCurrentUser { Spacer() }
        }
        .task {
            await loadReactions()
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

    private var groupedReactions: [GroupedReaction] {
        let grouped = Dictionary(grouping: reactions, by: { $0.emoji })
        return grouped.map { emoji, reactions in
            GroupedReaction(
                emoji: emoji,
                count: reactions.count,
                hasUserReacted: reactions.contains(where: { $0.userId == currentUserId })
            )
        }.sorted { $0.emoji < $1.emoji }
    }

    private func loadReactions() async {
        do {
            reactions = try await reactionService.fetchReactions(messageId: message.id)
        } catch {
            print("Failed to load reactions: \(error)")
        }
    }

    private func toggleReaction(emoji: String) async {
        do {
            try await reactionService.toggleReaction(
                messageId: message.id,
                userId: currentUserId,
                emoji: emoji
            )
            // Reload reactions after toggle
            await loadReactions()
        } catch {
            print("Failed to toggle reaction: \(error)")
        }
    }
}

struct GroupedReaction {
    let emoji: String
    let count: Int
    let hasUserReacted: Bool
}

struct ReactionBubble: View {
    let emoji: String
    let count: Int
    let hasUserReacted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text(emoji).font(.caption)
                if count > 1 {
                    Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                hasUserReacted
                    ? Color.blue.opacity(0.2)
                    : Color(.systemGray6)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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

struct ReadReceiptDetailsView: View {
    let readReceipts: [ReadReceipt]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if readReceipts.isEmpty {
                Text("Not read yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(readReceipts) { receipt in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(receipt.readAt, style: .date)
                            .font(.caption)
                        Text(receipt.readAt, style: .time)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 150)
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

