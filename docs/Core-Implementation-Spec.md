# MessageAI Core Implementation Spec (Non‑AI)

This document is the authoritative spec for Phase 1 (core app without AI). It captures the scope, architecture, database, policies, iOS components, and the dependency‑ordered implementation plan we are following.

## 1) Scope
- In scope: Authentication, conversations, 1:1 and group chat, realtime messaging, typing indicators, read receipts, offline/local persistence (SwiftData), push notifications (APNs relay via Supabase Edge Function), logging/hardening.
- Out of scope: All AI features and any streaming UI (moved to `docs/AI-Implementation-Spec.md`).

## 2) Deliverables
- Working iOS app (SwiftUI) that signs in, lists conversations, sends/receives messages in realtime, persists locally for offline, shows read receipts, supports basic groups, and can receive basic push notifications.
- Supabase Postgres schema with RLS and triggers.
- Minimal Supabase Edge Function for push relay (placeholder behavior until APNs is wired).

## 3) Architecture
- Client: iOS 17+ SwiftUI, Swift Concurrency (async/await), SwiftData for local persistence.
- Backend: Supabase (Postgres, Auth, Realtime, Storage), Edge Functions (Deno) for push.
- Security: Postgres RLS policies enforce per‑user access; client authenticates via Supabase.

Data flow
- Send message: iOS inserts into `messages` → trigger updates `conversations.updated_at` → Realtime notifies other clients.
- Receive message: iOS subscribed to `INSERT` events on `messages` filtered by `conversation_id`.
- Typing: iOS upserts into `typing_indicators`; subscribers render ephemeral state.
- Read receipts: iOS inserts into `read_receipts`; server data used to render status.
- Offline: messages cached in SwiftData; outbox retries on reconnect.
- Push: server‑side function (later wired to APNs) invoked on events or by app logic.

## 4) Repository Layout (Core)
```
MessageAI/
├─ ios/MessageAI/
│  ├─ App/
│  ├─ Models/
│  ├─ Views/
│  ├─ ViewModels/
│  ├─ Services/
│  ├─ Utilities/
│  └─ Resources/
├─ supabase/
│  ├─ migrations/
│  │  ├─ 2025-10-20-001_core.sql
│  │  ├─ 2025-10-20-002_rls.sql
│  │  ├─ 2025-10-20-003_seed.sql
│  │  └─ 2025-10-20-004_triggers.sql
│  └─ functions/
│     └─ send-notification/
│        └─ index.ts
├─ scripts/
│  ├─ dev-bootstrap.sh
│  └─ verify-env.sh
├─ docs/
│  ├─ Core-Implementation-Spec.md   ← this document
│  └─ AI-Implementation-Spec.md     (Phase 2)
└─ README.md
```

## 5) Database Schema (Core)
Tables
- `users(id, email, username, display_name, avatar_url, created_at, last_seen, status, push_token)` (refs `auth.users(id)`)
- `conversations(id, name, avatar_url, is_group, created_at, updated_at)`
- `conversation_participants(conversation_id, user_id, joined_at, last_read_at)` (PK: conversation_id, user_id)
- `messages(id, conversation_id, sender_id, content, message_type, media_url, created_at, updated_at, deleted_at, local_id unique)`
- `typing_indicators(conversation_id, user_id, last_typed)` (PK: conversation_id, user_id)
- `read_receipts(message_id, user_id, read_at)` (PK: message_id, user_id)

Indexes
- `messages(conversation_id, created_at DESC)`, `messages(sender_id)`, `messages(local_id)`
- `conversation_participants(user_id)`, `conversation_participants(conversation_id)`
- `conversations(updated_at DESC)`, `users(push_token)`

Trigger
- `update_conversation_on_message` updates `conversations.updated_at` on message `INSERT`.

## 6) Row‑Level Security (RLS) Summary
Enabled on all core tables.
- Users: public `SELECT`; `UPDATE` allowed to self (`auth.uid() = id`).
- Conversations: `SELECT` allowed only if user is a participant; `INSERT` allowed for any authenticated user (creation).
- Participants: `SELECT` limited to user’s conversations; `INSERT` allowed by existing members of that conversation.
- Messages: `SELECT` limited to user’s conversations; `INSERT` allowed only if `sender_id = auth.uid()` and user is participant.
- Typing: `SELECT` limited to user’s conversations; `INSERT`/`UPDATE` allowed only for own `user_id`.
- Read receipts: `SELECT` limited to messages in user’s conversations; `INSERT` allowed only for own `user_id`.

