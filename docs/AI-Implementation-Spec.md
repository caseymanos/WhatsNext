# AI Implementation Planning (Phase 2)

Design/specification only for the AI layer that builds on the Core app. No implementation in this phase.

## 1) Overview
- Persona: Busy Parent/Caregiver
- Provider: OpenAI via Vercel AI SDK in Supabase Edge Functions (Deno)
- Out of scope: Client UI wiring, streaming UX, external calendar integrations

## 2) Dependencies on Core
- Core schema and RLS exist: `users`, `conversations`, `conversation_participants`, `messages`, `typing_indicators`, `read_receipts`
- Auth is present; iOS passes `Authorization` header to Supabase Edge Functions
- Optional: Push relay function exists for basic APNs (not required by AI phase)

## 3) Deliverables (Phase 2)
- AI DB migrations (tables, indexes, RLS)
- Supabase Edge Functions for 6 features with validated JSON contracts
- iOS contracts (Swift model shapes only; no UI or wiring)
- Observability (structured logs), soft rate limits, fixtures for QA
- Rollout and feature flags

## 4) Architecture (AI Layer)
- Runtime: Supabase Edge Functions (Deno)
- AI SDK: `npm:ai` + `npm:@ai-sdk/openai` (no streaming initially)
- DB access: `jsr:@supabase/supabase-js@2` with `global.headers.Authorization` to enforce RLS
- Validation: `npm:zod` schemas for structured outputs
- Isolation: One function per capability; shared deps under `supabase/functions/_shared/`

```
[iOS SwiftUI]
  → supabase.functions.invoke()
    → [Supabase Edge Function]
       ├─ supabase-js (RLS)
       ├─ Vercel AI SDK (OpenAI)
       └─ Persist structured results → Postgres (AI tables)
```

## 5) Dependencies & Config
- Packages (pin minimum compatible versions):
  - `npm:ai@3.4.29`
  - `npm:@ai-sdk/openai@1.0.5`
  - `npm:zod@3.22.4`
  - `jsr:@supabase/supabase-js@2`
- Function env vars:
  - `OPENAI_API_KEY` (required)
  - `SUPABASE_URL`, `SUPABASE_ANON_KEY` (auto-injected by Supabase)
- Models: Use `gpt-4o` (allow `gpt-4o-mini` for cost-sensitive paths)

## 6) Database (AI Phase Migrations)
Create in AI phase (not core):
- `calendar_events(id, conversation_id, message_id, title, date, time, location, description, category, confidence, confirmed, created_at)`
- `decisions(id, conversation_id, message_id, decision_text, category, decided_by, deadline, created_at)`
- `priority_messages(message_id PK, priority, reason, action_required, dismissed, created_at)`
- `rsvp_tracking(id, message_id, conversation_id, user_id, event_name, requested_by, deadline, event_date, status, response, created_at, responded_at, UNIQUE(message_id,user_id))`
- `deadlines(id, message_id, conversation_id, user_id, task, deadline, category, priority, details, status, created_at, completed_at)`
- `reminders(id, user_id, title, reminder_time, priority, status, created_by, created_at)`

Indexes
- Conversation/date/status columns on each table for query performance

RLS Summary
- Conversation-scoped tables: SELECT for members only; INSERT via user-auth Edge Functions
- Per-user tables (`rsvp_tracking`, `deadlines`, `reminders`): SELECT/UPDATE only when `auth.uid()` matches `user_id`

## 7) Edge Functions (Endpoints & Contracts)
Common requirements
- Require `Authorization` header; construct supabase client with `global.headers.Authorization`
- Input validation via zod; cap history (≤100 messages; ≤7–30 days)
- Redact logs (no message content); include `requestId`; target ≤15s runtime

Endpoints
1. `extract-calendar-events`
   - Input: `{ conversationId: string, messageIds?: string[] }`
   - Output: `{ events: CalendarEvent[] }`
   - Behavior: Fetch messages, `generateObject` with zod schema; persist events where `confidence >= 0.7`

2. `track-decisions`
   - Input: `{ conversationId: string, daysBack?: number }`
   - Output: `{ decisions: Decision[] }`

3. `detect-priority`
   - Input: `{ conversationId: string }`
   - Output: `{ priorityMessages: { messageId: string, priority: 'urgent'|'high'|'medium', reason: string, actionRequired: boolean }[] }`

