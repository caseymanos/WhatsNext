# WhatsNext Setup Guide

This guide walks you through setting up WhatsNext for development and production deployment.

## Prerequisites

### Required Accounts & Services
- **Apple Developer Account** (for iOS development and APNs)
- **Supabase Account** (for backend database and edge functions)
- **Node.js** (for Supabase CLI, optional for development)

### Required Tools
- **Xcode 15+** (for iOS development)
- **Supabase CLI** (`npm install -g supabase`)
- **iOS Device** (for push notification testing, simulator doesn't support APNs)

## 1. Environment Configuration

### 1.1 Create Environment Variables

Create a `.env` file in the project root:

```bash
# Supabase Configuration
IOS_SUPABASE_URL=https://your-project-id.supabase.co
IOS_SUPABASE_ANON_KEY=your-anon-key

# APNs Configuration (for push notifications)
APNS_TEAM_ID=your-apple-team-id
APNS_KEY_ID=your-apns-key-id
APNS_BUNDLE_ID=com.gauntletai.whatsnext

# Development Settings
ENVIRONMENT=development
```

### 1.2 Update Build Configurations

Update `ios/MessageAI/Resources/Debug.xcconfig`:

```xcconfig
// Update these values
DEVELOPMENT_TEAM=your-apple-team-id
PRODUCT_BUNDLE_IDENTIFIER=com.gauntletai.whatsnext.dev

// Make sure these are set
SUPABASE_URL=$(IOS_SUPABASE_URL)
SUPABASE_ANON_KEY=$(IOS_SUPABASE_ANON_KEY)
```

Update `ios/MessageAI/Resources/Release.xcconfig`:

```xcconfig
// Update these values
DEVELOPMENT_TEAM=your-apple-team-id
PRODUCT_BUNDLE_IDENTIFIER=com.gauntletai.whatsnext

// Make sure these are set
SUPABASE_URL=$(IOS_SUPABASE_URL)
SUPABASE_ANON_KEY=$(IOS_SUPABASE_ANON_KEY)
```

## 2. Supabase Setup

### 2.1 Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Choose your organization and project name (e.g., "whatsnext-prod")
3. Select your preferred region
4. Wait for project initialization (2-3 minutes)

### 2.2 Apply Database Migrations

Run all migrations in order:

```bash
# Initialize Supabase in your project (if not done)
supabase init

# Link to your remote project
supabase link --project-ref your-project-id

# Apply migrations
supabase db push

# Verify migrations applied
supabase db diff --linked
```

The migrations will create:
- `users` table with push_token column
- `conversations`, `conversation_participants`, `messages` tables
- `typing_indicators`, `read_receipts` tables
- RLS policies for all tables
- Database triggers for conversation updates

### 2.3 Configure Edge Function

Deploy the push notification function:

```bash
cd supabase/functions
supabase functions deploy send-notification
```

### 2.4 Set Environment Variables in Supabase

In your Supabase dashboard:

1. Go to **Settings** → **Edge Functions**
2. Add these environment variables:

```bash
APNS_TEAM_ID=your-apple-team-id
APNS_KEY_ID=your-apns-key-id
APNS_KEY=-----BEGIN PRIVATE KEY-----\nYour private key content\n-----END PRIVATE KEY-----
APNS_BUNDLE_ID=com.gauntletai.whatsnext
APNS_ENVIRONMENT=development  # or production
```

3. Go to **Settings** → **Database**
4. Add these database-level settings:

```sql
-- Set edge function URL for push trigger
ALTER DATABASE postgres SET app.edge_function_url = 'https://your-project-id.supabase.co/functions/v1/send-notification';

-- Set service role key (for edge function auth)
ALTER DATABASE postgres SET app.service_role_key = 'your-service-role-key';
```

### 2.5 Enable Required Extensions

In Supabase SQL Editor, run:

```sql
-- Enable HTTP extension for push triggers
CREATE EXTENSION IF NOT EXISTS http;

-- Enable pg_net for async HTTP calls (recommended for production)
CREATE EXTENSION IF NOT EXISTS pg_net;
```

## 3. APNs Setup (Push Notifications)

### 3.1 Create APNs Key

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles** → **Keys**
3. Create a new key:
   - Name: "WhatsNext Push"
   - Enable: Apple Push Notifications service (APNs)
4. Download the `.p8` key file
5. Note your **Key ID** and **Team ID**

### 3.2 Configure Bundle ID

1. In Apple Developer Portal, register your bundle ID:
   - Bundle ID: `com.gauntletai.whatsnext`
   - Capabilities: Push Notifications
2. For development: `com.gauntletai.whatsnext.dev`

### 3.3 Convert APNs Key

Convert the `.p8` key to PEM format for the edge function:

```bash
# The key content should be in PEM format for the edge function
# Your APNS_KEY environment variable should contain:
-----BEGIN PRIVATE KEY-----
[Your key content]
-----END PRIVATE KEY-----
```

## 4. iOS App Configuration

### 4.1 App Icons

Add app icons to complete the setup:

1. Create a 1024x1024px app icon (square, PNG format)
2. Use an icon generator service (e.g., [appicon.co](https://appicon.co)) to create all required sizes
3. Place the generated icons in:
   ```
   ios/MessageAI/Resources/Assets.xcassets/AppIcon.appiconset/
   ```
4. Ensure all filenames match exactly (see `APP_ICON_README.md`)

### 4.2 Code Signing Setup

#### Development
1. In Xcode, select your target
2. Go to **Signing & Capabilities**
3. Enable **Automatically manage signing**
4. Select your development team
5. Set bundle identifier to `com.gauntletai.whatsnext.dev`

#### Production/Release
1. Create an App ID in Apple Developer Portal
2. Create development/distribution certificates
3. Create provisioning profiles
4. In Xcode, manually set:
   - Code signing identity
   - Provisioning profile
   - Bundle identifier: `com.gauntletai.whatsnext`

### 4.3 Build Configuration

In Xcode:
1. Select your target
2. Go to **Build Settings**
3. Ensure `Debug.xcconfig` and `Release.xcconfig` are properly referenced
4. Verify environment variables are loaded

## 5. Testing Checklist

### 5.1 Development Testing

```bash
# Build and run in simulator
# 1. Authentication flows
# 2. 1:1 messaging
# 3. Group creation and management
# 4. Real-time updates
# 5. Offline functionality
```

### 5.2 Device Testing (Required for Push)

1. **Push Notifications**:
   - Test on real device (simulator doesn't support APNs)
   - Verify permission request appears
   - Check token registration in Supabase dashboard
   - Send test push via edge function

2. **Real-time Features**:
   - Test typing indicators
   - Test read receipts
   - Test message delivery across devices

3. **Group Features**:
   - Create group with multiple users
   - Test participant management
   - Verify sender attribution in groups

### 5.3 Database Verification

Check Supabase dashboard:
- All tables created with correct structure
- RLS policies active
- Triggers functioning
- Edge function deployed and accessible

## 6. Production Deployment

### 6.1 Environment Variables Update

Update your production `.env`:

```bash
ENVIRONMENT=production
APNS_ENVIRONMENT=production
# Update URLs to production Supabase project
```

### 6.2 App Store Preparation

1. **App Information**:
   - App name: "WhatsNext"
   - Bundle ID: `com.gauntletai.whatsnext`
   - Version: 1.0.0
   - Build: 1

2. **Screenshots & Metadata**:
   - Prepare screenshots for all device sizes
   - Write app description
   - Set keywords and categories

3. **Certificates & Profiles**:
   - Create App Store distribution certificate
   - Create App Store provisioning profile
   - Update Xcode signing for App Store

### 6.3 Final Testing

- [ ] Test on multiple real devices
- [ ] Test with production Supabase backend
- [ ] Verify all push notifications work
- [ ] Test app performance with large conversations
- [ ] Verify offline functionality
- [ ] Test error handling and edge cases

## 7. Troubleshooting

### Common Issues

**Push Notifications Not Working**:
- Verify APNs certificates are correctly uploaded
- Check bundle ID matches exactly
- Ensure device token is being saved to database
- Test edge function independently

**Authentication Issues**:
- Verify Supabase URL and keys are correct
- Check RLS policies allow access
- Ensure user profile exists after signup

**Real-time Not Working**:
- Check Supabase realtime is enabled
- Verify subscription channels match
- Check network connectivity

**Build Issues**:
- Clean build folder in Xcode
- Verify certificates are valid
- Check provisioning profiles

### Debug Commands

```bash
# Check Supabase connection
supabase status

# View logs
supabase functions logs send-notification

# Test edge function locally
supabase functions serve send-notification --env-file .env

# Check database
supabase db diff --linked
```

## 8. Next Steps After Setup

1. **Beta Testing**: Submit to TestFlight and gather feedback
2. **Analytics**: Add analytics tracking (optional)
3. **Monitoring**: Set up error monitoring (optional)
4. **Phase 2**: Begin AI integration (see `docs/AI-Implementation-Spec.md`)
5. **App Store**: Submit for App Store review

## 9. Support Resources

- **Supabase Documentation**: [supabase.com/docs](https://supabase.com/docs)
- **Apple Push Notifications**: [developer.apple.com/documentation/usernotifications](https://developer.apple.com/documentation/usernotifications)
- **iOS Development**: [developer.apple.com/tutorials/app-dev-training](https://developer.apple.com/tutorials/app-dev-training)
- **SwiftUI**: [developer.apple.com/tutorials/swiftui](https://developer.apple.com/tutorials/swiftui)

---

**Need Help?** Check the troubleshooting section or refer to the implementation documentation in `/docs`.

🚀 **Ready to deploy!** Once setup is complete, your WhatsNext app will be fully functional with authentication, real-time messaging, groups, and push notifications.

