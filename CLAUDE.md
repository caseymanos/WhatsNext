# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WhatsNext is a modern iOS messaging application with AI-powered assistance, built with SwiftUI and Supabase. The app combines traditional chat functionality with intelligent AI capabilities for proactive assistance, conflict detection, deadline tracking, and smart organization.

## Development Commands

### Supabase Backend

```bash
# Bootstrap development environment
./scripts/dev-bootstrap.sh

# Push database migrations to Supabase
supabase db push

# Deploy edge functions
supabase functions deploy send-notification

# View edge function logs
supabase functions logs send-notification

# Check Supabase connection
supabase status
```

### iOS Development

```bash
# Open the iOS project in Xcode
cd ios/WhatsNext
open WhatsNext.xcworkspace

# Or use xed
xed ios/WhatsNext

# Build and run in simulator (⌘+R in Xcode)
# Note: Push notifications require a real device, not simulator
```

### Environment Configuration

Required environment variables in `.env`:
- `IOS_SUPABASE_URL` - Your Supabase project URL
- `IOS_SUPABASE_ANON_KEY` - Your Supabase anonymous key

Additional AI configuration:
- `OPENAI_API_KEY` - OpenAI API key for AI features

These are loaded into Xcode via `ios/WhatsNext/Resources/Config.xcconfig` and injected into `Info.plist`.

## Architecture

### iOS App Structure

The iOS app follows **MVVM architecture** with clean separation of concerns:

- **Services Layer**: Single-responsibility services handle all backend interactions
  - `SupabaseClientService` - Singleton providing Supabase client access
  - `AuthService` - User authentication and session management
  - `ConversationService` - Conversation CRUD operations
  - `MessageService` - Message CRUD and querying
  - `RealtimeService` - WebSocket subscriptions for live updates
  - `LocalStorageService` - SwiftData persistence layer
  - `MessageSyncService` - Offline message queue and sync
  - `PushNotificationService` - APNs token registration
  - `CalendarSyncEngine` - EventKit integration for calendar syncing
  - `AIService` - AI-powered feature coordination (SupabaseAIService/MockAIService)

- **ViewModels**: `@MainActor` view models manage UI state and coordinate services
  - `AuthViewModel` - Authentication flow state
  - `ConversationListViewModel` - Conversation list with realtime updates
  - `ChatViewModel` - Chat screen with messages, typing indicators, optimistic UI
  - `AIViewModel` - AI features coordinator and state management

- **Models**: Clean data models separate from UI
  - `User`, `Conversation`, `Message` - Codable structs matching Supabase schema
  - `LocalModels.swift` - SwiftData models for offline persistence
  - AI models: `Deadline`, `Conflict`, `RSVP`, `Decision`, `ProactiveAssistant`

### Data Flow Patterns

**Send Message Flow** (Optimistic UI):
1. User sends message → Immediate UI update with optimistic message (local ID)
2. Service sends to Supabase API
3. On success: Replace optimistic message with server response (real ID)
4. On failure: Mark message as failed, queue in outbox for retry

**Receive Message Flow** (Real-time):
1. Supabase Realtime subscription receives new message insert
2. RealtimeService callback fires with decoded Message
3. ChatViewModel updates `@Published` messages array
4. SwiftUI view automatically re-renders

**Offline Support Flow**:
1. Failed messages stored in SwiftData outbox
2. NetworkMonitor detects connectivity changes
3. MessageSyncService automatically retries queued messages
4. Successful sends remove from outbox

**Read Receipts Flow**:
1. ChatView appears → Marks conversation as read
2. Inserts/updates `read_receipts` table in Supabase
3. Realtime updates notify sender
4. Sender's ConversationListView shows "Read" status

### Backend Structure

**Database** (PostgreSQL via Supabase):
- Core tables: `users`, `conversations`, `conversation_participants`, `messages`, `typing_indicators`, `read_receipts`
- Calendar tables: `calendar_events`, `sync_queue`
- AI tables: `ai_deadlines`, `ai_conflicts`, `ai_rsvps`, `ai_decisions`, `ai_priority_messages`, `ai_proactive_assistant`
- Row-Level Security (RLS) policies enforce access control on all tables
- Triggers auto-update `conversations.updated_at` on new messages
- Push notification trigger calls edge function on message insert
- AI processing triggers for automatic message and event analysis

**Edge Functions** (Deno):
- `send-notification` - APNs HTTP/2 relay with JWT authentication
- `proactive-assistant` - AI-powered proactive assistance
- `detect-conflicts-agent` - Scheduling conflict detection
- `parse-message-ai` - Message content analysis
- Triggered by database events and real-time processing
- Supports both sandbox and production environments

