-- Reminders Table Migration
-- AI-created reminders for users to address conflicts and follow-ups

CREATE TABLE IF NOT EXISTS reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Reminder content
    title TEXT NOT NULL,
    context TEXT,  -- Additional context or details

    -- Timing
    reminder_time TIMESTAMPTZ NOT NULL,

    -- Priority and status
    priority TEXT NOT NULL CHECK (priority IN ('urgent', 'high', 'medium', 'low')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'dismissed')),

    -- Metadata
    created_by TEXT DEFAULT 'user' CHECK (created_by IN ('user', 'ai')),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_reminders_user_status
    ON reminders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_reminders_reminder_time
    ON reminders(reminder_time) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_reminders_created_by
    ON reminders(created_by);

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_reminders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();

    -- Set completion/dismissal timestamps
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        NEW.completed_at = now();
    END IF;

    IF NEW.status = 'dismissed' AND OLD.status != 'dismissed' THEN
        NEW.dismissed_at = now();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reminders_updated_at_trigger ON reminders;
CREATE TRIGGER reminders_updated_at_trigger
    BEFORE UPDATE ON reminders
    FOR EACH ROW
    EXECUTE FUNCTION update_reminders_updated_at();

-- Row Level Security
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own reminders" ON reminders;
CREATE POLICY "Users can view their own reminders" ON reminders FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own reminders" ON reminders;
CREATE POLICY "Users can insert their own reminders" ON reminders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own reminders" ON reminders;
CREATE POLICY "Users can update their own reminders" ON reminders FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own reminders" ON reminders;
CREATE POLICY "Users can delete their own reminders" ON reminders FOR DELETE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all reminders" ON reminders;
CREATE POLICY "Service role can manage all reminders" ON reminders FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Comments
COMMENT ON TABLE reminders IS 'User reminders created by AI or manually for conflict resolution and follow-ups';
COMMENT ON COLUMN reminders.created_by IS 'Source of reminder: user (manual) or ai (auto-generated)';
COMMENT ON COLUMN reminders.reminder_time IS 'When user should be reminded';
