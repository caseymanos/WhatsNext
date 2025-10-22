# RLS Conversation Creation - Debugging Guide

## Current Status

✅ **Database RLS Policies**: Correctly configured and verified
✅ **iOS Client Code**: Updated to proper insert flow
✅ **App Build**: Successfully built and installed on device
🔍 **Debug Logging**: Added to ConversationService

## What We Fixed

### 1. Database (Supabase)
- Applied migrations `20251021000006_rls_fix.sql` and `20251021000007_conversations_policies.sql`
- Active policy: `conv_insert_authenticated` with `WITH CHECK (auth.uid() IS NOT NULL)`
- Verified with query - policy is active

### 2. iOS Client
- Updated `ConversationService.swift` to:
  - Remove `.select()` on INSERT (avoids immediate read before membership)
  - Insert creator first, then other participants
  - Added debug logging to track auth session and insert attempts
- Both files updated:
  - `/ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/ConversationService.swift` (active)
  - `/ios/MessageAI/Services/ConversationService.swift` (legacy)

## Current Issue

You're **signed in on the device** but still getting:
```
new row violates row-level security policy for table "conversations"
```

This means `auth.uid()` is returning `NULL` despite being "signed in" in the UI.

## Root Cause Possibilities

### 1. **Session Token Not Being Sent** (Most Likely)
The Supabase client might not be automatically attaching the JWT token to database requests.

**Check**: Does the Supabase Swift SDK automatically include auth headers?
- The SDK should automatically attach `Authorization: Bearer <jwt>` to all requests
- This happens via the shared `SupabaseClient` instance

### 2. **Session Expired**
The JWT token might have expired and needs refresh.

**Check**: Token lifetime in Supabase Auth settings (default is 1 hour)

### 3. **Different Client Instances**
If `AuthService` and `ConversationService` use different Supabase client instances, the auth state won't be shared.

**Status**: ✅ Both use `SupabaseClientService.shared` (verified)

### 4. **Auth State Not Persisted**
The session might not be saved/loaded between app launches.

**Check**: Does Supabase Swift SDK persist sessions by default?

## Next Steps - Run These Tests

### Test 1: Check Console Logs
The app now has debug logging. When you try to create a conversation, check the Xcode console for:

```
✅ ConversationService: Auth session valid - user_id=<UUID>
🔄 Attempting to insert conversation: <UUID>
```

If you see:
```
❌ ConversationService: No valid auth session - <error>
```

Then the session is not valid on the client side.

### Test 2: Verify Auth Session in ConversationListView

Add this to `ConversationListView.swift` before creating a conversation:

```swift
Button("New Conversation") {
    Task {
        // Debug check
        do {
            let session = try await SupabaseClientService.shared.auth.session
            print("✅ Auth session active: \(session.user.id)")
        } catch {
            print("❌ No auth session: \(error)")
        }
        
        // Then try creating conversation
        // ...
    }
}
```

### Test 3: Manual Session Check

Run this in the app after signing in:

```swift
// In ContentView or ConversationListView
.task {
    do {
        let session = try await SupabaseClientService.shared.auth.session
        print("Session User ID: \(session.user.id)")
        print("Session Access Token: \(session.accessToken.prefix(20))...")
        print("Token Expires: \(session.expiresAt)")
    } catch {
        print("No session: \(error)")
    }
}
```

## Likely Solutions

### Solution A: Session Persistence Issue

The Supabase Swift SDK should auto-persist sessions, but verify it's configured:

```swift
// In SupabaseClient.swift, add storage configuration
SupabaseClient(
    supabaseURL: url,
    supabaseKey: supabaseAnonKey,
    options: SupabaseClientOptions(
        db: .init(schema: "public"),
        auth: .init(
            redirectToURL: URL(string: "com.gauntletai.whatsnext://login-callback"),
            autoRefreshToken: true,
            storage: DefaultLocalStorage()  // ← Add this if missing
        ),
        global: .init(headers: ["X-Client-Info": "whatsnext-ios/1.0.0"])
    )
)
```

### Solution B: Force Session Refresh

Before creating a conversation, force refresh the session:

```swift
func createDirectConversation(...) async throws -> Conversation {
    // Force session refresh
    _ = try await supabase.auth.session
    
    // Then proceed with insert
    // ...
}
```

