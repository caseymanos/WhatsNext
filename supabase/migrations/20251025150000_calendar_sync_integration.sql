-- Calendar Sync Integration Migration
-- Purpose: Add sync tracking for Apple Calendar, Google Calendar, and Apple Reminders
-- Phase: Calendar & Reminders Integration

-- Add sync tracking columns to calendar_events table
ALTER TABLE calendar_events
ADD COLUMN IF NOT EXISTS apple_calendar_event_id TEXT,
ADD COLUMN IF NOT EXISTS google_calendar_event_id TEXT,
ADD COLUMN IF NOT EXISTS sync_status TEXT DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed', 'syncing')),
ADD COLUMN IF NOT EXISTS last_sync_attempt TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS sync_error TEXT;

-- Add sync tracking columns to deadlines table
ALTER TABLE deadlines
ADD COLUMN IF NOT EXISTS apple_reminder_id TEXT,
ADD COLUMN IF NOT EXISTS sync_status TEXT DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed', 'syncing')),
ADD COLUMN IF NOT EXISTS last_sync_attempt TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS sync_error TEXT;

-- Add sync tracking columns to rsvp_tracking table (RSVPs can also become calendar events)
ALTER TABLE rsvp_tracking
ADD COLUMN IF NOT EXISTS apple_calendar_event_id TEXT,
ADD COLUMN IF NOT EXISTS google_calendar_event_id TEXT,
ADD COLUMN IF NOT EXISTS sync_status TEXT DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed', 'syncing')),
ADD COLUMN IF NOT EXISTS last_sync_attempt TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS sync_error TEXT;

-- User calendar sync settings and preferences
CREATE TABLE IF NOT EXISTS calendar_sync_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Feature toggles
    apple_calendar_enabled BOOLEAN DEFAULT true,
    google_calendar_enabled BOOLEAN DEFAULT false,
    apple_reminders_enabled BOOLEAN DEFAULT true,

    -- Category to calendar mapping (JSON object)
    -- Example: {"school": "Work", "medical": "Personal", "social": "Family", ...}
    -- Maps AI event categories to user's calendar names
    category_calendar_mapping JSONB DEFAULT '{}'::jsonb,

    -- Google Calendar OAuth credentials (encrypted in production)
    google_calendar_id TEXT, -- Selected Google Calendar ID
    google_access_token TEXT,
    google_refresh_token TEXT,
    google_token_expiry TIMESTAMPTZ,

    -- Sync preferences
    auto_sync_enabled BOOLEAN DEFAULT true,
    sync_to_all_participants BOOLEAN DEFAULT true, -- For group conversations

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Sync retry queue for failed operations
CREATE TABLE IF NOT EXISTS calendar_sync_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Item being synced
    item_type TEXT NOT NULL CHECK (item_type IN ('calendar_event', 'deadline', 'rsvp')),
    item_id UUID NOT NULL,

    -- Operation details
    operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'delete')),
    target_system TEXT NOT NULL CHECK (target_system IN ('apple_calendar', 'google_calendar', 'apple_reminders')),

    -- Retry logic
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    last_error TEXT,
    next_retry_at TIMESTAMPTZ,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- External calendar change tracking (for two-way sync)
CREATE TABLE IF NOT EXISTS calendar_external_changes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- External calendar details
    external_system TEXT NOT NULL CHECK (external_system IN ('apple_calendar', 'google_calendar', 'apple_reminders')),
    external_id TEXT NOT NULL, -- Event/reminder ID in external system

    -- Change details
    change_type TEXT NOT NULL CHECK (change_type IN ('created', 'updated', 'deleted')),
    change_data JSONB, -- Full event/reminder data from external system

    -- Processing status
    processed BOOLEAN DEFAULT false,
    processed_at TIMESTAMPTZ,

    -- Timestamps
    detected_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_calendar_events_sync_status
    ON calendar_events(sync_status, last_sync_attempt);

CREATE INDEX IF NOT EXISTS idx_calendar_events_apple_id
    ON calendar_events(apple_calendar_event_id) WHERE apple_calendar_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_calendar_events_google_id
    ON calendar_events(google_calendar_event_id) WHERE google_calendar_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_deadlines_sync_status
    ON deadlines(sync_status, last_sync_attempt);

CREATE INDEX IF NOT EXISTS idx_deadlines_apple_reminder_id
    ON deadlines(apple_reminder_id) WHERE apple_reminder_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_rsvp_tracking_sync_status
    ON rsvp_tracking(sync_status, last_sync_attempt);

CREATE INDEX IF NOT EXISTS idx_sync_queue_next_retry
    ON calendar_sync_queue(next_retry_at) WHERE next_retry_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sync_queue_user
    ON calendar_sync_queue(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_external_changes_unprocessed
    ON calendar_external_changes(user_id, processed) WHERE processed = false;

-- Updated_at triggers
CREATE OR REPLACE FUNCTION update_calendar_sync_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS calendar_sync_settings_updated_at_trigger ON calendar_sync_settings;
CREATE TRIGGER calendar_sync_settings_updated_at_trigger
    BEFORE UPDATE ON calendar_sync_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_calendar_sync_settings_updated_at();

CREATE OR REPLACE FUNCTION update_calendar_sync_queue_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS calendar_sync_queue_updated_at_trigger ON calendar_sync_queue;
CREATE TRIGGER calendar_sync_queue_updated_at_trigger
    BEFORE UPDATE ON calendar_sync_queue
    FOR EACH ROW
    EXECUTE FUNCTION update_calendar_sync_queue_updated_at();

-- Comments for documentation
COMMENT ON TABLE calendar_sync_settings IS 'User preferences for calendar and reminder synchronization';
COMMENT ON TABLE calendar_sync_queue IS 'Retry queue for failed calendar sync operations';
COMMENT ON TABLE calendar_external_changes IS 'Track changes made externally in user calendars for two-way sync';

COMMENT ON COLUMN calendar_events.apple_calendar_event_id IS 'EventKit event identifier in Apple Calendar';
COMMENT ON COLUMN calendar_events.google_calendar_event_id IS 'Event ID in Google Calendar';
COMMENT ON COLUMN calendar_events.sync_status IS 'Current sync status: pending, synced, failed, syncing';

COMMENT ON COLUMN deadlines.apple_reminder_id IS 'EventKit reminder identifier in Apple Reminders';
COMMENT ON COLUMN deadlines.sync_status IS 'Current sync status: pending, synced, failed, syncing';

COMMENT ON COLUMN calendar_sync_settings.category_calendar_mapping IS 'JSON mapping of AI categories to user calendar names';
COMMENT ON COLUMN calendar_sync_settings.sync_to_all_participants IS 'Whether to sync events to all conversation participants';
