# WhatsNext (MessageAI)

A modern iOS messaging application with AI capabilities, built with SwiftUI and Supabase.

## Overview

WhatsNext is a feature-rich messaging app that combines traditional chat functionality with AI-powered features. The app is being developed in phases:

- **Phase 1 (Core)**: Core messaging features 
  - ✅ Authentication & Profile Management
  - ✅ 1:1 and Group Conversations
  - ✅ Real-time Messaging with Typing Indicators
  - ✅ Offline Support & Message Sync
  - ✅ Read Receipts


- **Phase 2 (AI)**: AI integration (message enhancement, smart replies, conversation summaries)

## Features Implemented

### Authentication & Profile (E4) ✅
- Email/password sign up and sign in
- User profile management
- Last seen tracking
- Session persistence

### Conversations & Chat (E5) ✅
- Create 1:1 and group conversations
- Conversation list with last message preview
- Real-time message sending and receiving
- Optimistic UI updates
- Message history pagination

### Real-time Features (E6) ✅
- WebSocket-based message delivery
- Typing indicators
- Automatic message synchronization
- Sub-200ms latency

### Offline Support (E7) ✅
- SwiftData local persistence
- Offline message queueing (outbox)
- Automatic sync on reconnection
- Network status monitoring

### Read Receipts (E8) ✅
- Message read status tracking
- Visual indicators (delivered/read)
- Group chat read counts
- Real-time receipt updates

### Observability (E11) 🚧
- Structured logging with OSLog
- Error tracking and reporting
- Network monitoring

## Project Structure

```
WhatsNext/
├── docs/                    # Documentation
│   ├── Core-Implementation-Spec.md
│   ├── AI-Implementation-Spec.md
│   ├── Core-Backlog-Progress.md
│   ├── PROJECT-SUMMARY.md
│   └── CHANGELOG.md
├── ios/MessageAI/          # iOS application
│   ├── App/                # App entry point
│   ├── Models/             # Data models
│   ├── Views/              # SwiftUI views
│   ├── ViewModels/         # View models
│   ├── Services/           # Business logic services
│   ├── Utilities/          # Helper utilities
│   └── Resources/          # Assets, configs
├── supabase/               # Backend (Postgres, Edge Functions)
│   ├── migrations/         # Database migrations
│   └── functions/          # Edge Functions
└── scripts/                # Development scripts
```

## Tech Stack

- **Frontend**: iOS 17+, SwiftUI, Swift Concurrency, SwiftData
- **Backend**: Supabase (Postgres, Auth, Realtime, Storage)
- **Local Storage**: SwiftData for offline-first architecture
- **Real-time**: Supabase Realtime (WebSocket subscriptions)
- **Networking**: Async/await with URLSession
- **Logging**: OSLog for structured logging

## Architecture

### Data Flow
1. **Send Message**: iOS → Optimistic UI → Supabase → Trigger updates `conversations.updated_at` → Realtime notifies other clients
2. **Receive Message**: Realtime subscription → ChatViewModel → SwiftUI update
3. **Offline**: Message → SwiftData outbox → Network reconnect → Auto-sync → Remote DB
4. **Read Receipts**: View message → Insert `read_receipts` → Real-time update sender

### Security
- Row-Level Security (RLS) on all tables
- JWT-based authentication
- User can only access their own conversations
- Messages filtered by participant membership

## Getting Started

### Prerequisites

- Xcode 15+
- iOS 17+ device or simulator
- Supabase account and project
- Swift 5.9+

### Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd WhatsNext
   ```

2. Run the setup script:
   ```bash
   ./scripts/dev-bootstrap.sh
   ```

3. Set up Supabase:
   - Create a new Supabase project
   - Run migrations: `supabase db push`
   - Copy your project URL and anon key

4. Configure environment (create `.env.local` from `.env.example`):
   ```
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   ```

5. Open the iOS project in Xcode:
   ```bash
   open ios/MessageAI/Package.swift
   ```

6. Update `Info.plist` with your Supabase credentials

7. Build and run on simulator or device

## Documentation

- [Core Implementation Spec](docs/Core-Implementation-Spec.md) - Phase 1 technical specification
- [AI Implementation Spec](docs/AI-Implementation-Spec.md) - Phase 2 AI features
- [Core Backlog Progress](docs/Core-Backlog-Progress.md) - Development progress tracker
- [Project Summary](docs/PROJECT-SUMMARY.md) - Technical achievements and lessons learned
- [Development Changelog](docs/CHANGELOG.md) - Session-by-session history

## Development Status

**Current**: Phase 1 - Core Features (81% complete)
- 100 out of 123 story points completed
- 8 out of 11 epics fully implemented
- Ready for group management UI and push notifications

**Next**: Complete Phase 1 (E9, E10, E11 remaining)

**Future**: Phase 2 - AI Integration

## License

[Your License Here]

## Contributing

[Contributing Guidelines]
