# Real-time Messaging Testing Guide

## Prerequisites

- Two iOS simulators running (iPhone 16 Pro and iPhone 16 already booted)
- WhatsNext app installed on both simulators
- Two test user accounts in Supabase

## Test Setup

### Simulator 1: iPhone 16 Pro (Device A)
- UUID: `C27A8895-154B-45A1-BD7C-EA5326537107`
- User: alice@example.com (or your test user 1)

### Simulator 2: iPhone 16 (Device B)  
- UUID: `ED3A1ED8-A8FA-4E8F-94B3-56129E98FC11`
- User: bob@example.com (or your test user 2)

## Test Scenarios

### Test 1: Real-time Message Delivery

**Goal**: Verify messages appear instantly on other device

**Steps**:
1. Launch app on both simulators
2. Log in as different users on each device
3. Device A: Navigate to conversation with Device B's user
4. Device B: Navigate to the same conversation
5. Device A: Type and send "Test message 1"
6. **Expected Result**: Device B immediately shows "Test message 1" without any refresh

**Look for in Console**:
```
[RealtimeService] Subscribing to messages for conversation: {uuid}
[RealtimeService] Successfully subscribed to messages channel
[RealtimeService] Received message insert: {messageId} for conversation: {conversationId}
[GRM] Broadcasting message -> conv={conversationId} id={messageId}
```

**Success Criteria**:
- ✅ Message appears within 1 second
- ✅ No manual refresh needed
- ✅ Message appears in correct position in chat

### Test 2: Conversation Preview Updates

**Goal**: Verify conversation list updates when messages arrive

**Steps**:
1. Device A: Navigate to conversation list (home screen)
2. Device B: Open a conversation and send a message
3. **Expected Result**: Device A's conversation list immediately:
   - Shows the new message preview
   - Moves that conversation to the top
   - Updates timestamp

**Look for in Console**:
```
[RealtimeService] Subscribing to all messages for user: {userId}
[RealtimeService] Successfully subscribed to global messages
[RealtimeService] Received global message: {messageId} for conversation: {conversationId}
[GRM] Broadcasting message -> conv={conversationId}
```

**Success Criteria**:
- ✅ Preview updates instantly
- ✅ Conversation moves to top of list
- ✅ Timestamp updates
- ✅ No need to pull-to-refresh

### Test 3: Read Receipts

**Goal**: Verify read status updates in real-time

**Steps**:
1. Device A: Send a message to Device B
2. Verify message shows one checkmark (delivered)
3. Device B: Open the conversation (marks as read automatically)
4. **Expected Result**: Device A's message checkmark changes to two checkmarks (read)

**Look for in Console**:
```
[RealtimeService] Subscribing to read receipts for conversation: {conversationId}
[RealtimeService] Successfully subscribed to read receipts
[RealtimeService] Received read receipt (insert): message {messageId}
```

**Success Criteria**:
- ✅ One checkmark when sent (delivered)
- ✅ Changes to two checkmarks within 1 second of reading
- ✅ No refresh needed

### Test 4: Typing Indicators

**Goal**: Verify typing indicators work in real-time

