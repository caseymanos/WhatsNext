# How to Monitor Simulator Logs for Real-time Debugging

## Quick Start - Console.app (Easiest)

1. **Open Console.app**:
   ```bash
   open -a Console
   ```

2. **Select your simulator** in left sidebar:
   - Look for "iPhone 16 Pro" or "iPhone 16" under Simulators

3. **Filter for your app**:
   - Click the search field (top right)
   - Type: `process:WhatsNext Dev`

4. **Search for realtime logs**:
   - Type in search: `[RealtimeService]` or `[GRM]` or `GlobalRealtimeManager`

## Terminal Option (Live Stream) - RECOMMENDED FOR DEBUGGING

### Monitor Simulator 1 (iPhone 16 Pro)

```bash
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'process == "WhatsNext Dev"' \
  --level debug \
  --style compact | grep -E "\[RealtimeService\]|\[GRM\]|\[WhatsNextApp\]|\[ConversationListVM\]|Error|Failed"
```

### Monitor Simulator 2 (iPhone 16)

```bash
xcrun simctl spawn ED3A1ED8-A8FA-4E8F-94B3-56129E98FC11 log stream \
  --predicate 'process == "WhatsNext Dev"' \
  --level debug \
  --style compact | grep -E "\[RealtimeService\]|\[GRM\]|\[WhatsNextApp\]|\[ConversationListVM\]|Error|Failed"
```

### Monitor BOTH Simulators Together

```bash
# Run this in two terminal windows side-by-side
# Terminal 1 - Simulator 1:
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'process == "WhatsNext Dev"' --level debug --style compact \
  2>&1 | grep --line-buffered -E "\[RealtimeService\]|\[GRM\]|\[WhatsNextApp\]" | \
  sed 's/^/[SIM1] /'

# Terminal 2 - Simulator 2:
xcrun simctl spawn ED3A1ED8-A8FA-4E8F-94B3-56129E98FC11 log stream \
  --predicate 'process == "WhatsNext Dev"' --level debug --style compact \
  2>&1 | grep --line-buffered -E "\[RealtimeService\]|\[GRM\]|\[WhatsNextApp\]" | \
  sed 's/^/[SIM2] /'
```

## What to Look For

### On App Launch / Login

You should see:
```
[WhatsNextApp] User logged in, starting GlobalRealtimeManager
[WhatsNextApp] Fetched 2 conversations
[GRM] Starting GlobalRealtimeManager for user: ABC-123
[GRM] Conversations count: 2
[RealtimeService] Subscribing to all messages for user: ABC-123
[RealtimeService] Global messages channel status: subscribed
[RealtimeService] Successfully initiated global messages subscription
[GRM] ✅ Messages subscription successful
[RealtimeService] Subscribing to conversation updates for user: ABC-123
[RealtimeService] Conversation channel status: subscribed
[GRM] ✅ Conversation updates subscription successful
[GRM] GlobalRealtimeManager started successfully
[WhatsNextApp] ✅ GlobalRealtimeManager started successfully
```

### When Entering a Conversation

```
[RealtimeService] Subscribing to messages for conversation: XYZ-789
[RealtimeService] Message channel status: subscribed
[RealtimeService] Successfully initiated messages subscription
[RealtimeService] Subscribing to read receipts for conversation: XYZ-789
[RealtimeService] Read receipts channel status: subscribed
[RealtimeService] Subscribing to typing indicators for conversation: XYZ-789
[RealtimeService] Typing channel status: subscribed
```

### When Receiving a Message (CRITICAL)

```
[RealtimeService] Received message insert: MSG-456 for conversation: XYZ-789
[GRM] Broadcasting message -> conv=XYZ-789 id=MSG-456
```

### When Message is Read

```
[RealtimeService] Received read receipt (insert): message MSG-456
```

### When Someone is Typing

```
[RealtimeService] Received typing indicator (update): user USER-789
```

## Troubleshooting

### If You See NOTHING

**Problem**: No `[RealtimeService]` or `[GRM]` logs appear at all

**Possible Causes**:
1. App isn't logging to the system log (check if using `print()` vs `NSLog()` or `os_log`)
2. User not authenticated
3. Subscription failures happening silently

**Solution**: Check for these logs instead:
```bash
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'process == "WhatsNext Dev"' \
  --level debug | grep -i "user\|login\|auth\|conversation"
```

### If Subscriptions Fail

Look for these error patterns:
```
[GRM] ❌ Messages subscription failed: ...
[RealtimeService] Error in message subscription: ...
```

### If Channel Status Shows "unsubscribed"

```
[RealtimeService] Message channel status: unsubscribed
```

This means the subscription attempt failed. Check:
1. Network connectivity
2. Supabase project is running
3. Auth token is valid

## Quick Test Command

Before testing real-time, verify logs are working:

```bash
# This should show SOME output from your app
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'process == "WhatsNext Dev"' \
  --level debug \
  --style compact | head -20
```

If you see output, then logs are working and you can monitor for real-time events.

## Alternative: Xcode Debug Console

If running from Xcode:
1. Open Xcode
2. Run your app: `Cmd + R`
3. Open debug console: `Cmd + Shift + Y`
4. Type in filter field: `[RealtimeService]` or `[GRM]`

## Save Logs to File

```bash
# Save first 1000 lines of logs to file
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'process == "WhatsNext Dev"' --level debug --style compact \
  2>&1 | grep -E "\[RealtimeService\]|\[GRM\]" | head -1000 > ~/Desktop/realtime-logs.txt
```

## Expected Log Flow

1. App launches
2. User logs in
3. `handleAuthenticationChange()` called
4. GlobalRealtimeManager starts
5. Subscriptions created
6. Channel statuses become "subscribed"
7. Events start flowing when messages sent

Watch for the **channel status: subscribed** logs - that's the key indicator that real-time is working!