## 7) Edge Functions (Core)
- `send-notification`: placeholder Deno function that validates input and returns a queued response. Later it will use a service role key to fetch `push_token` and call APNs.

## 8) iOS Components (planned structure)
- Models: `User`, `Conversation`, `Message`, `TypingIndicator`, local `LocalMessage` (SwiftData).
- Services: `SupabaseClient`, `RealtimeService` (or inline in VMs), `LocalStorageService`, `MessageSyncService`, `ConversationService`.
- ViewModels: `AuthViewModel`, `ConversationListViewModel`, `ChatViewModel`.
- Views: `LoginView`, `SignUpView`, `ConversationListView`, `ChatView`, `MessageRow`.
- Utilities: `NetworkMonitor`, logging utilities.

## 9) Environment & Secrets
- iOS build settings (xcconfig) provide `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the app at runtime.
- Edge Functions use environment variables injected by Supabase; no client secrets in the app.

## 10) Implementation Roadmap (Epics, Deliverables, Acceptance)
E1. Foundation & Repo Setup — 5 pts
- Deliverables: repo skeleton, docs, env scaffolding, scripts.
- Acceptance: bootstrap script runs; docs present.

E2. Supabase Schema & RLS — 21 pts
- Deliverables: core tables, indexes, RLS, triggers, (optional) seeds.
- Acceptance: `supabase db push` succeeds; auth’d queries pass/deny as designed.

E3. iOS App Bootstrap — 8 pts
- Deliverables: Xcode project, SPM deps, configs; `SupabaseClient` skeleton.
- Acceptance: app launches; simple health call works.

E4. Authentication & Profile — 13 pts
- Deliverables: `AuthViewModel`, Login/SignUp views; profile create/fetch/update; last_seen updates.
- Acceptance: sign up/in/out works; session persists; RLS holds.

E5. Conversations & Chat Core — 21 pts
- Deliverables: conversation list; chat view with optimistic send and reconciliation.
- Acceptance: send text with local_id; reconciles on insert; basic error path.

E6. Realtime Messaging — 8 pts
- Deliverables: message insert subscription; typing indicators.
- Acceptance: p50 <200ms delivery; dedup against optimistic UI.

E7. Offline & Local Persistence — 13 pts
- Deliverables: SwiftData models, local cache, outbox sync, network monitor.
- Acceptance: offline send queues; reconnect posts; restart shows local history.

E8. Read Receipts — 8 pts
- Deliverables: insert read receipts; show status for own messages.
- Acceptance: sent/delivered/read status displays consistently.

E9. Group Chat Management — 8 pts
- Deliverables: create group; add/remove participants; sender attribution in groups.
- Acceptance: participant CRUD respects RLS; UI attribution correct.

E10. Push Notifications (APNs) — 13 pts
- Deliverables: iOS device token save; APNs relay function; optional DB trigger.
- Acceptance: token persists; relay reachable; basic notification delivered (staging).

E11. Observability & Hardening — 5 pts
- Deliverables: OSLog, error handling surfaces, retry/backoff utilities; release configs.
- Acceptance: structured logs visible; basic resiliency in poor networks.

## 11) Current Status (Updated: 2025-10-20)
- ✅ Foundation & docs: completed
- ✅ Supabase core schema: completed
- ✅ Supabase RLS & triggers: completed
- ✅ iOS project bootstrap: completed
- ✅ Authentication & profile: completed
- ✅ Conversations & chat core: completed
- ✅ Realtime messaging: completed
- ✅ Offline & local persistence: completed
- ✅ Read receipts: completed
- ✅ Group chat management: completed (create, manage, sender attribution)
- ✅ Push notifications: completed (APNs integration, auto-trigger)
- ✅ Observability & hardening: completed (logging, configs, icons)
- AI spec: completed (separate doc, Phase 2)
- **Progress**: 123/123 story points (100% complete)
- **Status**: Phase 1 implementation complete and ready for deployment testing

## 12) Rollout
- Local/dev: `supabase db push`; run app on simulator/devices.
- Staging: deploy push function; test APNs with test tokens.
- Production: finalize provisioning, feature‑flag push trigger, monitor logs.

---
This spec is the source of truth for the Phase 1 (non‑AI) implementation. Any deviations will be reflected here and in the plan’s TODO statuses.
