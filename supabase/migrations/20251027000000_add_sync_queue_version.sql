-- Add version column for optimistic locking in calendar_sync_queue
-- This prevents race conditions when multiple sync operations try to update the same queue item

-- Add version column with default 1
ALTER TABLE calendar_sync_queue
ADD COLUMN IF NOT EXISTS version INT DEFAULT 1 NOT NULL;

-- Create index for efficient version checks
CREATE INDEX IF NOT EXISTS idx_calendar_sync_queue_version
ON calendar_sync_queue(id, version);

-- Update trigger to increment version on every update
CREATE OR REPLACE FUNCTION increment_sync_queue_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists and recreate
DROP TRIGGER IF EXISTS calendar_sync_queue_version_trigger ON calendar_sync_queue;

DROP TRIGGER IF EXISTS calendar_sync_queue_version_trigger ON calendar_sync_queue;
CREATE TRIGGER calendar_sync_queue_version_trigger
    BEFORE UPDATE ON calendar_sync_queue
    FOR EACH ROW
    EXECUTE FUNCTION increment_sync_queue_version();

-- Add comment explaining optimistic locking
COMMENT ON COLUMN calendar_sync_queue.version IS 'Version number for optimistic locking to prevent concurrent update conflicts';
