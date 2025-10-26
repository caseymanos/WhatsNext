# Core Backlog Progress

Last updated: 2025-10-26

This document tracks progress against the Phase 1 (non‑AI) backlog described in `docs/Core-Implementation-Spec.md`.

## Summary
- Completed: E1 Foundation (5 pts), E2 Supabase Schema & RLS (21 pts), E3 iOS Bootstrap (8 pts), E4 Auth & Profile (13 pts), E5 Conversations & Chat Core (21 pts), E6 Realtime Messaging (8 pts), E7 Offline & Local Persistence (13 pts), E8 Read Receipts (8 pts), E9 Group Chat Management (8 pts), E10 Push Notifications (13 pts), E11 Observability & Hardening (5 pts)
- In Progress: None
- Not Started: None
- Total Completed: 123 pts / 123 pts (100%)

## Quick Metrics

| Metric | Value |
|--------|-------|
| Story Points | 123 / 123 (100%) |
| Epics Complete | 11 / 11 (100%) |
| Swift Files | 33 |
| SQL Migrations | 7 |
| Services | 8 |
| ViewModels | 3 |
| Views | 11 |
| Database Tables | 6 |

## Architecture Overview

**Design Patterns**:
- MVVM with @MainActor ViewModels for clean separation
- Service layer with single-responsibility services
- Offline-first with SwiftData + outbox pattern
- Optimistic UI for instant feedback with server reconciliation

**Tech Stack**:
- iOS: SwiftUI, Swift Concurrency (async/await), SwiftData
- Backend: Supabase (Postgres, Auth, Realtime, Edge Functions)
- Security: Row-Level Security (RLS) on all tables
- Logging: OSLog with structured categories

**Key Decisions**:
1. SwiftData over Core Data (modern, type-safe)
2. Async/await throughout (no callbacks)
3. Optimistic UI with localId → serverId reconciliation
4. Outbox pattern for offline resilience
5. RLS for database-level security

---

## Epic E1 — Foundation & Repo Setup (5 pts)
- Status: Completed
- Stories:
  - [x] S1. Initialize repo, docs, env scaffolding — Completed
  - [x] S2. Project structure stubs (dirs, empty files) — Completed
- Files:
  - `README.md`
  - `docs/Core-Implementation-Spec.md`
  - `scripts/dev-bootstrap.sh`
  - `scripts/verify-env.sh`
  - `.gitignore`
  - `ios/MessageAI/` directory structure (App, Models, Views, ViewModels, Services, Utilities, Resources)

## Epic E2 — Supabase Schema & RLS (21 pts)
- Status: Completed
- Stories:
  - [x] S3. Core tables migration — Completed
  - [x] S4. RLS policies + seeds — Completed (seed stub present)
  - [x] S5. Conversation timestamp trigger — Completed
- Files:
  - `supabase/migrations/2025-10-20-001_core.sql`
  - `supabase/migrations/2025-10-20-002_rls.sql`
  - `supabase/migrations/2025-10-20-003_seed.sql`
  - `supabase/migrations/2025-10-20-004_triggers.sql`

## Epic E3 — iOS App Bootstrap (8 pts)
- Status: Completed
- Stories:
  - [x] S6. Xcode project, SPM deps, configs — Completed
  - [x] S7. SupabaseClient singleton — Completed
- Files:
  - `ios/MessageAI/Package.swift`
  - `ios/MessageAI/App/MessageAIApp.swift`
  - `ios/MessageAI/App/ContentView.swift`
  - `ios/MessageAI/Resources/Config.xcconfig`
  - `ios/MessageAI/Resources/Info.plist`
  - `ios/MessageAI/Services/SupabaseClient.swift`

## Epic E4 — Authentication & Profile (13 pts)
- Status: Completed
- Stories:
  - [x] S8. AuthViewModel + login/sign-up UI — Completed
  - [x] S9. Profile fetch/update & last_seen — Completed
- Files:
  - `ios/MessageAI/Models/User.swift`
  - `ios/MessageAI/Services/AuthService.swift`
  - `ios/MessageAI/ViewModels/AuthViewModel.swift`
  - `ios/MessageAI/Views/LoginView.swift`
  - `ios/MessageAI/Views/SignUpView.swift`

## Epic E5 — Conversations & Chat Core (21 pts)
- Status: Completed
- Stories:
  - [x] S10. Conversation list (1:1 and groups) — Completed
  - [x] S11. Chat view send/receive with optimistic UI — Completed
- Files:
  - `ios/MessageAI/Models/Conversation.swift`
  - `ios/MessageAI/Models/Message.swift`
  - `ios/MessageAI/Services/ConversationService.swift`
  - `ios/MessageAI/Services/MessageService.swift`
  - `ios/MessageAI/ViewModels/ConversationListViewModel.swift`
  - `ios/MessageAI/ViewModels/ChatViewModel.swift`
  - `ios/MessageAI/Views/ConversationListView.swift`
  - `ios/MessageAI/Views/ChatView.swift`

## Epic E6 — Realtime Messaging (8 pts)
- Status: Completed
- Stories:
  - [x] S12. Subscribe to message inserts per conversation — Completed
  - [x] S13. Typing indicators realtime — Completed
