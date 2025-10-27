# WhatsNext

A modern iOS messaging application with AI-powered assistance, built with SwiftUI and Supabase.

## Overview

WhatsNext is a feature-rich messaging app that combines traditional chat functionality with intelligent AI capabilities. The app provides seamless real-time communication with proactive AI assistance to help users manage their conversations, schedules, and important messages.

### Key Features

- **Real-time Messaging**: Instant 1:1 and group conversations with typing indicators
- **AI Assistant**: Proactive detection of conflicts, deadlines, RSVPs, and important decisions
- **Calendar Integration**: Automatic event detection and scheduling conflict alerts
- **Offline Support**: Full offline-first architecture with automatic sync
- **Read Receipts**: Track message delivery and read status in real-time
- **Push Notifications**: Stay updated with APNs-powered notifications
- **Smart Organization**: AI-powered message categorization and priority detection

### AI Capabilities

WhatsNext includes several AI-powered features:

- **Conflict Detection**: Automatically identifies scheduling conflicts across conversations
- **Deadline Tracking**: Extracts and monitors important deadlines from messages
- **RSVP Management**: Detects event invitations and tracks responses
- **Priority Messages**: Highlights time-sensitive and important communications
- **Decision Tracking**: Identifies decisions that need to be made
- **Proactive Assistance**: Contextual suggestions and reminders

## Tech Stack

### iOS App
- **Platform**: iOS 17+
- **UI Framework**: SwiftUI
- **Language**: Swift 5.9+
- **Local Storage**: SwiftData for offline-first persistence
- **Concurrency**: Swift async/await
- **Push Notifications**: Apple Push Notification service (APNs)

### Backend
- **Database**: PostgreSQL (via Supabase)
- **Authentication**: Supabase Auth with JWT
- **Real-time**: Supabase Realtime (WebSocket subscriptions)
- **Edge Functions**: Deno runtime
- **AI Integration**: OpenAI GPT models via Supabase Edge Functions

## Getting Started

### Prerequisites