**Steps**:
1. Device A: Open conversation with Device B
2. Device B: Start typing (don't send)
3. **Expected Result**: Device A shows "User B is typing..." indicator
4. Device B: Stop typing
5. **Expected Result**: Indicator disappears after 5 seconds

**Look for in Console**:
```
[RealtimeService] Subscribing to typing indicators for conversation: {conversationId}
[RealtimeService] Received typing indicator (update): user {userId}
```

**Success Criteria**:
- ✅ Typing indicator appears instantly
- ✅ Indicator shows correct user name
- ✅ Indicator disappears after timeout

### Test 5: Multiple Conversations

**Goal**: Verify updates only affect relevant conversations

**Steps**:
1. Device A: Open conversation with User C
2. Device B: Send message in conversation with User C
3. **Expected Result**: Device A sees the message in that conversation only
4. Device A: Check other conversations
5. **Expected Result**: No updates in unrelated conversations

**Look for in Console**:
```
[GRM] Client-side filter: Verify message belongs to user's conversations
[GRM] Broadcasting message -> conv={correctConversationId}
```

**Success Criteria**:
- ✅ Updates only appear in correct conversation
- ✅ No phantom updates in other chats
- ✅ Conversation list correctly reorders

### Test 6: Background/Foreground Transitions

**Goal**: Verify real-time works after app backgrounding

**Steps**:
1. Device A: Open a conversation
2. Device A: Press home button (background app)
3. Device B: Send a message
4. **Expected Result**: Device A receives notification
5. Device A: Open app again
6. **Expected Result**: Message is already visible, no loading

**Look for in Console**:
```
[GRM] Skipping notification - conversation {conversationId} is currently open
[GlobalRealtimeManager] Starting GlobalRealtimeManager for user: {userId}
[RealtimeService] Successfully subscribed to global messages
```

**Success Criteria**:
- ✅ Notification appears when backgrounded
- ✅ Message visible when returning to app
- ✅ Real-time subscriptions reconnect automatically

## Debugging Failed Tests

### No Messages Appearing

**Check**:
1. Supabase realtime logs: `supabase logs realtime`
2. Verify publication configuration:
   ```sql
   SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';
   ```
3. Check RLS policies are not blocking reads
4. Verify channel subscription in console logs

### Messages Delayed

**Check**:
1. Network latency in simulator
2. Check for errors in console logs
3. Verify GlobalRealtimeManager is active: `[GRM] Broadcasting message`

### Preview Not Updating

**Check**:
1. ConversationListViewModel is subscribed: `[RealtimeService] Subscribing to all messages`
2. User has proper conversation membership
3. Check for client-side filtering logs: `[GRM] Filtered out message`

### Read Receipts Not Working

**Check**:
1. Read receipt subscription active: `[RealtimeService] Subscribing to read receipts`
2. Receipt insert actually happening in database
3. ChatViewModel receiving events: `[RealtimeService] Received read receipt`

## Console Log Analysis

### Successful Real-time Flow

```
# On app launch
[GlobalRealtimeManager] Starting GlobalRealtimeManager for user: {userId}
[RealtimeService] Subscribing to all messages for user: {userId}
[RealtimeService] Successfully subscribed to global messages
[RealtimeService] Subscribing to conversation updates for user: {userId}
[RealtimeService] Successfully subscribed to conversation updates

# When entering a conversation
[RealtimeService] Subscribing to messages for conversation: {conversationId}
[RealtimeService] Successfully subscribed to messages channel
[RealtimeService] Subscribing to read receipts for conversation: {conversationId}
[RealtimeService] Successfully subscribed to read receipts
[RealtimeService] Subscribing to typing indicators for conversation: {conversationId}

# When message is sent from another device
[RealtimeService] Received message insert: {messageId} for conversation: {conversationId}
[GRM] Broadcasting message -> conv={conversationId} id={messageId}

# When message is read
[RealtimeService] Received read receipt (insert): message {messageId}
```

## Performance Verification

Monitor console for:
- **Subscription time**: Should be < 100ms
- **Event delivery**: Should be < 500ms from send to receive
- **UI update**: Should be immediate after event received
- **Memory**: No leaks from subscriptions

## Cleanup After Testing

1. Stop both simulators
2. Review Supabase logs for any errors
3. Check database for any orphaned subscriptions
4. Verify no memory leaks in Instruments

## Success Criteria Summary

All tests should pass with:
- ✅ Messages delivered instantly (< 1 second)
- ✅ Previews update automatically
- ✅ Read receipts work in real-time
- ✅ Typing indicators function properly
- ✅ No phantom updates in wrong conversations
- ✅ App works after backgrounding/foregrounding
- ✅ Console logs show proper subscription lifecycle
- ✅ No errors in Supabase realtime logs

## Next Steps After Testing

1. If all tests pass: Mark implementation complete ✅
2. If tests fail: Review specific failure scenario above
3. Monitor production for real-world performance
4. Consider adding metrics/analytics for real-time events