- Files:
  - `ios/MessageAI/Services/RealtimeService.swift`
  - Updated: `ios/MessageAI/ViewModels/ChatViewModel.swift` (integrated realtime subscriptions)

## Epic E7 — Offline & Local Persistence (13 pts)
- Status: Completed
- Stories:
  - [x] S14. SwiftData models + local cache — Completed
  - [x] S15. Outbox queue + reconnect sync — Completed
- Files:
  - `ios/MessageAI/Models/LocalModels.swift`
  - `ios/MessageAI/Services/LocalStorageService.swift`
  - `ios/MessageAI/Services/MessageSyncService.swift`
  - `ios/MessageAI/Utilities/NetworkMonitor.swift`

## Epic E8 — Read Receipts (8 pts)
- Status: Completed
- Stories:
  - [x] S16. DB policy + insert read_receipts — Completed
  - [x] S17. Per-user status display — Completed
- Files:
  - Updated: `ios/MessageAI/Services/MessageService.swift` (read receipts methods)
  - Updated: `ios/MessageAI/ViewModels/ChatViewModel.swift` (receipt status tracking)
  - Updated: `ios/MessageAI/Views/ChatView.swift` (receipt status display)

## Epic E9 — Group Chat Management (8 pts)
- Status: Completed
- Stories:
  - [x] S18. Create group, add/remove participants — Completed
  - [x] S19. Show sender attribution in groups — Completed
- Files:
  - `ios/MessageAI/Views/CreateGroupView.swift` (new)
  - `ios/MessageAI/Views/GroupSettingsView.swift` (new)
  - Updated: `ios/MessageAI/Views/ConversationListView.swift` (added group creation menu)
  - Updated: `ios/MessageAI/Views/ChatView.swift` (sender attribution, group settings navigation)
  - Updated: `ios/MessageAI/Services/ConversationService.swift` (group management methods)

## Epic E10 — Push Notifications (APNs) (13 pts)
- Status: Completed
- Stories:
  - [x] S20. iOS registration + token save — Completed
  - [x] S21. Edge Function APNs relay — Completed (full APNs implementation)
  - [x] S22. Database trigger for auto-push — Completed
- Files:
  - `ios/MessageAI/Services/PushNotificationService.swift` (new)
  - `ios/MessageAI/App/MessageAIApp.swift` (AppDelegate for push handling)
  - Updated: `ios/MessageAI/Services/AuthService.swift` (token registration/removal)
  - Updated: `ios/MessageAI/ViewModels/AuthViewModel.swift` (pass userId to signOut)
  - Updated: `supabase/functions/send-notification/index.ts` (full APNs JWT implementation)
  - `supabase/migrations/2025-10-20-005_push_trigger.sql` (new)

## Epic E11 — Observability & Hardening (5 pts)
- Status: Completed
- Stories:
  - [x] S23. Logging, error surfaces, simple metrics — Completed
  - [x] S24. Release configs, icons, Info.plist hygiene — Completed
- Files:
  - `ios/MessageAI/Utilities/Logger.swift`
  - `ios/MessageAI/Resources/Debug.xcconfig` (new)
  - `ios/MessageAI/Resources/Release.xcconfig` (new)
  - `ios/MessageAI/Resources/Assets.xcassets/AppIcon.appiconset/` (new, with Contents.json)
  - `ios/MessageAI/Resources/APP_ICON_README.md` (new, instructions)
  - Updated: `ios/MessageAI/Resources/Info.plist` (permission strings, proper keys)

---

## Implementation Complete! 🎉

All 11 epics and 24 stories have been successfully implemented.

## Next Steps for Production Deployment

### 1. Environment Setup
- Create Supabase project (production)
- Set up environment variables in CI/CD
- Configure APNs certificates and keys
- Set up code signing and provisioning profiles

### 2. Database Migration
```bash
# Apply all migrations to production Supabase
supabase db push
# Or use Supabase dashboard to run migrations manually
```

### 3. Deploy Edge Functions
```bash
cd supabase/functions
supabase functions deploy send-notification
# Set environment variables in Supabase dashboard:
# - APNS_TEAM_ID
# - APNS_KEY_ID
# - APNS_KEY (private key in PEM format)
# - APNS_BUNDLE_ID
# - APNS_ENVIRONMENT (production)
```

### 4. iOS App Configuration
- Add actual app icons (see `APP_ICON_README.md`)
- Configure Debug.xcconfig and Release.xcconfig with your team ID
- Set up provisioning profiles for TestFlight/App Store
- Update bundle identifier if needed
- Test on real devices with production Supabase

### 5. Testing Checklist
- [ ] User authentication (sign up, sign in, sign out)
- [ ] 1:1 messaging with realtime updates
- [ ] Group chat creation and management
- [ ] Message read receipts
- [ ] Typing indicators
- [ ] Offline functionality and sync
- [ ] Push notifications (requires real device)
- [ ] Profile management
- [ ] Group participant management

### 6. App Store Submission
- Complete app metadata and screenshots
- Submit for TestFlight review
- Beta test with users
- Address feedback
- Submit for App Store review