- macOS 13+ with Xcode 15 or later
- iOS 17+ device or simulator
- Supabase account ([sign up here](https://supabase.com))
- Supabase CLI installed (`brew install supabase/tap/supabase`)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/WhatsNext.git
   cd WhatsNext
   ```

2. **Set up Supabase**

   Create a `.env` file in the root directory:
   ```bash
   # Supabase Configuration
   IOS_SUPABASE_URL=https://your-project.supabase.co
   IOS_SUPABASE_ANON_KEY=your-anon-key

   # OpenAI Configuration (for AI features)
   OPENAI_API_KEY=your-openai-api-key
   ```

3. **Initialize the database**

   Link to your Supabase project and push migrations:
   ```bash
   supabase link --project-ref your-project-ref
   supabase db push
   ```

4. **Deploy Edge Functions**

   Deploy the AI-powered backend functions:
   ```bash
   # Set up secrets
   supabase secrets set OPENAI_API_KEY=your-openai-api-key

   # Deploy functions
   supabase functions deploy proactive-assistant
   supabase functions deploy detect-conflicts-agent
   supabase functions deploy parse-message-ai
   ```

5. **Configure the iOS app**

   The app automatically loads configuration from `ios/WhatsNext/Resources/Config.xcconfig`, which reads from your `.env` file.

### Running in Simulator

1. **Open the project in Xcode**
   ```bash
   cd ios/WhatsNext
   open WhatsNext.xcworkspace
   ```

   Or using `xed`:
   ```bash
   xed ios/WhatsNext
   ```

2. **Select a simulator**
   - In Xcode, select a simulator from the scheme selector (e.g., "iPhone 16 Pro")
   - For best results, use iOS 17+ simulators

3. **Build and run**
   - Press `⌘ + R` or click the Play button in Xcode
   - The app will build and launch in the simulator

4. **Create an account**
   - On first launch, tap "Sign Up" to create a test account
   - Use any email/password for testing purposes

### Running on a Physical Device

For full functionality including push notifications:

1. **Configure signing**
   - In Xcode, select the WhatsNext target
   - Go to "Signing & Capabilities"
   - Select your development team
   - Ensure "Automatically manage signing" is checked

2. **Connect your device**
   - Connect your iPhone via USB or wirelessly
   - Select your device from the scheme selector

3. **Trust the developer certificate**
   - Run the app (`⌘ + R`)
   - On your device, go to Settings > General > VPN & Device Management
   - Trust your developer certificate

4. **Enable push notifications**
   - Grant notification permissions when prompted
   - Push notifications will only work on physical devices (not simulators)

## Architecture

### iOS App Structure

```
ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/
├── AI/                          # AI-powered features
│   ├── Services/                # AI service layer
│   ├── ViewModels/              # AI feature view models
│   └── Views/                   # AI UI components
├── App/                         # App entry point and root views
├── Auth/                        # Authentication flow
├── Calendar/                    # Calendar integration
├── Conversations/               # Chat and messaging
├── Models/                      # Data models
├── Services/                    # Core services
└── Utilities/                   # Helper utilities
```

### MVVM Architecture

The app follows the Model-View-ViewModel pattern:

- **Services**: Single-responsibility services handle backend interactions
  - `SupabaseClientService`: Singleton for Supabase client access
  - `AuthService`: User authentication and session management
  - `ConversationService`: Conversation CRUD operations
  - `MessageService`: Message handling and querying
  - `RealtimeService`: WebSocket subscriptions
  - `CalendarSyncEngine`: EventKit integration
  - `AIService`: AI-powered feature coordination

- **ViewModels**: `@MainActor` view models manage UI state
  - `AuthViewModel`: Authentication flow
  - `ConversationListViewModel`: Conversation list with real-time updates
  - `ChatViewModel`: Chat screen with messages and typing indicators
  - `AIViewModel`: AI features coordinator

- **Models**: Clean Codable data models matching the Supabase schema

### Data Flow

**Send Message**
1. User sends message → Optimistic UI update with temporary ID
2. Message sent to Supabase → Returns with real ID
3. Optimistic message replaced with server response
4. AI processing triggered for content analysis

**Receive Message**
1. Supabase Realtime receives new message
2. RealtimeService callback fires
3. ViewModel updates published state
4. SwiftUI view auto-renders

**AI Processing**
1. New message triggers edge function
2. AI analyzes content for deadlines, conflicts, RSVPs
3. Results stored in AI tables
4. Real-time updates notify iOS app
5. AI tab updates with new insights

## Database Schema

Key tables:

- `users`: User profiles and authentication
- `conversations`: Chat conversations and metadata
- `conversation_participants`: Many-to-many relationship for group chats
- `messages`: Chat messages with sender attribution
- `calendar_events`: Synced calendar events
- `ai_deadlines`: Extracted deadlines from messages
- `ai_rsvps`: Detected RSVP requests
- `ai_conflicts`: Scheduling conflicts
- `ai_decisions`: Pending decisions

All tables are protected by Row-Level Security (RLS) policies.

## Security

- **Row-Level Security**: All database tables enforce RLS policies
- **JWT Authentication**: Secure token-based auth via Supabase
- **End-to-End Privacy**: Users only access their own data
- **Secure Storage**: Credentials stored in iOS Keychain
- **Environment Variables**: No secrets committed to version control

## Development

### Project Commands

```bash
# Database migrations
supabase db push                              # Push migrations to remote
supabase db pull                              # Pull remote schema changes
supabase migration list                       # List all migrations

# Edge functions
supabase functions deploy <function-name>     # Deploy a function
supabase functions logs <function-name>       # View function logs

# Local development
supabase start                                # Start local Supabase
supabase stop                                 # Stop local Supabase
supabase status                               # Check service status
```

### Testing

- **Manual Testing**: Run in simulator or on device
- **Database Testing**: Use Supabase Studio (http://localhost:54323 for local)
- **Function Testing**: Test edge functions via Supabase Dashboard

### Adding New Features

1. **Database changes**: Create a new migration in `supabase/migrations/`
2. **Backend logic**: Add edge functions in `supabase/functions/`
3. **iOS models**: Update Swift models in `Models/`
4. **Service layer**: Add or update services in `Services/`
5. **UI layer**: Create SwiftUI views and view models

## Troubleshooting

### Common Issues

**Build errors in Xcode**
- Clean build folder: `⌘ + Shift + K`
- Reset package cache: File > Packages > Reset Package Caches
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/WhatsNext-*`

**Real-time not working**
- Check Supabase project status
- Verify RLS policies allow access
- Ensure proper WebSocket connection

**Push notifications not appearing**
- Push only works on physical devices
- Check notification permissions in Settings
- Verify APNs configuration in Supabase

**Calendar integration issues**
- Grant calendar permissions when prompted
- Check EventKit authorization status
- Ensure calendar sync is enabled in settings

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check existing documentation in the repository
- Review the CLAUDE.md file for development guidelines

## Acknowledgments

- Built with [Supabase](https://supabase.com)
- AI powered by [OpenAI](https://openai.com)
- iOS development with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
