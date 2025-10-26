# Conflict Detection System - Test Plan

## Overview

This document describes the conflict detection system implementation and provides a comprehensive test plan.

## What Was Built

### 1. Database Schema (Migration: 20251026120000_scheduling_conflicts.sql)

Three new tables:
- **scheduling_conflicts**: Stores detected conflicts with severity levels (urgent/high/medium/low)
- **user_preferences**: Stores user preferences for conflict sensitivity and learned patterns
- **resolution_feedback**: Tracks user feedback on AI suggestions for continuous learning

### 2. Edge Function: detect-conflicts-agent

**Location**: `supabase/functions/detect-conflicts-agent/`

**Components**:
- **index.ts**: Main agent using Vercel AI SDK with GPT-4o
- **tools.ts**: 8 tools for multi-step conflict detection

**8 Detection Tools**:
1. `getCalendarEvents` - Fetch events in date range
2. `getDeadlines` - Fetch pending deadlines
3. `analyzeTimeConflict` - Detect time overlaps, travel time issues, buffer problems
4. `checkDeadlineConflict` - Analyze if schedule prevents meeting deadlines
5. `analyzeCapacity` - Detect schedule overload (too many events, consecutive busy days)
6. `storeConflict` - Persist conflicts to database
7. `createReminder` - Create reminders for urgent conflicts
8. `getUserPreferences` - Get user scheduling preferences

### 3. Test Data

**Calendar Events** (17 events created):
- **Scenario 1**: Direct time overlap (Oct 27, 14:00 & 14:30) - Expected: URGENT conflict
- **Scenario 2**: Insufficient travel time (Oct 28, 09:00-10:00, different locations) - Expected: HIGH conflict
- **Scenario 3**: Back-to-back same location (Oct 29, 10:00 & 11:00, Office) - Expected: LOW conflict
- **Scenario 4**: Capacity overload (Oct 30, 5 events in one day) - Expected: HIGH conflict
- **Scenario 5**: Consecutive busy days (Oct 31 - Nov 2, 2+ events each day) - Expected: MEDIUM conflict

**Deadlines** (3 deadlines created):
- **Scenario 6**: Urgent deadline with busy schedule (Oct 31, 8h needed, Oct 30 has 5 events) - Expected: URGENT/HIGH conflict
- **Scenario 7**: Tight deadline (Nov 3, 4h needed) - Expected: MEDIUM conflict
- **Scenario 8**: Comfortable deadline (Nov 15, plenty of time) - Expected: NO conflict

## Test IDs

- **User ID**: `eda593e9-5ed9-4ab0-aa73-f5fc10a6d065`
- **Conversation ID**: `386dd901-8ef9-4f14-a075-46cf63f5e59d`
- **Project URL**: `https://wgptkitofarpdyhmmssx.supabase.co`

## How to Test

### Method 1: Direct API Call (Requires Auth Token)

You need a valid JWT token for the test user. If you have an auth token:

```bash
curl -X POST \
  https://wgptkitofarpdyhmmssx.supabase.co/functions/v1/detect-conflicts-agent \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "conversationId": "386dd901-8ef9-4f14-a075-46cf63f5e59d",
    "daysAhead": 14
  }'
```

### Method 2: Through iOS App

1. Sign in as the test user
2. Navigate to the conversation with ID `386dd901-8ef9-4f14-a075-46cf63f5e59d`
3. Trigger conflict detection (integration point TBD)
4. Review detected conflicts in AI tab or conversation view

### Method 3: Supabase Dashboard

1. Go to: https://supabase.com/dashboard/project/wgptkitofarpdyhmmssx/functions/detect-conflicts-agent
2. Use the "Invoke" button to test with test data
3. Provide auth token and request payload

### Method 4: SQL Query Verification

After running the agent, verify conflicts were stored:

```sql
SELECT
  conflict_type,
  severity,
  description,
  suggested_resolution,
  affected_items,
  created_at
FROM scheduling_conflicts
WHERE user_id = 'eda593e9-5ed9-4ab0-aa73-f5fc10a6d065'
  AND conversation_id = '386dd901-8ef9-4f14-a075-46cf63f5e59d'
ORDER BY
  CASE severity
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  created_at DESC;
```

## Expected Results

When the agent analyzes the test data, it should detect:

### Time-Based Conflicts
1. **URGENT**: "Parent-teacher conference" and "Doctor appointment" overlap (Oct 27, 14:00-14:30)
2. **HIGH**: Insufficient travel time between "Dentist appointment" and "School pickup" (Oct 28)
3. **LOW**: Back-to-back "Team meeting" and "1:1 with manager" at same location (Oct 29)

### Capacity-Based Conflicts
4. **HIGH**: 5 events on Oct 30 (Morning grocery, Soccer practice, Work presentation, PTA meeting, Family dinner)
5. **MEDIUM**: 3 consecutive busy days (Oct 31 - Nov 2)

### Deadline Conflicts
6. **URGENT/HIGH**: "Complete quarterly report" deadline (Oct 31) impossible due to Oct 30 schedule
7. **MEDIUM**: "Prepare kids science fair project" (Nov 3) - tight but achievable
8. **NO CONFLICT**: "Plan holiday party" (Nov 15) - comfortable timeline

### Total Expected Conflicts
- Urgent: 2
- High: 2-3
- Medium: 2
- Low: 1

**Total: 7-8 conflicts detected**

## Agent Behavior

The agent will:
1. Fetch calendar events (Oct 25 - Nov 8, 14 days)
2. Fetch deadlines in same range
3. Analyze each pair of events on the same day for time conflicts
4. Analyze overall capacity across all days
5. Check each deadline against available time
6. Store significant conflicts (medium+ severity) in database
7. Create reminders for urgent conflicts
8. Return comprehensive summary with actionable recommendations

## Success Criteria

✅ Agent completes without errors
✅ All 7-8 expected conflicts detected
✅ Conflicts stored in `scheduling_conflicts` table
✅ Severity levels correctly assigned
✅ Suggestions are actionable and specific
✅ Tool calls are efficient (< 15 steps)
✅ Response time < 30 seconds

## Next Steps After Testing

If Phase 1 tests pass:
1. **Phase 2**: Integrate into iOS app messaging flow
2. Add trigger logic (analyze after calendar event extraction)
3. Display conflicts in AI tab or conversation
4. Allow user to accept/reject suggestions
5. Track feedback in `resolution_feedback` table
6. Implement learning algorithm to improve suggestions

## Troubleshooting

### No conflicts detected
- Check calendar_events and deadlines tables have test data
- Verify conversation_id and user_id are correct
- Check edge function logs in Supabase dashboard

### Authentication errors
- Ensure valid JWT token in Authorization header
- Verify user has access to conversation (check conversation_participants)

### Tool execution errors
- Check edge function logs for specific error
- Verify all _shared dependencies are deployed
- Check database tables exist with correct schema

## Edge Function Logs

View logs at: https://supabase.com/dashboard/project/wgptkitofarpdyhmmssx/logs/edge-functions?fn=detect-conflicts-agent
