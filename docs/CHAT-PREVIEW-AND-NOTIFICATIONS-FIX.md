# Chat Preview & Notifications Fix - October 22, 2025

## Issues Resolved

### 1. Chat Preview Not Updating in Conversation List
**Problem:** When a new message arrived in a conversation, the conversation list didn't update to show the latest message preview until the conversation was opened.

**Root Cause:** `ConversationListViewModel` wasn't subscribing to realtime updates for messages or conversation changes. Only individual `ChatView` instances subscribed to their specific conversations.

**Solution:**
- Added global message subscription in `ConversationListViewModel` via new `subscribeToAllMessages()` method
- Added conversation update subscription to track when `conversations.updated_at` changes
- Implemented `handleNewMessage()` to update last message and move conversation to top of list
- Implemented `handleConversationUpdate()` to refresh conversation metadata

**Files Changed:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/ViewModels/ConversationListViewModel.swift`
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/RealtimeService.swift`
- `ios/MessageAI/ViewModels/ConversationListViewModel.swift`
- `ios/MessageAI/Services/RealtimeService.swift`

---

### 2. Missing In-App Banners and Local Notifications
**Problem:** No notifications appeared when messages arrived, either as in-app banners or local notifications on simulator.

**Root Cause:** 
- No global subscription to trigger notifications for messages outside the currently open conversation
- Notification logic existed in `RealtimeService` but was only called from individual chat subscriptions

**Solution:**
- Integrated notification triggering in `ConversationListViewModel.showNotificationForMessage()`
- Checks `realtimeService.currentOpenConversationId` to avoid showing notifications for the active chat
- Shows in-app banner when app is active (foreground)
- Schedules local notification when app is background/inactive
- Leverages existing `InAppBannerManager` and `PushNotificationService` infrastructure

**Notification Flow:**
1. Message arrives via realtime subscription
2. `ConversationListViewModel.handleNewMessage()` processes it
3. If message is from another user, `showNotificationForMessage()` is called
4. Checks if conversation is currently open (no notification if yes)
5. Checks app state:
   - **Active:** Shows in-app banner at top of screen (auto-dismisses after 5s)
   - **Background/Inactive:** Schedules local notification

---

## Technical Details

### New Methods Added

#### RealtimeService
```swift
func subscribeToAllMessages(
    userId: UUID,
    onMessage: @escaping (Message) -> Void
) async throws
```
Subscribes to ALL message inserts across all tables, not just a specific conversation.

#### ConversationListViewModel
```swift
private func subscribeToUpdates(userId: UUID) async
private func handleConversationUpdate(_ updated: Conversation) async
private func handleNewMessage(_ message: Message) async
private func fetchLastMessage(for conversationId: UUID) async
private func showNotificationForMessage(_ message: Message, in conversation: Conversation) async
func cleanup() async
```

### Key Features

1. **Automatic List Reordering:** Conversations with new messages automatically move to the top
2. **Real-time Preview Updates:** Last message preview updates instantly without opening the conversation
3. **Smart Notifications:** No notifications shown for the currently open conversation
4. **In-App Banners:** Beautiful, dismissible banners when app is active
5. **Local Notifications:** Standard iOS notifications when app is backgrounded
6. **Proper Cleanup:** Subscriptions are properly cleaned up in `deinit`

---

## Testing on Simulator

### Expected Behavior

**Scenario 1: App Active, Conversation List Open**
- Receive message → In-app banner appears at top
- Banner auto-dismisses after 5 seconds
- Conversation moves to top with updated preview
- Tap banner → Navigate to that conversation

**Scenario 2: App Active, Chat View Open**
- Receive message in SAME conversation → No banner (already in chat)
- Receive message in DIFFERENT conversation → In-app banner appears
- Conversation list updates in background

**Scenario 3: App Backgrounded**
- Receive message → Local notification appears (standard iOS notification)
- Tap notification → Opens app to conversation list
- Conversation preview already updated

**Scenario 4: Multiple Devices**
- Send message from Device A
- Device B receives message instantly
- Preview updates without opening conversation
- Banner/notification appears on Device B

---

## Configuration Notes

### Push Notifications (Already Configured)
- Authorization requested on first app launch
- Device token automatically registered with APNs
- Token saved to `users.push_token` in Supabase
- Local notifications work on simulator without APNs setup

### In-App Banners
- `.inAppBanner()` modifier already applied to `ConversationListView`
- Managed by `InAppBannerManager.shared` singleton
- Banner navigation integrated with NavigationPath

---

## Files Modified

### WhatsNext Package
1. `Sources/WhatsNextFeature/ViewModels/ConversationListViewModel.swift`
   - Added: RealtimeService instance, subscription methods, notification logic
   - Modified: `fetchConversations()` now subscribes to updates
   - Added: Cleanup in deinit

2. `Sources/WhatsNextFeature/Services/RealtimeService.swift`
   - Added: `subscribeToAllMessages()` method for global message subscription

### MessageAI
1. `ViewModels/ConversationListViewModel.swift` (same changes as WhatsNext)
2. `Services/RealtimeService.swift` (same changes as WhatsNext)

---

## Next Steps

1. **Build and Test:** Run on simulator to verify notifications appear
2. **Multi-Device Testing:** Test with 2 simulators or devices
3. **Monitor Performance:** Check for subscription leaks or performance issues
4. **Production Push:** Configure APNs certificates for production push notifications

---

## Related Documents
- `BUGFIXES-2025-10-22.md` - Database fixes (read receipts, pg_net)
- `PUSH_NOTIFICATIONS_SETUP.md` - Complete push notification setup guide
- `Local-Notifications-Implementation.md` - Original local notification spec