### Solution C: Check Supabase SDK Version

Ensure you're using a recent version of `supabase-swift`:

```swift
// In Package.swift
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
```

## How to View Logs

### Option 1: Xcode Console
1. Keep USB connected
2. Open Xcode → Window → Devices and Simulators
3. Select your device
4. Click "Open Console"
5. Filter by process: "WhatsNext"

### Option 2: Terminal
```bash
# Stream device logs
log stream --predicate 'processImagePath contains "WhatsNext"' --level debug

# Or using devicectl
xcrun devicectl device info logs --device 4C03B95C-671D-53F2-9455-E392ED8E4455
```

### Option 3: Device Console App (macOS)
1. Open "Console" app
2. Select your iPhone from sidebar
3. Filter for "WhatsNext"
4. Try creating a conversation
5. Look for our debug prints

## Expected Debug Output

### ✅ Success Case:
```
✅ ConversationService: Auth session valid - user_id=123e4567-...
🔄 Attempting to insert conversation: 789abcde-...
✅ Conversation inserted successfully
```

### ❌ Failure Case (No Session):
```
❌ ConversationService: No valid auth session - Session expired
Must be signed in to create conversations. Please sign in and try again.
```

### ❌ Failure Case (RLS):
```
✅ ConversationService: Auth session valid - user_id=123e4567-...
🔄 Attempting to insert conversation: 789abcde-...
❌ Failed to insert conversation: new row violates row-level security policy
```

If you see the third case (session valid but RLS fails), then we have a deeper issue with how the SDK sends tokens.

## Quick Test Script

Run this on device after signing in:

```swift
// Add to ConversationListView or ContentView
Button("Test Auth") {
    Task {
        do {
            // 1. Check session
            let session = try await SupabaseClientService.shared.auth.session
            print("✅ Session: \(session.user.id)")
            
            // 2. Try a simple select (should work)
            let users: [User] = try await SupabaseClientService.shared.database
                .from("users")
                .select()
                .limit(1)
                .execute()
                .value
            print("✅ Select works: \(users.count) users")
            
            // 3. Try conversation insert
            let testConv = Conversation(
                id: UUID(),
                name: nil,
                avatarUrl: nil,
                isGroup: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            try await SupabaseClientService.shared.database
                .from("conversations")
                .insert(testConv)
                .execute()
            print("✅ Insert works!")
            
        } catch {
            print("❌ Test failed: \(error)")
        }
    }
}
```

## Files Modified (This Session)

1. `/ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/ConversationService.swift`
   - Added auth session verification
   - Added debug logging
   - Removed `.select()` on INSERT

2. `/ios/MessageAI/Services/ConversationService.swift`
   - Same changes (legacy file)

3. `/docs/CHANGELOG.md`
   - Documented RLS fix

4. `RLS_FIX_INSTRUCTIONS.md` (new)
   - Initial troubleshooting guide

5. `RLS_DEBUG_NEXT_STEPS.md` (this file)
   - Detailed debugging steps

## App Installed

- Device: iPhone 17,2 (Casey's phones)
- Bundle ID: `com.gauntletai.whatsnext`
- Location: `/private/var/containers/Bundle/Application/D82FF68F-0BC8-4A64-B2C4-197D424429F0/`
- Build: Debug configuration with logging

## What to Do Now

1. **Launch the app** on your device
2. **Sign in** with your test account
3. **Try creating a conversation**
4. **Check console logs** in Xcode or Console.app for the debug output
5. **Report back** what you see:
   - Does it show "✅ Auth session valid"?
   - Does it show "❌ No valid auth session"?
   - Does it show "✅ Conversation inserted successfully"?
   - Or does it still show RLS error after valid session?

The debug output will tell us exactly where the problem is:
- **No session** → Need to fix auth persistence
- **Session valid but RLS fails** → Need to investigate SDK token attachment
- **Everything works** → Problem solved! 🎉

## Contact Points

If the issue persists after checking logs:
1. Share the exact console output from attempting to create a conversation
2. Share the output of the "Test Auth" button if you add it
3. Check if other authenticated operations work (e.g., updating profile, fetching users)

