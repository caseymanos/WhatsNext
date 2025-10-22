# Push Notifications Setup

## ✅ RLS Issue - RESOLVED
Conversations are now creating successfully! The issue was missing RLS migrations which have been applied.

## 🔔 Push Notifications - Setup Required

### Current Status
- ✅ App installed on device with `aps-environment` entitlement
- ✅ Push notification code implemented (`PushNotificationService`)
- ⚠️ Push notifications won't work until APNs is configured

### Why Notifications Don't Work Yet

**Push notifications require:**
1. ✅ APNs entitlement (just added)
2. ❌ **APNs authentication key** from Apple Developer
3. ❌ **Supabase Edge Function** configured with APNs credentials
4. ✅ Database trigger to send notifications (already set up)

### Quick Test (Without Full APNs Setup)

The app will **ask for notification permission** but notifications won't actually be delivered until you configure APNs with Apple.

**On your device:**
1. Open the app
2. Sign in
3. You should see a permission dialog: "WhatsNext Dev would like to send you notifications"
4. Tap "Allow"
5. The app will register for notifications (but delivery won't work yet)

### Full Push Notification Setup (For Production)

#### Step 1: Get APNs Key from Apple Developer

1. Go to https://developer.apple.com/account/resources/authkeys/list
2. Click "+" to create a new key
3. Give it a name: "WhatsNext APNs Key"
4. Check "Apple Push Notifications service (APNs)"
5. Click "Continue" → "Register"
6. **Download the `.p8` file** (you can only download once!)
7. Note the **Key ID** (e.g., `ABC123DEF4`)
8. Note your **Team ID** (e.g., `G79V58PSGA`)

#### Step 2: Configure Supabase Edge Function

Update the edge function with your APNs credentials:

```bash
# Set Supabase secrets
supabase secrets set APNS_KEY_ID=ABC123DEF4
supabase secrets set APNS_TEAM_ID=G79V58PSGA
supabase secrets set APNS_KEY="-----BEGIN PRIVATE KEY-----
<paste full content of .p8 file>
-----END PRIVATE KEY-----"

supabase secrets set APNS_BUNDLE_ID=com.gauntletai.whatsnext
supabase secrets set APNS_ENVIRONMENT=development  # or 'production'
```

#### Step 3: Verify Edge Function

The edge function at `supabase/functions/send-notification/index.ts` is already implemented with full APNs support. Just needs the environment variables above.

#### Step 4: Test End-to-End

1. **On Device A**: Sign in and create a conversation with another user
2. **On Device B**: Sign in as the other user
3. **On Device A**: Send a message
4. **On Device B**: You should receive a push notification (even if app is closed)

### Simulator Limitations

❌ **Push notifications DO NOT work in simulators**
- Error: `no valid "aps-environment" entitlement string found`
- This is expected iOS behavior
- Must test on physical devices

### Troubleshooting

#### "Failed to register for remote notifications"
**On Simulator**: This is normal - simulators don't support push
**On Device**: Check that:
- `aps-environment` is in entitlements (✅ now added)
- App is signed with a provisioning profile that includes push
- Device has network connectivity

#### "Notifications not being delivered"
Check:
1. Did the app successfully register? Check device token in `users.push_token`
2. Is the edge function configured with APNs credentials?
3. Is the database trigger firing? Check Supabase logs
4. Is the device token valid for the environment (dev vs prod)?

#### "Permission dialog not appearing"
- Go to Settings → WhatsNext Dev → Notifications
- Make sure "Allow Notifications" is ON
- If OFF, the user denied it - they must manually enable in Settings

### Current Implementation

**Client (iOS)**:
- `PushNotificationService` handles registration and token management
- Automatically registers on sign-in
- Saves token to `users.push_token` in database
- Removes token on sign-out

**Server (Supabase)**:
- Database trigger on `messages` table
- Calls edge function `send-notification`
- Sends to all conversation participants except sender
- Includes message preview and sender info

**Edge Function**:
- Full APNs HTTP/2 implementation
- JWT-based authentication
- Supports both sandbox and production
- Proper error handling

### What Works Now

✅ Conversations create successfully (RLS fixed!)
✅ Messages send and receive in real-time
✅ Auth session persistence
✅ App installed on device with push entitlement
✅ Permission dialog will appear (but delivery requires APNs setup)

### What Requires Apple Developer Account

❌ APNs authentication key (.p8 file)
❌ Configuring Supabase secrets with APNs credentials
❌ Actual push notification delivery

### Next Steps

1. **For testing conversations**: You're all set! ✅
2. **For testing push notifications**: 
   - Get APNs key from Apple Developer
   - Configure Supabase secrets
   - Test on physical device

### Files Modified

- `/ios/WhatsNext/Config/WhatsNext.entitlements` - Added `aps-environment`
- App rebuilt and installed on device

### Quick Reference

```swift
// Check if notifications are enabled
let center = UNUserNotificationCenter.current()
let settings = await center.notificationSettings()
print("Authorization status: \(settings.authorizationStatus.rawValue)")
// 0 = notDetermined, 1 = denied, 2 = authorized

// Check device token
let user = try await SupabaseClientService.shared.database
    .from("users")
    .select("push_token")
    .eq("id", value: userId)
    .single()
    .execute()
    .value
print("Device token: \(user.pushToken ?? "nil")")
```

### Production Checklist

Before App Store release:
- [ ] Get APNs production key
- [ ] Update entitlements to `<string>production</string>`
- [ ] Configure Supabase with production APNs credentials
- [ ] Test on TestFlight
- [ ] Update `APNS_ENVIRONMENT=production`
- [ ] Test with production APNs endpoint

