# Local Notifications & In-App Banners Implementation

## Overview
Implemented local notifications and in-app banners for messages received via websocket/realtime subscriptions, since push notifications don't work in iOS simulators.

## Date Implemented
October 22, 2025

## Components Added/Modified

### 1. PushNotificationService.swift
**Added:**
- `scheduleLocalNotification()` method to create local notifications for incoming messages
- Triggers local notifications when messages arrive via websocket

**Location:** 
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/PushNotificationService.swift`

### 2. InAppMessageBanner.swift (NEW)
**Created new file with:**
- `InAppMessageBanner` view - Banner UI component that slides down from top
- `InAppBannerManager` - Singleton manager to control banner display
- `InAppBannerModifier` - View modifier to attach banner support to any view
- `.inAppBanner()` view extension for easy integration

**Features:**
- Auto-dismisses after 5 seconds
- Tap to navigate to conversation
- Manual dismiss with X button
- Smooth animations (slide in/out)
- Shows sender avatar, name, and message preview

**Location:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/InAppMessageBanner.swift`

### 3. RealtimeService.swift
**Modified:**
- Added `currentOpenConversationId` property to track which conversation is currently open
- Updated `subscribeToMessages()` signature to include:
  - `currentUserId: UUID` - to filter out own messages
  - `conversationName: String` - for notification display
- Added `handleIncomingMessageNotification()` private method that:
  - Checks app state (foreground/background)
  - Shows in-app banner if app is active and user is not viewing that conversation
  - Sends local notification if app is in background/inactive

**Location:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/RealtimeService.swift`

### 4. ChatViewModel.swift
**Modified:**
- Updated `subscribeToRealtimeUpdates()` to pass new required parameters
- Added `getConversationName()` helper method
- Sets `realtimeService.currentOpenConversationId` when conversation opens
- Clears `currentOpenConversationId` in deinit

**Location:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/ViewModels/ChatViewModel.swift`

### 5. ConversationListViewModel.swift
**Modified:**
- Added `init()` with app lifecycle observer setup
- Added `setupAppLifecycleObserver()` - listens for `UIApplication.willEnterForegroundNotification`
- Added `refreshConversationsOnForeground()` - silently refreshes last messages when app returns to foreground
- Changed `fetchLastMessages()` from private to public for foreground refresh

**Location:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/ViewModels/ConversationListViewModel.swift`

### 6. ConversationListView.swift
**Modified:**
- Added `.inAppBanner()` modifier to the NavigationStack
- Banner tap handler navigates to the appropriate conversation using `navPath.append()`

**Location:**
- `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Views/ConversationListView.swift`

## How It Works

### Message Received via Websocket (App in Background)
1. RealtimeService receives message via Supabase realtime subscription
2. `handleIncomingMessageNotification()` detects app is in background
3. Schedules local notification via `PushNotificationService.scheduleLocalNotification()`
4. iOS displays notification banner with sound
5. User can tap notification to open app and navigate to conversation

### Message Received via Websocket (App in Foreground)
1. RealtimeService receives message via Supabase realtime subscription
2. `handleIncomingMessageNotification()` detects app is active
3. Checks if user is currently viewing the conversation that received the message
4. If viewing different conversation: Shows in-app banner via `InAppBannerManager.shared.showBanner()`
5. If viewing same conversation: No notification (just updates message list)

### App Reopened After Being Closed
1. User reopens app
2. `UIApplication.willEnterForegroundNotification` fires
3. `ConversationListViewModel.refreshConversationsOnForeground()` called
4. Silently fetches latest messages for all conversations
5. Conversation list updates with new message previews

## Testing Instructions

### Test Local Notifications (Background)
1. Launch app on simulator
2. Send app to background (Cmd+Shift+H or Device > Home)
3. Send a message from another user via Supabase/database
4. Local notification should appear on simulator screen
5. Tap notification to open app and view conversation

### Test In-App Banners (Foreground)
1. Launch app on simulator
2. Navigate to conversation list (not inside a specific conversation)
3. Send a message from another user via Supabase/database
4. In-app banner should slide down from top
5. Tap banner to navigate to that conversation
6. OR wait 5 seconds for auto-dismiss

### Test Message Preview Updates
1. Launch app, view conversation list
2. Send app to background or close app
3. Send messages from other users
4. Reopen app
5. Conversation list should show updated last messages

## Technical Details

### Platform Support
- Uses `#if canImport(UIKit)` for iOS-specific features
- Falls back gracefully on macOS (local notifications only)

### State Management
- `InAppBannerManager` is a singleton with `@Published` state
- Banner state is observed via `@ObservedObject` in view modifier
- App lifecycle managed through `NotificationCenter` observers

### Performance Considerations
- Only one banner shown at a time (new replaces old)
- Silent refresh on foreground (no loading spinner)
- Unsubscribes from realtime channels in deinit

## Future Enhancements
- Badge count on app icon
- Notification grouping by conversation
- Rich notifications with images
- Custom notification sounds per conversation
- Notification action buttons (reply, mark as read)
- Local notification history

## Related Files
- `/docs/PUSH_NOTIFICATIONS_SETUP.md` - Original push notification setup
- `/docs/Challenge.md` - Project requirements
- `/localruns.txt` - Build and test commands

## Build & Test Commands

### Build for simulator:
```bash
xcodebuild -workspace ios/WhatsNext/WhatsNext.xcworkspace \
  -scheme WhatsNext \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

### Run on simulator:
```bash
xcrun simctl launch C27A8895-154B-45A1-BD7C-EA5326537107 com.gauntletai.whatsnext
```

## Notes
- Local notifications work in simulator (unlike remote push notifications)
- Requires notification permissions to be granted by user
- Notifications requested on app first launch
- Messages from self are filtered out from notifications

