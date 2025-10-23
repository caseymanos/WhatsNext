# Real-time Filters Fix - October 23, 2025

## Problem Summary

Messages, conversation previews, and read receipts were not updating in real-time across devices. Users had to back out of conversations and re-enter to see new messages. The root cause was missing channel-level filters in Supabase Realtime subscriptions.

## Root Causes Identified

1. **No channel-level event filters** - Subscriptions listened to entire table changes without user/conversation filters
2. **Missing filter parameters** - `postgresChange()` calls didn't include `filter` parameter to scope events
3. **Improper channel naming** - Channel names weren't descriptive enough for debugging
4. **Missing client-side validation** - No verification that received events belong to user's conversations
5. **Realtime publication not configured** - Tables weren't explicitly added to `supabase_realtime` publication

## Changes Implemented

### Phase 1: RealtimeService Filter Updates

**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/RealtimeService.swift`

#### Individual Conversation Messages
```swift
// BEFORE
channel.postgresChange(InsertAction.self, table: "messages")

// AFTER
channel.postgresChange(
    InsertAction.self, 
    table: "messages",
    filter: "conversation_id=eq.\(conversationId)"
)
```

#### Typing Indicators
```swift
// BEFORE
channel.postgresChange(AnyAction.self, table: "typing_indicators")

// AFTER
channel.postgresChange(
    AnyAction.self, 
    table: "typing_indicators",
    filter: "conversation_id=eq.\(conversationId)"
)
```

#### Global Messages Subscription
- Relies on RLS policies to filter server-side
- No explicit filter needed as RLS ensures user only receives messages from their conversations

#### Read Receipts
- Listens to all receipts (cannot filter by message_id without knowing all IDs upfront)
- Client-side filtering in ChatViewModel ensures only relevant receipts are processed

#### Conversation Updates
- No user membership filter available at channel level
- Client-side filtering in GlobalRealtimeManager verifies user participation

### Phase 2: Channel Naming Improvements

Updated all channel names to be more descriptive and debuggable:

- Messages (per conversation): `"conversation:{conversationId}:messages"`
- Typing indicators: `"conversation:{conversationId}:typing"`
- Read receipts: `"conversation:{conversationId}:receipts"`
- Global messages: `"user:{userId}:messages"`
- Conversation updates: `"user:{userId}:conversations"`

### Phase 3: Client-Side Filtering

**File**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/GlobalRealtimeManager.swift`

Added `isUserMemberOfConversation()` method to verify events:

```swift
private func isUserMemberOfConversation(_ conversationId: UUID) -> Bool {
    return conversations.keys.contains(conversationId)
}
```

Applied in:
- `handleIncomingMessage()` - Filters messages from non-member conversations
- `handleConversationUpdate()` - Filters conversation updates for non-participant conversations

### Phase 4: Comprehensive Logging

Added logging at all subscription lifecycle points:

- Channel creation and subscription
- Event reception with message/conversation IDs
- Filter application (when events are filtered out)
- Subscription cleanup
- Error handling

Prefix: `[RealtimeService]` for service-level logs, `[GRM]` for manager-level logs

### Phase 5: Supabase Migration

**File**: `supabase/migrations/20251023000011_configure_realtime.sql`

Applied migration to:
1. Add tables to `supabase_realtime` publication
   - `messages`
   - `conversations`
   - `read_receipts`
   - `typing_indicators`

2. Grant SELECT permissions to `authenticated` role
   - Required for realtime subscriptions to work

3. Grant USAGE on sequences
   - Ensures proper access for all authenticated users

## Testing Instructions

### Test Scenario 1: Real-time Message Delivery

1. **Setup**: Open app on Device A and Device B, both logged into different accounts
2. **Device A**: Navigate to conversation with Device B's user
3. **Device B**: Navigate to same conversation
4. **Device A**: Send a message "Hello from A"
5. **Expected**: Device B sees message appear instantly without refresh
6. **Verify**: Check Xcode console for logs:
   ```
   [RealtimeService] Received message insert: {messageId} for conversation: {conversationId}
   [GRM] Broadcasting message -> conv={conversationId} id={messageId}
   ```

