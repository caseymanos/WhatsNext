# CRITICAL BUG FOUND - Channel Subscribe Order

## The Bug

We're calling `channel.subscribe()` **BEFORE** setting up event listeners, causing this fault:

```
fault: You cannot call postgresChange after joining the channel, this won't work as expected.
```

## Current (BROKEN) Code Flow

```swift
let channel = await supabase.realtimeV2.channel("...")

// ❌ WRONG: Subscribe BEFORE setting up listeners
await channel.subscribe()

// ❌ This fails silently - channel already subscribed
let task = Task {
    for try await insertion in channel.postgresChange(...) {
        // This never executes!
    }
}
```

## Correct Code Flow

```swift
let channel = await supabase.realtimeV2.channel("...")

// ✅ Set up listener FIRST
let task = Task {
    for try await insertion in channel.postgresChange(...) {
        // Handle event
    }
}

// ✅ Subscribe AFTER listener is set up
await channel.subscribe()
```

## Fix Required

Move ALL `channel.subscribe()` calls to AFTER the Task that sets up `postgresChange()` listeners.

This affects **5 subscription methods** in `RealtimeService.swift`:
1. `subscribeToMessages`
2. `subscribeToTypingIndicators`
3. `subscribeToConversationUpdates`
4. `subscribeToAllMessages`
5. `subscribeToReadReceipts`

## Impact

**This is why real-time isn't working at all!** The listeners are never attached because the channel is already subscribed by the time we try to set them up.

Once fixed, all real-time updates should start working immediately.