## Key Implementation Details

### Real-time Subscriptions

The app uses Supabase Realtime (WebSocket) for live updates. Subscriptions are scoped per conversation and automatically cleaned up on view dismissal.

Example from `ChatViewModel`:
```swift
try await realtimeService.subscribeToMessages(conversationId: conversation.id) { message in
    Task { @MainActor in
        self.handleIncomingMessage(message)
    }
}
```

**Important**: Always unsubscribe in `deinit` to prevent memory leaks.

### Authentication & Session Management

- JWT-based authentication via Supabase Auth
- Sessions automatically persist and refresh via `SupabaseClientOptions`
- User profiles stored in `users` table with RLS policies
- Auth state managed by `AuthViewModel` with `@Published` currentUser

Configuration in `SupabaseClient.swift:18-33`:
```swift
SupabaseClientOptions(
    auth: SupabaseClientOptions.AuthOptions(
        autoRefreshToken: true,
        persistSession: true
    )
)
```

### Offline-First Architecture

Messages are persisted locally using SwiftData models in `LocalModels.swift`. Failed sends are queued in an "outbox" and automatically retried when connectivity is restored.

Key components:
- `LocalStorageService` - SwiftData CRUD operations
- `MessageSyncService` - Outbox queue management and retry logic
- `NetworkMonitor` - Network reachability tracking

### Group Chat Implementation

Group conversations support multiple participants with sender attribution:
- `conversation_participants` junction table tracks memberships
- Messages include `sender_id` for attribution in groups
- `CreateGroupView` provides user search and multi-select
- `GroupSettingsView` allows adding/removing participants

### Push Notifications (APNs)

Push notifications use APNs HTTP/2 protocol with JWT authentication:
1. iOS app registers device token via `PushNotificationService`
2. Token stored in `users.push_token` column
3. Database trigger calls `send-notification` edge function on new messages
4. Edge function constructs APNs payload and sends via HTTP/2

**Important**: Push requires real device testing. Simulator doesn't support APNs.

## Documentation

- **README.md** - Project overview, setup instructions, and architecture
- **CLAUDE.md** - Development guidance for Claude Code (this file)
- **docs/CHANGELOG.md** - Development history and session notes

Update the CHANGELOG when making significant changes. Do NOT create new documentation files unless specifically requested.

## Testing Guidelines

### Manual Testing Flow

1. **Authentication**: Sign up → Sign in → Session persistence across app restarts
2. **1:1 Messaging**: Send message → Verify realtime delivery on second device → Test offline queue
3. **Groups**: Create group → Add participants → Send messages → Verify sender attribution
4. **Read Receipts**: Open conversation → Verify "Read" status on sender's device
5. **Push Notifications**: Background app → Send message → Verify notification appears (device only)

### Known Limitations

- Push notifications require physical device (not simulator)
- APNs setup requires Apple Developer account and proper certificate configuration
- Realtime requires active internet connection (no offline message receiving)

## Common Development Tasks

### Adding a New Service

1. Create new file in `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/`
2. Follow single-responsibility principle - one service per backend feature
3. Use `SupabaseClientService.shared` for Supabase access
4. Add proper error handling with custom error enums
5. Mark async functions with `async throws` where appropriate

### Adding a New View

1. Create SwiftUI view in appropriate feature directory (e.g., `Conversations/`, `AI/Views/`)
2. If complex, create corresponding ViewModel in the feature's ViewModels directory
3. Mark ViewModels with `@MainActor` for thread safety
4. Use `@Published` properties for UI state
5. Inject dependencies via initializer (avoid global state where possible)

### Database Schema Changes

1. Create new migration in `supabase/migrations/` with timestamp prefix
2. Include RLS policies for security
3. Test locally with `supabase db reset`
4. Push to remote with `supabase db push`
5. Update Swift models to match schema

## Security Considerations

- **Row-Level Security**: All tables have RLS policies. Users can only access their own data or conversations they're participants in.
- **No API Keys in Code**: Supabase URL and keys are loaded from environment variables via xcconfig files.
- **JWT Authentication**: All API calls include JWT token from Supabase Auth.
- **Edge Function Auth**: Push trigger uses service role key stored in database config (not exposed to clients).

## Dependencies

- **supabase-swift** (2.0.0+) - Official Supabase client for Swift
- **iOS 17+** - Minimum deployment target
- **Swift 5.9+** - Uses modern async/await and SwiftData
- **Xcode 15+** - Required for Swift 5.9 and iOS 17 support
