import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ConversationListViewModel()
    @State private var showingProfile = false
    @State private var showingNewConversation = false
    @State private var showingCreateGroup = false
    @State private var navPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView()
                } else if viewModel.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No conversations yet")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Tap + to start a new conversation")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            NavigationLink {
                                if let userId = authViewModel.currentUser?.id {
                                    ChatView(conversation: conversation, currentUserId: userId)
                                }
                            } label: {
                                ConversationRow(
                                    conversation: conversation,
                                    currentUserId: authViewModel.currentUser?.id ?? UUID()
                                )
                            }
                        }
                    }
                    .refreshable {
                        if let userId = authViewModel.currentUser?.id {
                            await viewModel.fetchConversations(userId: userId)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .inAppBanner { conversationId in
                // Handle banner tap - navigate to the conversation
                if let conversation = viewModel.conversations.first(where: { $0.id == conversationId }) {
                    navPath.append(conversation)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingNewConversation = true
                        } label: {
                            Label("New Direct Message", systemImage: "person.fill")
                        }
                        
                        Button {
                            showingCreateGroup = true
                        } label: {
                            Label("New Group", systemImage: "person.3.fill")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewConversation) {
                if let userId = authViewModel.currentUser?.id {
                    NewConversationView(currentUserId: userId) { conversation in
                        viewModel.conversations.insert(conversation, at: 0)
                        showingNewConversation = false
                        DispatchQueue.main.async {
                            navPath.append(conversation)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                if let userId = authViewModel.currentUser?.id {
                    CreateGroupView(currentUserId: userId) { conversation in
                        // Add the new group to the list
                        viewModel.conversations.insert(conversation, at: 0)
                    }
                }
            }
            .task {
                if let userId = authViewModel.currentUser?.id {
                    await viewModel.fetchConversations(userId: userId)
                }
            }
            .navigationDestination(for: Conversation.self) { conv in
                if let userId = authViewModel.currentUser?.id {
                    ChatView(conversation: conv, currentUserId: userId)
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: UUID
    @StateObject private var viewModel = ConversationListViewModel()
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(displayName.prefix(1).uppercased())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.headline)
                    
                    Spacer()
                    
                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage.content ?? "Media")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var displayName: String {
        viewModel.displayName(for: conversation, currentUserId: currentUserId)
    }
}

struct NewConversationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = NewConversationViewModel()
    
    let currentUserId: UUID
    let onConversationCreated: (Conversation) -> Void
    
    @State private var searchText = ""
    @State private var selectedUser: User?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search users", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newValue in
                            Task { await viewModel.searchUsers(currentUserId: currentUserId, search: newValue) }
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                if viewModel.isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView("No Users Found", systemImage: "person.2.slash", description: Text("Try adjusting your search"))
                } else {
                    List(viewModel.results) { user in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.displayName ?? user.username ?? "Unknown")
                                if let email = user.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if selectedUser?.id == user.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedUser = user }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { Task { await createDM() } }
                        .disabled(selectedUser == nil || viewModel.isCreating)
                }
            }
            .task { await viewModel.searchUsers(currentUserId: currentUserId, search: "") }
        }
    }
    
    private func createDM() async {
        guard let other = selectedUser else { return }
        if let conv = await viewModel.createDirect(currentUserId: currentUserId, otherUserId: other.id) {
            onConversationCreated(conv)
            dismiss()
        }
    }
}

@MainActor
final class NewConversationViewModel: ObservableObject {
    @Published var results: [User] = []
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseClientService.shared
    private let conversationService = ConversationService()
    
    func searchUsers(currentUserId: UUID, search: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            var builder = supabase.database
                .from("users")
                .select()
                .neq("id", value: currentUserId)
            if !term.isEmpty {
                let pattern = "%\(term)%"
                builder = builder.or("display_name.ilike.\(pattern),username.ilike.\(pattern),email.ilike.\(pattern)")
            }
            results = try await builder.limit(50).execute().value
        } catch {
            errorMessage = "Failed to search users"
        }
    }
    
    func createDirect(currentUserId: UUID, otherUserId: UUID) async -> Conversation? {
        isCreating = true
        defer { isCreating = false }
        do {
            return try await conversationService.createDirectConversation(currentUserId: currentUserId, otherUserId: otherUserId)
        } catch {
            errorMessage = "Failed to start conversation"
            return nil
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = authViewModel.currentUser {
                        LabeledContent("Email", value: user.email ?? "N/A")
                        LabeledContent("Username", value: user.username ?? "Not set")
                        LabeledContent("Display Name", value: user.displayName ?? "Not set")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                            dismiss()
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Sign Out")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(AuthViewModel())
}