4. `track-rsvps`
   - Input: `{ conversationId: string, userId: string }`
   - Output: `{ rsvps: RSVPSummary[] }`

5. `extract-deadlines`
   - Input: `{ conversationId: string, userId: string }`
   - Output: `{ deadlines: Deadline[] }` (+ auto-create day-before reminder)

6. `proactive-assistant` (multi-step tools agent)
   - Input: `{ conversationId: string, userId: string }`
   - Output: `{ message: string, steps?: any[] }`
   - Tools: `getRecentMessages`, `getCalendarEvents`, `getPendingRSVPs`, `getDeadlines`, `checkConflicts`, `createReminder`

Optional structured variant
- `proactive-scan` using `generateObject` to return arrays of `conflicts`, `pendingRSVPs`, `deadlines`, `recommendations`

Representative function skeleton
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai'
import { openai } from 'npm:@ai-sdk/openai'
import { z } from 'npm:zod'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  const auth = req.headers.get('Authorization')
  if (!auth) return new Response('Unauthorized', { status: 401 })

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } }
  )

  // 1) fetch bounded data  2) AI with zod schema  3) persist  4) return JSON
  return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } })
})
```

## 8) iOS Integration Contracts (to be consumed later)
- Invocation pattern:
```swift
let res = try await supabase.functions.invoke(
  "extract-calendar-events",
  options: .init(body: ["conversationId": id.uuidString])
)
```
- Swift models mirror JSON: `CalendarEvent`, `Decision`, `PriorityMessage`, `RSVPSummary`, `Deadline`, `ProactiveAnalysis`
- Errors: `{ error: string, code?: string }`; no streaming required initially

## 9) Performance, Rate Limits, Cost
- Token budgets per call
  - Calendar/Decisions/Priority/RSVP/Deadlines: ≤1,200 prompt / ≤600 output
  - Proactive Assistant: ≤2,000 / ≤800; ≤5 tool steps
- Soft rate limits: 30 calls/user/day/function via `ai_usage` table (return 429 on exceed)

## 10) Security & Privacy
- Verify conversation membership before any read
- Enforce RLS through user `Authorization` header on supabase-js client
- No message content in logs; store structured outputs only
- Secrets only in function env; never exposed to client

## 11) Observability & QA
- Structured logs: `{ requestId, stage, counts }` (no PII)
- Local run: `supabase functions serve <fn> --env-file .env.local`
- Golden fixtures under `supabase/functions/_fixtures/` per feature
- Manual QA transcripts (busy parent scenarios) per endpoint

## 12) Deployment & Rollout
- Migrations: `supabase db push` (AI tables)
- Deploy functions: `supabase functions deploy <name>` per endpoint
- Feature flags: `feature_flags(user_id, feature, enabled)`; client gates AI UI on flags
- Stage → prod after quota/latency validation

## 13) AI Backlog (Story Points)
- A1. AI migrations & RLS — 8 pts
- A2. `_shared/deps.ts` — 1 pt
- A3. extract-calendar-events — 5 pts
- A4. track-decisions — 5 pts
- A5. detect-priority — 4 pts
- A6. track-rsvps — 6 pts
- A7. extract-deadlines — 6 pts
- A8. proactive-assistant — 13 pts
- A9. iOS models/contracts (interfaces only) — 5 pts
- A10. QA fixtures, rate limits, logs — 5 pts

## 14) File Map (AI Phase)
```
supabase/
  migrations/
    2025-xx-xx-ai-001_tables.sql
    2025-xx-xx-ai-002_rls.sql
    2025-xx-xx-ai-003_indexes.sql
  functions/
    _shared/deps.ts
    extract-calendar-events/index.ts
    track-decisions/index.ts
    detect-priority/index.ts
    track-rsvps/index.ts
    extract-deadlines/index.ts
    proactive-assistant/index.ts
    proactive-scan/index.ts   # optional structured variant
  functions/_fixtures/
    calendar.sample.json
    decisions.sample.json
    rsvps.sample.json
    deadlines.sample.json

ios/MessageAI/
  Services/AI/ (README only until Phase 2)
  Models/AI/ (Swift struct shapes)

docs/
  AI-Implementation-Spec.md (this document)
```

