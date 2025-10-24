# AI Implementation Guide

This guide documents the AI features implementation for WhatsNext (Phase 2).

## Overview

The AI implementation adds intelligent features tailored for the **Busy Parent/Caregiver** persona, helping them manage family schedules, track decisions, monitor deadlines, and stay organized.

## Architecture

### Technology Stack

- **Runtime**: Supabase Edge Functions (Deno)
- **AI SDK**: Vercel AI SDK (`npm:ai@3.4.29`) with OpenAI provider
- **Model**: GPT-4o (with GPT-4o-mini option for cost-sensitive paths)
- **Validation**: Zod schemas for structured outputs
- **Database**: PostgreSQL (Supabase) with RLS policies

### Data Flow

```
iOS App → Supabase Edge Function → OpenAI API → Structured Output → Database
                ↓
         RLS Enforcement (user's JWT)
                ↓
         Response to iOS
```

## AI Features (5 Required + 1 Advanced)

### Required Features

1. **Smart Calendar Extraction** (`extract-calendar-events`)
   - Extracts school events, appointments, activities from conversations
   - Categories: school, medical, social, sports, work
   - Returns confidence scores and auto-saves events with confidence ≥ 0.7

2. **Decision Tracking** (`track-decisions`)
   - Tracks family decisions from group conversations
   - Categories: activity, schedule, purchase, policy, food
   - Identifies what was decided and any associated deadlines

3. **Priority Message Detection** (`detect-priority`)
   - Flags urgent, high, or medium priority messages
   - Identifies messages requiring immediate action
   - Helps parents focus on what matters most

4. **RSVP Tracking** (`track-rsvps`)
   - Detects event invitations requiring responses
   - Tracks RSVP deadlines and status
   - Provides summary of all pending RSVPs

5. **Deadline Extraction** (`extract-deadlines`)
   - Extracts tasks with deadlines from conversations
   - Categories: school, bills, chores, forms, medical, work
   - Auto-creates reminders 1 day before deadline

### Advanced Feature

**Proactive Assistant** (`proactive-assistant`)
- Multi-step agent with tool calling capabilities
- Analyzes schedule for conflicts
- Provides consolidated insights across all features
- Can create reminders and suggest actions
- Tools: getRecentMessages, getCalendarEvents, getPendingRSVPs, getDeadlines, checkConflicts, createReminder

## Database Schema

### AI Tables

```sql
calendar_events      - AI-extracted calendar events
decisions            - Tracked family decisions
priority_messages    - Messages flagged as high-priority
rsvp_tracking        - RSVP requests and responses
deadlines            - Tasks with deadlines
reminders            - User and AI-generated reminders
ai_usage             - Rate limiting and cost tracking
```

### Security

- All tables have Row-Level Security (RLS) enabled
- Users can only see data for conversations they're part of
- Edge Functions use user's JWT for authenticated queries
- Service role only for AI insertions (logged and audited)

## Edge Functions

All functions located in `supabase/functions/`:

| Function | Purpose | Rate Limit |
|----------|---------|------------|
| `extract-calendar-events` | Extract events from messages | 30/day |
| `track-decisions` | Track decisions made | 30/day |
| `detect-priority` | Flag priority messages | 30/day |
| `track-rsvps` | Track RSVP requests | 30/day |
| `extract-deadlines` | Extract tasks with deadlines | 30/day |
| `proactive-assistant` | Multi-step agent analysis | 15/day |

### Shared Utilities

- `_shared/deps.ts` - Centralized imports
- `_shared/utils.ts` - Common functions (auth, rate limiting, logging)

## iOS Integration

### Swift Models

Located in `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Models/AI/`:

- `CalendarEvent.swift` - Calendar event model and response
- `Decision.swift` - Decision tracking model
- `PriorityMessage.swift` - Priority message model
- `RSVPTracking.swift` - RSVP model and response
- `Deadline.swift` - Deadline model and response
- `Reminder.swift` - Reminder model
- `ProactiveAssistant.swift` - Agent response model

### Usage Example

```swift
let response = try await supabase.functions.invoke(
    "extract-calendar-events",
    options: .init(
        body: [
            "conversationId": conversation.id.uuidString,
            "daysBack": 7
        ]
    )
)

let data = try JSONDecoder().decode(
    ExtractCalendarEventsResponse.self,
    from: response.data
)
```

## Deployment

### Prerequisites

1. Set environment variables:
   ```bash
   OPENAI_API_KEY=sk-...
   ```

2. Push database migrations:
   ```bash
   supabase db push
   ```

### Deploy Functions

```bash
# Deploy all AI functions
supabase functions deploy extract-calendar-events
supabase functions deploy track-decisions
supabase functions deploy detect-priority
supabase functions deploy track-rsvps
supabase functions deploy extract-deadlines
supabase functions deploy proactive-assistant
```

### Test Locally

```bash
# Serve function locally
supabase functions serve extract-calendar-events --env-file .env.local

# Test with curl
curl -i --location --request POST 'http://localhost:54321/functions/v1/extract-calendar-events' \
  --header 'Authorization: Bearer YOUR_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"conversationId":"...", "daysBack":7}'
```

## Testing

### Fixtures

Sample conversations for testing are in `supabase/functions/_fixtures/`:

- `calendar-sample.json` - Parent group chat with events
- `decisions-sample.json` - Family planning conversation
- `rsvps-sample.json` - School RSVP requests
- `deadlines-sample.json` - Mixed deadline sources

### QA Scenarios (Busy Parent Persona)

1. **Morning Rush Scenario**
   - Extract all events for the week ahead
   - Check for scheduling conflicts
   - Identify pending permission slips/forms

2. **Group Chat Catch-Up**
   - Detect priority messages while away
   - Track any new RSVPs needed
   - Summarize decisions made

3. **Weekly Planning**
   - Run proactive assistant for consolidated view
   - Review upcoming deadlines
   - Check for missed action items

## Rate Limiting & Cost Control

- Soft rate limits enforced via `ai_usage` table
- Default: 30 calls/day per function per user
- Proactive assistant: 15 calls/day (higher cost)
- Returns 429 status when limit exceeded

## Observability

### Structured Logging

All functions log:
- Request ID (for tracing)
- Stage markers (authenticated, rate_check, messages_fetched, etc.)
- Counts (events extracted, tokens used)
- NO message content or PII

### Monitoring

Check Edge Function logs:
```bash
supabase functions logs extract-calendar-events
```

## Future Enhancements

- [ ] Streaming responses for real-time feedback
- [ ] Calendar integration (Apple Calendar, Google Calendar)
- [ ] Smart notification scheduling
- [ ] Voice input for adding events/tasks
- [ ] Multi-language support for international families
- [ ] Shared family dashboard view

## Troubleshooting

### Common Issues

1. **401 Unauthorized**
   - Check Authorization header is being sent
   - Verify user session is valid

2. **403 Access Denied**
   - User not participant in conversation
   - RLS policies blocking access

3. **429 Rate Limit Exceeded**
   - User has exceeded daily quota
   - Check `ai_usage` table for counts

4. **500 Internal Error**
   - Check Edge Function logs
   - Verify OPENAI_API_KEY is set
   - Ensure database schema is up to date

## Security Considerations

- Never expose OPENAI_API_KEY to client
- All AI calls authenticated via user JWT
- Message content not logged (privacy)
- Rate limiting prevents abuse
- Audit trail via ai_usage table

## References

- [Vercel AI SDK Docs](https://sdk.vercel.ai/docs)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [AI Implementation Spec](./AI-Implementation-Spec.md)
