-- AI Phase Migration: Create indexes for AI tables
-- Phase: AI Implementation
-- Purpose: Optimize query performance for AI features

-- Calendar Events indexes
CREATE INDEX IF NOT EXISTS idx_calendar_events_conversation_id ON calendar_events(conversation_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_date ON calendar_events(date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_conversation_date ON calendar_events(conversation_id, date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_confirmed ON calendar_events(confirmed) WHERE NOT confirmed;

-- Decisions indexes
CREATE INDEX IF NOT EXISTS idx_decisions_conversation_id ON decisions(conversation_id);
CREATE INDEX IF NOT EXISTS idx_decisions_deadline ON decisions(deadline) WHERE deadline IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_decisions_conversation_created ON decisions(conversation_id, created_at DESC);

-- Priority Messages indexes
CREATE INDEX IF NOT EXISTS idx_priority_messages_dismissed ON priority_messages(dismissed) WHERE NOT dismissed;
CREATE INDEX IF NOT EXISTS idx_priority_messages_priority ON priority_messages(priority);

-- RSVP Tracking indexes
CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_user_id ON rsvp_tracking(user_id);
CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_conversation_id ON rsvp_tracking(conversation_id);
CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_status ON rsvp_tracking(status);
CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_user_status ON rsvp_tracking(user_id, status);
CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_deadline ON rsvp_tracking(deadline) WHERE deadline IS NOT NULL;

-- Deadlines indexes
CREATE INDEX IF NOT EXISTS idx_deadlines_user_id ON deadlines(user_id);
CREATE INDEX IF NOT EXISTS idx_deadlines_conversation_id ON deadlines(conversation_id);
CREATE INDEX IF NOT EXISTS idx_deadlines_deadline ON deadlines(deadline);
CREATE INDEX IF NOT EXISTS idx_deadlines_user_status ON deadlines(user_id, status);
CREATE INDEX IF NOT EXISTS idx_deadlines_user_deadline ON deadlines(user_id, deadline) WHERE status = 'pending';

-- Reminders indexes
CREATE INDEX IF NOT EXISTS idx_reminders_user_id ON reminders(user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_reminder_time ON reminders(reminder_time);
CREATE INDEX IF NOT EXISTS idx_reminders_user_status ON reminders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_reminders_pending ON reminders(reminder_time) WHERE status = 'pending';

-- AI Usage indexes (for rate limiting)
CREATE INDEX IF NOT EXISTS idx_ai_usage_user_function ON ai_usage(user_id, function_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_created_at ON ai_usage(created_at);
