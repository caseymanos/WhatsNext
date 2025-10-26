import SwiftUI
#if AI_FEATURES

struct AITabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var vm = AIViewModel()
    @State private var conversations: [Conversation] = []
    @State private var isLoadingConversations = false
    @State private var selectedFeature: AIFeature = .events
    @State private var showSyncSettings = false

    enum AIFeature: String, CaseIterable {
        case events = "Events"
        case decisions = "Decisions"
        case priority = "Priority"
        case rsvps = "RSVPs"
        case deadlines = "Deadlines"
        case conflicts = "Conflicts"
        case assistant = "Assistant"

        var icon: String {
            switch self {
            case .events: return "calendar"
            case .decisions: return "list.bullet.clipboard"
            case .priority: return "exclamationmark.triangle"
            case .rsvps: return "envelope.badge"
            case .deadlines: return "clock.badge"
            case .conflicts: return "calendar.badge.exclamationmark"
            case .assistant: return "sparkles"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                featureSelector
                Divider()
                conversationSelectorView
                Divider()

                // Show conflict notification banner
                if vm.totalUnresolvedConflictsCount > 0 && selectedFeature != .conflicts {
                    conflictNotificationBanner
                    Divider()
                }

                featureContent
            }
            .navigationTitle("AI Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        print("🔧 Gear button tapped - opening settings")
                        showSyncSettings = true
                    } label: {
                        Image(systemName: "calendar.badge.gearshape")
                            .font(.title3)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                }
            }
            .sheet(isPresented: $showSyncSettings) {
                CalendarSyncSettingsView(viewModel: vm)
            }
            .task {
                await loadConversations()
                if let userId = authViewModel.currentUser?.id {
                    vm.currentUserId = userId
                    await vm.loadSyncSettings()
                }
            }
            .refreshable {
                await loadConversations()
            }
        }
    }

    private var featureSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AIFeature.allCases, id: \.self) { feature in
                    featureButton(feature)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private func featureButton(_ feature: AIFeature) -> some View {
        Button {
            selectedFeature = feature
        } label: {
            HStack(spacing: 6) {
                Image(systemName: feature.icon)
                    .font(.caption)
                Text(feature.rawValue)
                    .font(.caption.bold())

                // Show badge for unresolved conflicts
                if feature == .conflicts && vm.totalUnresolvedConflictsCount > 0 {
                    Text("\(vm.totalUnresolvedConflictsCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedFeature == feature ? Color.blue : Color(.systemGray6))
            .foregroundStyle(selectedFeature == feature ? .white : .primary)
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var conversationSelectorView: some View {
        if isLoadingConversations {
            ProgressView("Loading conversations...")
                .frame(height: 50)
        } else if conversations.isEmpty {
            Text("No conversations available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 50)
        } else {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(conversations) { conversation in
                            conversationChip(conversation)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 60)

                if !vm.selectedConversations.isEmpty {
                    analyzeButton
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var analyzeButton: some View {
        Button {
            Task {
                await analyzeForSelectedFeature()
            }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Analyze \(vm.selectedConversations.count) conversation(s)")
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(8)
        }
        .disabled(vm.isAnalyzing)
    }

    private func conversationChip(_ conversation: Conversation) -> some View {
        let isSelected = vm.selectedConversations.contains(conversation.id)
        let name = displayName(for: conversation)

        return Text(name)
            .font(.caption.bold())
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
            .foregroundStyle(isSelected ? .blue : .primary)
            .cornerRadius(8)
            .onTapGesture {
                if isSelected {
                    vm.selectedConversations.remove(conversation.id)
                } else {
                    vm.selectedConversations.insert(conversation.id)
                }
            }
    }

    @ViewBuilder
    private var featureContent: some View {
        switch selectedFeature {
        case .events:
            eventsView
        case .decisions:
            DecisionsView(viewModel: vm)
        case .priority:
            PriorityMessagesView(viewModel: vm)
        case .rsvps:
            RSVPView(viewModel: vm)
        case .deadlines:
            DeadlinesView(viewModel: vm)
        case .conflicts:
            if let firstConv = vm.selectedConversations.first ?? conversations.first?.id {
                ConflictDetectionView(conversationId: firstConv)
            } else {
                Text("Select a conversation to check for conflicts")
                    .foregroundStyle(.secondary)
            }
        case .assistant:
            if let firstConv = vm.selectedConversations.first ?? conversations.first?.id {
                ProactiveAssistantView(viewModel: vm, conversationId: firstConv)
            } else {
                Text("Select a conversation to use the assistant")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eventsView: some View {
        Group {
            if vm.isAnalyzing {
                ProgressView("Finding events...")
            } else if vm.eventsByConversation.isEmpty {
                emptyStateView(icon: "calendar", message: "No events found")
            } else {
                List {
                    ForEach(Array(vm.eventsByConversation.keys), id: \.self) { convId in
                        if let events = vm.eventsByConversation[convId], !events.isEmpty {
                            Section(header: conversationHeader(convId)) {
                                ForEach(events) { event in
                                    eventRow(event)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func conversationHeader(_ convId: UUID) -> some View {
        if let conversation = conversations.first(where: { $0.id == convId }) {
            return Text(displayName(for: conversation))
        } else {
            return Text("Conversation \(convId.uuidString.prefix(4))")
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title).font(.headline)
                HStack {
                    Text(event.date, style: .date)
                    if let time = event.time {
                        Text("•")
                        Text(time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let location = event.location {
                    Label(location, systemImage: "location")
                        .font(.caption)
                }
                if let description = event.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Sync status indicator
            syncStatusBadge(event.parsedSyncStatus)
        }
        .padding(.vertical, 4)
    }

    private func syncStatusBadge(_ status: SyncStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption)
            if vm.isSyncing {
                Text(status.displayName)
                    .font(.caption2)
            }
        }
        .foregroundStyle(status.color)
    }

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadConversations() async {
        guard let userId = authViewModel.currentUser?.id else { return }

        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            let service = ConversationService()
            conversations = try await service.fetchConversations(userId: userId)
        } catch {
            print("Failed to load conversations for AI: \(error)")
        }
    }

    private func analyzeForSelectedFeature() async {
        switch selectedFeature {
        case .events:
            await vm.analyzeSelectedForEvents()
        case .decisions:
            await vm.analyzeSelectedForDecisions()
        case .priority:
            await vm.analyzeSelectedForPriority()
        case .rsvps:
            await vm.analyzeSelectedForRSVPs()
        case .deadlines:
            await vm.analyzeSelectedForDeadlines()
        case .conflicts:
            // Conflicts are handled by ConflictDetectionView directly
            break
        case .assistant:
            if let firstConv = vm.selectedConversations.first ?? conversations.first?.id {
                await vm.runProactiveAssistant(conversationId: firstConv)
            }
        }
    }

    private func displayName(for conversation: Conversation) -> String {
        if conversation.isGroup {
            return conversation.name ?? "Group Chat"
        } else {
            // For 1:1 chats, show the other participant's name
            guard let currentUserId = authViewModel.currentUser?.id else {
                return "Chat"
            }
            if let otherUser = conversation.participants?.first(where: { $0.id != currentUserId }) {
                let name = otherUser.displayName ?? otherUser.username ?? otherUser.email ?? "Unknown User"
                return formatName(name)
            }
            return "Direct Message"
        }
    }

    private func formatName(_ fullName: String) -> String {
        let components = fullName.split(separator: " ").map(String.init)

        guard components.count >= 2 else {
            // If it's just one word (username or first name only), return as is
            return fullName
        }

        let firstName = components[0]
        let lastNameInitial = components[1].prefix(1)
        return "\(firstName) \(lastNameInitial)."
    }

    private var conflictNotificationBanner: some View {
        Button {
            selectedFeature = .conflicts
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduling Conflicts Detected")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("\(vm.totalUnresolvedConflictsCount) unresolved conflict\(vm.totalUnresolvedConflictsCount == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

#endif