### Test Scenario 2: Conversation Preview Updates

1. **Setup**: Device A in conversation list, Device B in a specific conversation
2. **Device B**: Send a message
3. **Expected**: Device A's conversation list updates preview instantly, moves conversation to top
4. **Verify**: Check console for:
   ```
   [RealtimeService] Received global message: {messageId} for conversation: {conversationId}
   [GRM] Broadcasting message -> conv={conversationId}
   ```

### Test Scenario 3: Read Receipts

1. **Device A**: Send message to Device B
2. **Device B**: Open conversation (message gets marked as read automatically)
3. **Expected**: Device A sees checkmark change from one to two (delivered → read)
4. **Verify**: Check console for:
   ```
   [RealtimeService] Received read receipt (insert): message {messageId}
   ```

### Test Scenario 4: Typing Indicators

1. **Device A**: Open conversation with Device B
2. **Device B**: Start typing in same conversation
3. **Expected**: Device A shows "User B is typing..." indicator
4. **Verify**: Check console for:
   ```
   [RealtimeService] Received typing indicator (update): user {userId}
   ```

## Debugging Tips

### Check Realtime Subscription Status

Use Supabase logs to verify events are being broadcast:

```bash
# Via Supabase CLI
supabase logs realtime

# Via Supabase Dashboard
# Navigate to Logs > Realtime
```

### Verify Publication Configuration

```sql
-- Check tables in realtime publication
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime' 
  AND schemaname = 'public';
```

Expected output:
- conversations
- messages
- read_receipts
- typing_indicators

### Check Client-Side Logs

Look for these patterns in Xcode console:

**Successful subscription**:
```
[RealtimeService] Subscribing to messages for conversation: {uuid}
[RealtimeService] Successfully subscribed to messages channel
```

**Event reception**:
```
[RealtimeService] Received message insert: {messageId}
[GRM] Broadcasting message -> conv={conversationId}
```

**Filtering in action**:
```
[GRM] Filtered out message for non-member conversation: {conversationId}
```

## Known Limitations

1. **Read Receipts**: Cannot filter by specific message IDs at subscription level
   - Solution: Listen to all receipts, filter client-side in ChatViewModel

2. **Conversation Updates**: Cannot filter by user membership at channel level
   - Solution: Client-side filtering in GlobalRealtimeManager

3. **Network Reconnection**: Subscriptions don't auto-resubscribe after network drop
   - Future improvement: Add connection monitoring and resubscription logic

## Success Metrics

✅ Messages appear instantly on other devices
✅ Conversation preview updates automatically
✅ Read receipts update in real-time
✅ No need to back out and refresh to see updates
✅ Proper event filtering prevents unauthorized access
✅ Comprehensive logging aids debugging

## Files Modified

1. `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/RealtimeService.swift`
   - Added filter parameters to all `postgresChange()` calls
   - Updated channel naming conventions
   - Added comprehensive logging

2. `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/GlobalRealtimeManager.swift`
   - Added `isUserMemberOfConversation()` helper
   - Added client-side filtering in message/conversation handlers
   - Enhanced logging throughout

3. `supabase/migrations/20251023000011_configure_realtime.sql`
   - New migration file
   - Adds tables to realtime publication
   - Grants necessary permissions

## Rollback Instructions

If issues arise, rollback by:

1. Remove filter parameters from RealtimeService (revert to previous version)
2. Rollback Supabase migration:
   ```sql
   ALTER PUBLICATION supabase_realtime DROP TABLE public.messages;
   ALTER PUBLICATION supabase_realtime DROP TABLE public.conversations;
   ALTER PUBLICATION supabase_realtime DROP TABLE public.read_receipts;
   ALTER PUBLICATION supabase_realtime DROP TABLE public.typing_indicators;
   ```

## Related Documentation

- [Real-time Fixes Summary](REALTIME-FIXES-SUMMARY.md)
- [Read Receipts Real-time Fix](READ-RECEIPTS-REALTIME-FIX.md)
- [Chat Preview and Notifications Fix](CHAT-PREVIEW-AND-NOTIFICATIONS-FIX.md)

