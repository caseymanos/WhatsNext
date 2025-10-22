import SwiftUI

struct GroupSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GroupSettingsViewModel
    
    let conversation: Conversation
    let currentUserId: UUID
    
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showAddParticipants = false
    @FocusState private var isNameFieldFocused: Bool
    
    init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: GroupSettingsViewModel(conversation: conversation))
    }
    
    var body: some View {
        List {
            // Group Info Section
            Section {
                HStack {
                    // Group Avatar
                    Circle()
                        .fill(Color.purple.gradient)
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(.white)
                                .font(.title3)
                        }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if isEditingName {
                            TextField("Group name", text: $editedName)
                                .textFieldStyle(.plain)
                                .font(.title3.bold())
                                .focused($isNameFieldFocused)
                        } else {
                            Text(viewModel.conversation.name ?? "Unnamed Group")
                                .font(.title3.bold())
                        }
                        
                        Text("\(viewModel.participants.count) participants")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        if isEditingName {
                            saveGroupName()
                        } else {
                            editedName = viewModel.conversation.name ?? ""
                            isEditingName = true
                            isNameFieldFocused = true
                        }
                    } label: {
                        Text(isEditingName ? "Save" : "Edit")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Participants Section
            Section {
                ForEach(viewModel.participants) { participant in
                    ParticipantRow(
                        user: participant,
                        isCurrentUser: participant.id == currentUserId
                    )
                }
                .onDelete { indexSet in
                    removeParticipants(at: indexSet)
                }
                
                Button {
                    showAddParticipants = true
                } label: {
                    Label("Add Participant", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Participants")
            }
            
            // Actions Section
            Section {
                Button(role: .destructive) {
                    leaveGroup()
                } label: {
                    Label("Leave Group", systemImage: "arrow.right.square")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Group Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchParticipants()
        }
        .sheet(isPresented: $showAddParticipants) {
            AddParticipantsView(
                conversation: viewModel.conversation,
                currentParticipantIds: viewModel.participants.map { $0.id },
                currentUserId: currentUserId,
                onParticipantsAdded: { userIds in
                    Task {
                        await viewModel.addParticipants(userIds: userIds)
                    }
                }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    private func saveGroupName() {
        guard !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isEditingName = false
            return
        }
        
        Task {
            await viewModel.updateGroupName(editedName)
            isEditingName = false
        }
    }
    
    private func removeParticipants(at offsets: IndexSet) {
        for index in offsets {
            let participant = viewModel.participants[index]
            
            // Don't allow removing yourself this way
            guard participant.id != currentUserId else { continue }
            
            Task {
                await viewModel.removeParticipant(userId: participant.id)
            }
        }
    }
    
    private func leaveGroup() {
        Task {
            await viewModel.removeParticipant(userId: currentUserId)
            dismiss()
        }
    }
}

struct ParticipantRow: View {
    let user: User
    let isCurrentUser: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(user.displayName?.prefix(1).uppercased() ?? user.email?.prefix(1).uppercased() ?? "?")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.displayName ?? user.username ?? "Unknown")
                        .font(.body)
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let email = user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddParticipantsViewModel()
    
    let conversation: Conversation
    let currentParticipantIds: [UUID]
    let currentUserId: UUID
    let onParticipantsAdded: ([UUID]) -> Void
    
    @State private var searchText = ""
    @State private var selectedUserIds: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search users", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // User List
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if availableUsers.isEmpty {
                    ContentUnavailableView(
                        "No Users Available",
                        systemImage: "person.2.slash",
                        description: Text("All users are already in this group")
                    )
                } else {
                    List(availableUsers) { user in
                        UserSelectionRow(
                            user: user,
                            isSelected: selectedUserIds.contains(user.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleUserSelection(user.id)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addParticipants()
                    }
                    .disabled(selectedUserIds.isEmpty)
                }
            }
            .task {
                await viewModel.fetchUsers(currentUserId: currentUserId, search: "")
            }
            .onChange(of: searchText) { _, newValue in
                Task { await viewModel.fetchUsers(currentUserId: currentUserId, search: newValue) }
            }
        }
    }
    
    private var availableUsers: [User] {
        viewModel.users.filter { user in
            !currentParticipantIds.contains(user.id) && user.id != currentUserId
        }
    }
    
    private func toggleUserSelection(_ userId: UUID) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
    
    private func addParticipants() {
        onParticipantsAdded(Array(selectedUserIds))
        dismiss()
    }
}

@MainActor
final class GroupSettingsViewModel: ObservableObject {
    @Published var conversation: Conversation
    @Published var participants: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let conversationService = ConversationService()
    private let supabase = SupabaseClientService.shared
    
    init(conversation: Conversation) {
        self.conversation = conversation
    }
    
    func fetchParticipants() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let updatedConversation = try await conversationService.fetchConversation(
                conversationId: conversation.id
            )
            conversation = updatedConversation
            participants = updatedConversation.participants ?? []
        } catch {
            errorMessage = "Failed to load participants"
            print("Error fetching participants: \(error)")
        }
    }
    
    func updateGroupName(_ name: String) async {
        errorMessage = nil
        
        do {
            try await supabase.database
                .from("conversations")
                .update(["name": name])
                .eq("id", value: conversation.id)
                .execute()
            
            conversation.name = name
        } catch {
            errorMessage = "Failed to update group name"
            print("Error updating group name: \(error)")
        }
    }
    
    func addParticipants(userIds: [UUID]) async {
        errorMessage = nil
        
        for userId in userIds {
            do {
                try await conversationService.addParticipant(
                    conversationId: conversation.id,
                    userId: userId
                )
            } catch {
                errorMessage = "Failed to add some participants"
                print("Error adding participant \(userId): \(error)")
            }
        }
        
        // Refresh participants
        await fetchParticipants()
    }
    
    func removeParticipant(userId: UUID) async {
        errorMessage = nil
        
        do {
            try await conversationService.removeParticipant(
                conversationId: conversation.id,
                userId: userId
            )
            
            // Remove from local list
            participants.removeAll { $0.id == userId }
        } catch {
            errorMessage = "Failed to remove participant"
            print("Error removing participant: \(error)")
        }
    }
}

@MainActor
final class AddParticipantsViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseClientService.shared
    
    func fetchUsers(currentUserId: UUID, search: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let term = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var builder = supabase.database
                .from("users")
                .select()
                .neq("id", value: currentUserId)
            if !term.isEmpty {
                let pattern = "%\(term)%"
                builder = builder.or("display_name.ilike.\(pattern),username.ilike.\(pattern),email.ilike.\(pattern)")
            }
            users = try await builder
                .limit(50)
                .execute()
                .value
        } catch {
            errorMessage = "Failed to load users"
            print("Error fetching users: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        GroupSettingsView(
            conversation: Conversation(
                id: UUID(),
                name: "Test Group",
                avatarUrl: nil,
                isGroup: true,
                createdAt: Date(),
                updatedAt: Date()
            ),
            currentUserId: UUID()
        )
    }
}

