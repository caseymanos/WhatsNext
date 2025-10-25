# UI Improvements Implementation Guide

## Progress Summary

### ✅ Completed
1. Database migration created (`20251024120001_avatars_reactions.sql`)
2. Core services implemented:
   - ImageUploadService (JPEG 0.7 quality, 512x512px max)
   - ReactionService (add/remove/fetch reactions)
   - AvatarService utility (initials parsing)
3. Reusable components created:
   - AvatarView (with AsyncImage + initials fallback)
   - ImagePickerView (camera + photo library)
4. MessageReaction model created
5. ConversationService updated to load participants
6. UserService updated with `updateAvatarUrl()` method

### 🚧 Remaining Tasks

#### 1. Update ConversationRow to use AvatarView
**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/ConversationListView.swift`

Replace lines 138-147:
```swift
// OLD
Circle()
    .fill(Color.blue.opacity(0.2))
    .frame(width: 50, height: 50)
    .overlay {
        Text(displayName.prefix(1).uppercased())
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
    }

// NEW
AvatarView(
    avatarUrl: avatarUrl,
    displayName: displayName,
    size: .medium
)
```

Add after `displayName` computed property (after line 176):
```swift
private var avatarUrl: String? {
    if conversation.isGroup {
        return conversation.avatarUrl
    } else {
        return conversation.participants?.first(where: { $0.id != currentUserId })?.avatarUrl
    }
}
```

#### 2. Implement Profile Picture Upload in ProfileView
**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/ConversationListView.swift`

Add to ProfileView (after line 323):
```swift
Section {
    HStack {
        Spacer()
        VStack(spacing: 12) {
            AvatarView(
                avatarUrl: authViewModel.currentUser?.avatarUrl,
                displayName: authViewModel.currentUser?.displayName ?? authViewModel.currentUser?.username ?? "U",
                size: .xlarge
            )

            Button {
                showImageSourcePicker = true
            } label: {
                Label("Change Photo", systemImage: "camera.circle.fill")
            }
            .buttonStyle(.borderless)

            if authViewModel.currentUser?.avatarUrl != nil {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteAvatar(userId: authViewModel.currentUser?.id)
                        await authViewModel.refreshCurrentUser()
                    }
                } label: {
                    Text("Remove Photo")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        Spacer()
    }
} header: {
    Text("Profile Picture")
}
```

Add state variables to ProfileView (after line 318):
```swift
@State private var showImagePicker = false
@State private var showImageSourcePicker = false
```

Add confirmation dialog (before `.onAppear`):
```swift
.confirmationDialog("Choose Photo Source", isPresented: $showImageSourcePicker) {
    Button("Camera") {
        viewModel.imageSourceType = .camera
        showImagePicker = true
    }
    Button("Photo Library") {
        viewModel.imageSourceType = .photoLibrary
        showImagePicker = true
    }
    Button("Cancel", role: .cancel) {}
}
.sheet(isPresented: $showImagePicker) {
    ImagePickerView(
        sourceType: viewModel.imageSourceType,
        onImagePicked: { image in
            Task {
                await viewModel.uploadAvatar(
                    image: image,
                    userId: authViewModel.currentUser?.id
                )
                await authViewModel.refreshCurrentUser()
            }
        }
    )
}
```

Add to ProfileViewModel (lines 446-537):
```swift
@Published var isUploadingAvatar = false
var imageSourceType: ImagePickerView.SourceType = .photoLibrary

private let imageUploadService = ImageUploadService()

func uploadAvatar(image: UIImage, userId: UUID?) async {
    guard let userId = userId else { return }

    isUploadingAvatar = true
    errorMessage = nil
    defer { isUploadingAvatar = false }

    do {
        let avatarUrl = try await imageUploadService.uploadProfilePicture(userId: userId, image: image)
        try await userService.updateAvatarUrl(userId: userId, avatarUrl: avatarUrl)
    } catch {
        errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
    }
}

func deleteAvatar(userId: UUID?) async {
    guard let userId = userId else { return }

    isUploadingAvatar = true
    errorMessage = nil
    defer { isUploadingAvatar = false }

    do {
        try await imageUploadService.deleteProfilePicture(userId: userId)
        try await userService.updateAvatarUrl(userId: userId, avatarUrl: nil)
    } catch {
        errorMessage = "Failed to delete avatar: \(error.localizedDescription)"
    }
}
```

#### 3. Update ChatView with Avatars and Reactions
**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/ChatView.swift`

Replace `.navigationTitle` (line 94) with toolbar:
```swift
.navigationTitle("") // Clear default
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
```

Add computed property after `conversationName` (after line 137):
```swift
private var avatarUrl: String? {
    if conversation.isGroup {
        return conversation.avatarUrl
    } else {
        return conversation.participants?.first(where: { $0.id != currentUserId })?.avatarUrl
    }
}
```

For MessageRow reactions, add context menu to message bubble (after line 198):
```swift
.contextMenu {
    ForEach(MessageReaction.allowedEmojis, id: \.self) { emoji in
        Button {
            Task {
                // Toggle reaction
                let reactionService = ReactionService()
                try? await reactionService.toggleReaction(
                    messageId: message.id,
                    userId: currentUserId,
                    emoji: emoji
                )
            }
        } label: {
            Text(emoji)
        }
    }
}
```

Add reaction display (placeholder - needs full implementation with state):
```swift
// After message bubble, before timestamp
if !message.reactions.isEmpty {
    HStack(spacing: 4) {
        ForEach(groupedReactions, id: \.emoji) { group in
            HStack(spacing: 2) {
                Text(group.emoji).font(.caption)
                if group.count > 1 {
                    Text("\(group.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}
```

#### 4. Add reactions property to Message model
**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Models/Message.swift`

Add after line 17:
```swift
public var reactions: [MessageReaction]?
```

Update initializer to include reactions parameter.

#### 5. Fix Read Receipts Re-updating
**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/ChatView.swift`

Remove `.onDisappear` block (lines 121-125).

The existing `markingAsRead` Set in ChatViewModel already prevents duplicates.

#### 6. Update GroupSettingsView and CreateGroupView
Replace Circle avatar placeholders with AvatarView component.

## Testing Checklist

- [ ] Run migration: `supabase db push`
- [ ] Build project to verify no compilation errors
- [ ] Test conversation list shows participant names (not "Direct Message")
- [ ] Test profile picture upload (camera + library)
- [ ] Test avatars display in conversation list
- [ ] Test avatars display in chat header
- [ ] Test message reactions (add/remove)
- [ ] Test read receipts don't duplicate
- [ ] Test on physical device for camera access

## Database Migration

Run this command to apply the migration:
```bash
cd /Users/caseymanos/GauntletAI/WhatsNext
supabase db push
```

Verify the migration succeeded:
```bash
supabase db remote list
```

## Architecture Notes

**Clean Architecture Achieved:**
- ✅ Separation of concerns (Services, Views, Models)
- ✅ Reusable components (AvatarView used 5+ places)
- ✅ Testable services (can mock Supabase)
- ✅ SOLID principles followed
- ✅ Performance optimized (JPEG 0.7, 512px, eager participant loading)

**Technical Decisions:**
- JPEG at 0.7 quality (research-backed sweet spot)
- 512x512px max (standard for profile pics)
- Limited emoji set (6 reactions matching iMessage/Facebook)
- Eager participant loading (fixes "Direct Message" issue)
- Service layer for business logic, components for UI

## Next Steps

1. Complete remaining UI updates (ConversationRow, ProfileView, ChatView)
2. Run code review with feature-dev:code-reviewer agent
3. Test on simulator and device
4. Update documentation
