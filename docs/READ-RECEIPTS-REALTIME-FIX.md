# Read Receipts Real-time Update Fix - October 22, 2025

## Issue Fixed

**Problem:** Read receipts (checkmarks indicating message has been read) were not updating in real-time. When User B read User A's message, User A's UI didn't show the updated read status until the conversation was closed and reopened.

**Root Cause:** Read receipts were only fetched once when the chat view loaded (in the `.task` block). There was no realtime subscription to the `read_receipts` table to receive updates when other users marked messages as read.

## Solution

Added realtime subscription to the `read_receipts` table that:
1. Subscribes when a chat conversation opens
2. Listens for both INSERT and UPDATE events (since we use upsert)
3. Updates the message's `readReceipts` array when a new receipt arrives
4. Triggers UI update automatically via SwiftUI's `@Published` property

## Technical Implementation

### New Methods Added

#### RealtimeService.swift
```swift
/// Subscribe to read receipts for messages in a conversation
func subscribeToReadReceipts(
    conversationId: UUID,
    onReceipt: @escaping (ReadReceipt) -> Void
) async throws

/// Unsubscribe from read receipts for a conversation
func unsubscribeFromReadReceipts(conversationId: UUID) async
```

#### ChatViewModel.swift
```swift
/// Handle read receipt from realtime
private func handleReadReceipt(_ receipt: ReadReceipt)
```

### Integration Points

1. **Subscription Setup** (ChatViewModel.subscribeToRealtimeUpdates):
   - Added read receipts subscription alongside messages and typing indicators
   - Passes received receipts to `handleReadReceipt()`

2. **Receipt Handler** (ChatViewModel.handleReadReceipt):
   - Finds the message by `receipt.messageId`
   - Initializes `readReceipts` array if needed
   - Adds new receipt or updates existing one for same user

3. **Cleanup** (ChatViewModel.deinit):
   - Unsubscribes from read receipts when leaving conversation
   - Prevents memory leaks and duplicate subscriptions

## User Flow

### Before Fix:
1. User A sends message to User B
2. User B reads the message
3. Database updates: new row in `read_receipts` table
4. User A's UI: **Still shows "delivered" (one checkmark)**
5. User A closes and reopens conversation
6. UI now shows "read" (two checkmarks)

### After Fix:
1. User A sends message to User B
2. User B reads the message  
3. Database updates: new row in `read_receipts` table
4. **Realtime event fires to User A's device**
5. **User A's UI immediately updates to "read" (two checkmarks)**

## Receipt Status Icons

The UI shows different icons based on read status:

- **Clock** ⏱️: Message sending (optimistic UI)
- **One Checkmark** ✓: Delivered to server
- **Two Checkmarks** ✓✓: Read by recipient(s)
- **Blue Checkmarks** (in groups): Read by some users (shows count)

## Files Modified

### WhatsNext Package
1. `Sources/WhatsNextFeature/Services/RealtimeService.swift`
   - Added: `subscribeToReadReceipts()` method
   - Added: `unsubscribeFromReadReceipts()` method

2. `Sources/WhatsNextFeature/ViewModels/ChatViewModel.swift`
   - Modified: `subscribeToRealtimeUpdates()` - added read receipts subscription
   - Modified: `deinit` - added read receipts cleanup
   - Added: `handleReadReceipt()` method

### MessageAI (Same Changes)
1. `Services/RealtimeService.swift`
2. `ViewModels/ChatViewModel.swift`

## Database Considerations

- Uses the existing `read_receipts` table structure
- No schema changes required
- Leverages the upsert fix from earlier (migration `20251022000008_read_receipts_update_policy.sql`)
- Supabase Realtime listens for both INSERT and UPDATE events

## Testing Instructions

### Test Scenario 1: 1-on-1 Conversation
1. Open app on Device A (user alice@example.com)
2. Open app on Device B (user bob@example.com)
3. Device A: Send a message to Bob
4. Observe: Message shows one checkmark (delivered)
5. Device B: Open conversation with Alice
6. Device A: **Should immediately see two checkmarks (read)**

### Test Scenario 2: Group Conversation
1. Create a group with 3+ users
2. Device A: Send a message
3. Device B: Open the group and view message
4. Device A: Should see "Read by 1" indicator
5. Device C: Open the group and view message
6. Device A: Should update to "Read by 2"

### Test Scenario 3: Multiple Messages
1. Device A: Send 5 messages in a row
2. All show delivered status
3. Device B: Open conversation (marks all as read)
4. Device A: **All 5 messages should update to read status**

## Performance Notes

- Each conversation gets its own read receipts channel: `read_receipts:{conversationId}`
- Channel is properly cleaned up when leaving conversation
- Only listens to receipts for messages in the current conversation
- Minimal overhead: only updates when receipts actually change

## Related Fixes

This fix complements:
1. **Read receipts upsert** (earlier today): Prevents duplicate key violations
2. **Chat preview updates**: Conversation list now updates with new messages
3. **In-app notifications**: Banners appear for messages from other conversations

## Next Steps

- ✅ Read receipts update in real-time
- ✅ Conversation previews update in real-time
- ✅ In-app banners and notifications working
- ✅ Database errors resolved (pg_net, read_receipts upsert)

All core realtime features are now fully functional! 🎉

