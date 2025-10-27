-- Add user_id column to calendar_events for proper user scoping
-- Purpose: Fix "Column calendar_events.user_id does not exist" error
-- Date: 2025-10-27

-- Step 1: Add user_id column (nullable initially for backfill)
ALTER TABLE calendar_events
ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;

-- Step 2: Create index for performance
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id
ON calendar_events(user_id);

-- Step 3: Backfill user_id from conversation participants
-- For 1:1 conversations, use the other participant
-- For group conversations, this will set user_id to one of the participants
-- (In production, you may need more sophisticated logic for group conversations)
UPDATE calendar_events ce
SET user_id = (
    SELECT cp.user_id
    FROM conversations c
    JOIN conversation_participants cp ON c.id = cp.conversation_id
    WHERE ce.conversation_id = c.id
    LIMIT 1
)
WHERE ce.user_id IS NULL;

-- Step 4: Make user_id NOT NULL after backfill
ALTER TABLE calendar_events
ALTER COLUMN user_id SET NOT NULL;

-- Update comments
COMMENT ON COLUMN calendar_events.user_id IS 'User who owns this calendar event (for multi-user conversations, this is the user who should see it in their calendar)';
