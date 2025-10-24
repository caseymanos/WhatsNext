-- AI Phase Migration: Create AI feature tables
-- Phase: AI Implementation
-- Purpose: Support Busy Parent/Caregiver persona AI features

-- Calendar Events: AI-extracted calendar events from conversations
CREATE TABLE calendar_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    date DATE NOT NULL,
    time TIME,
    location TEXT,
    description TEXT,
    category TEXT, -- e.g., 'school', 'medical', 'social', 'sports'
    confidence NUMERIC(3,2) CHECK (confidence >= 0 AND confidence <= 1),
    confirmed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Decisions: AI-tracked decisions from group/family conversations
CREATE TABLE decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    decision_text TEXT NOT NULL,
    category TEXT, -- e.g., 'activity', 'schedule', 'purchase', 'policy'
    decided_by UUID REFERENCES users(id) ON DELETE SET NULL,
    deadline DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Priority Messages: AI-detected important messages requiring attention
CREATE TABLE priority_messages (
    message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    priority TEXT NOT NULL CHECK (priority IN ('urgent', 'high', 'medium')),
    reason TEXT NOT NULL,
    action_required BOOLEAN DEFAULT false,
    dismissed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RSVP Tracking: Track event RSVPs and responses
CREATE TABLE rsvp_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_name TEXT NOT NULL,
    requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
    deadline TIMESTAMPTZ,
    event_date TIMESTAMPTZ,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'yes', 'no', 'maybe')),
    response TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    responded_at TIMESTAMPTZ,
    UNIQUE(message_id, user_id)
);

-- Deadlines: AI-extracted deadlines and tasks
CREATE TABLE deadlines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    task TEXT NOT NULL,
    deadline TIMESTAMPTZ NOT NULL,
    category TEXT, -- e.g., 'school', 'bills', 'chores', 'forms'
    priority TEXT CHECK (priority IN ('urgent', 'high', 'medium', 'low')),
    details TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Reminders: AI-generated and user-created reminders
CREATE TABLE reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    reminder_time TIMESTAMPTZ NOT NULL,
    priority TEXT CHECK (priority IN ('urgent', 'high', 'medium', 'low')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'dismissed')),
    created_by TEXT DEFAULT 'ai', -- 'ai' or 'user'
    created_at TIMESTAMPTZ DEFAULT now()
);

-- AI Usage Tracking: Rate limiting and cost control
CREATE TABLE ai_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    function_name TEXT NOT NULL,
    tokens_used INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Add updated_at trigger for calendar_events
CREATE OR REPLACE FUNCTION update_calendar_events_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calendar_events_updated_at_trigger
    BEFORE UPDATE ON calendar_events
    FOR EACH ROW
    EXECUTE FUNCTION update_calendar_events_updated_at();

-- Comments for documentation
COMMENT ON TABLE calendar_events IS 'AI-extracted calendar events from conversation messages';
COMMENT ON TABLE decisions IS 'AI-tracked decisions from family/group conversations';
COMMENT ON TABLE priority_messages IS 'AI-detected high-priority messages requiring attention';
COMMENT ON TABLE rsvp_tracking IS 'RSVP tracking for events mentioned in conversations';
COMMENT ON TABLE deadlines IS 'AI-extracted deadlines and tasks from conversations';
COMMENT ON TABLE reminders IS 'User and AI-generated reminders';
COMMENT ON TABLE ai_usage IS 'Track AI function usage for rate limiting and cost analysis';
