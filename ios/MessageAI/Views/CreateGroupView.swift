import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateGroupViewModel()
    
    let currentUserId: UUID
    let onGroupCreated: (Conversation) -> Void
    
    @State private var groupName = ""
    @State private var searchText = ""
    @State private var selectedUserIds: Set<UUID> = []
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Group Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    TextField("Enter group name", text: $groupName)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .focused($isNameFieldFocused)
                }
                .padding(.vertical)
                
                Divider()
                
                // Selected Users Preview
                if !selectedUserIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.users.filter { selectedUserIds.contains($0.id) }) { user in
                                SelectedUserChip(user: user) {
                                    selectedUserIds.remove(user.id)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGray6))
                    
                    Divider()
                }
                
                // User Search and Selection
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
                    } else if filteredUsers.isEmpty {
                        ContentUnavailableView(
                            "No Users Found",
                            systemImage: "person.2.slash",
                            description: Text("Try adjusting your search")
                        )
                    } else {
                        List(filteredUsers) { user in
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
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(!canCreate || viewModel.isCreating)
                }
            }
            .task {
                await viewModel.fetchUsers(currentUserId: currentUserId, search: "")
            }
            .onChange(of: searchText) { _, newValue in
                Task { await viewModel.fetchUsers(currentUserId: currentUserId, search: newValue) }
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
    }
    
    private var filteredUsers: [User] {
        viewModel.users.filter { $0.id != currentUserId }
    }
    
    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedUserIds.count >= 1
    }
    
    private func toggleUserSelection(_ userId: UUID) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
    
    private func createGroup() {
        Task {
            if let conversation = await viewModel.createGroup(
                name: groupName,
                creatorId: currentUserId,
                participantIds: Array(selectedUserIds)
            ) {
                onGroupCreated(conversation)
                dismiss()
            }
        }
    }
}

struct UserSelectionRow: View {
    let user: User
    let isSelected: Bool
    
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
                Text(user.displayName ?? user.username ?? "Unknown")
                    .font(.body)
                
                if let email = user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SelectedUserChip: View {
    let user: User
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(user.displayName ?? user.username ?? "Unknown")
                .font(.caption)
                .lineLimit(1)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(16)
    }
}

@MainActor
final class CreateGroupViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    private let conversationService = ConversationService()
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
    
    func createGroup(name: String, creatorId: UUID, participantIds: [UUID]) async -> Conversation? {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            let conversation = try await conversationService.createGroupConversation(
                name: name,
                creatorId: creatorId,
                participantIds: participantIds
            )
            return conversation
        } catch {
            errorMessage = "Failed to create group"
            print("Error creating group: \(error)")
            return nil
        }
    }
}

#Preview {
    CreateGroupView(
        currentUserId: UUID(),
        onGroupCreated: { _ in }
    )
}

