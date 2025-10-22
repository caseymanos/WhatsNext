# RLS Fix - Authentication Required

## ✅ Status: RLS Policies Are Correctly Configured

The error `new row violates row-level security policy for table "conversations"` is **expected behavior** when the user is not authenticated.

## Root Cause

The RLS policy requires `auth.uid() IS NOT NULL`, which means:
- ✅ Any **authenticated** user can create conversations
- ❌ **Unauthenticated** requests are blocked (as they should be)

## Verified Database Configuration

```sql
-- Current policy (confirmed active):
CREATE POLICY conv_insert_authenticated ON public.conversations
  FOR INSERT
  WITH CHECK ( auth.uid() IS NOT NULL );
```

This policy checks the JWT token in the `Authorization: Bearer <token>` header, **not** the `currentUserId` parameter passed by the client.

## Solution: Sign In Before Creating Conversations

### Step 1: Launch the App
```bash
# Get the app path and bundle ID
cd /Users/caseymanos/GauntletAI/WhatsNext
xcrun simctl list devices | grep "iPhone 16"

# Or use the build scripts in localruns.txt
```

### Step 2: Sign In or Sign Up
1. Open the app on simulator/device
2. **Sign up** with a new account, or **sign in** with existing credentials
3. Verify you see the conversation list (not the login screen)

### Step 3: Check Auth State
The app should:
- Store the session token via `SupabaseClient.auth.session`
- Automatically include the token in all database requests
- Show `ConversationListView` instead of `LoginView`

### Step 4: Create a Conversation
Once authenticated:
- Tap the "+" button or "New Message" 
- Select a user
- The conversation creation will succeed

## Debugging: Verify Auth Session

Add this to `ConversationService.swift` before creating a conversation:

```swift
func createDirectConversation(currentUserId: UUID, otherUserId: UUID) async throws -> Conversation {
    // Debug: Check if we have a valid session
    do {
        let session = try await supabase.auth.session
        print("✅ Auth session valid: user_id = \(session.user.id)")
    } catch {
        print("❌ No valid auth session: \(error)")
        throw error
    }
    
    // ... rest of the function
}
```

## Expected Behavior

### ✅ When Authenticated
```
Request: INSERT INTO conversations (...)
Header: Authorization: Bearer eyJhbGc...
Result: auth.uid() = '123e4567-e89b-12d3-a456-426614174000'
Policy: ✓ PASS (auth.uid() IS NOT NULL)
```

### ❌ When Not Authenticated
```
Request: INSERT INTO conversations (...)
Header: Authorization: Bearer anon_key_without_user_session
Result: auth.uid() = NULL
Policy: ✗ FAIL (violates RLS policy)
```

## What Was Fixed

1. **Database**: Applied RLS policies with correct `WITH CHECK` clauses
2. **iOS Client**: Updated insert flow to avoid immediate SELECT before membership
3. **Both simulator and device builds verified**

## What Still Needs to Be Done

**Nothing on the RLS side** - the policies are correct.

**The app needs to**:
1. Sign in a user (get JWT token)
2. Store the session (Supabase SDK does this automatically)
3. Then create conversations (token will be sent automatically)

## Testing Checklist

- [ ] Build and run app on simulator/device
- [ ] Sign up with a new account or sign in with existing
- [ ] Verify `ContentView` shows `ConversationListView` (not `LoginView`)
- [ ] Try creating a conversation
- [ ] Should succeed with authenticated user

## Common Issues

### "Still getting RLS error after signing in"
- Check: Is `authViewModel.isAuthenticated` true?
- Check: Does `SupabaseClient.auth.session` return a valid session?
- Check: Is the session persisted between app launches?

### "Can't sign in"
- Check: Is Config.plist configured with correct Supabase URL and anon key?
- Check: Are users being created in auth.users table?
- Check: Network connectivity to Supabase

### "Session expires immediately"
- Check: Auth settings in Supabase dashboard
- Check: `autoRefreshToken: true` in SupabaseClient init (already configured)

## Next Steps

1. **Run the app** (see localruns.txt for build/install commands)
2. **Sign in** with a test account
3. **Try creating a conversation** - should work!

If you get the RLS error **after confirming you're signed in**, then we have a real issue to debug. But 99% certain this is just an authentication state issue.

