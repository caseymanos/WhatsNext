-- AI Incremental Processing Migration
-- Adds tracking columns to support incremental AI message processing
-- This enables processing only new messages instead of entire conversation history

-- Add message-level tracking
-- Tracks when a message was last processed by any AI feature
ALTER TABLE messages ADD COLUMN IF NOT EXISTS ai_last_processed TIMESTAMPTZ;

-- Add conversation-level analysis tracking
-- Stores last analysis timestamp per feature in JSONB format
-- Example: {"extract-calendar-events": "2025-10-24T10:30:00Z", "detect-priority": "2025-10-24T10:31:00Z"}
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS ai_last_analysis JSONB DEFAULT '{}'::jsonb;

-- Index for efficient incremental queries
-- Enables fast lookup of unprocessed messages in a conversation
CREATE INDEX IF NOT EXISTS idx_messages_ai_tracking
  ON messages(conversation_id, ai_last_processed, created_at)
  WHERE ai_last_processed IS NOT NULL;

-- Additional index for messages never processed (NULL check is fast)
CREATE INDEX IF NOT EXISTS idx_messages_never_processed
  ON messages(conversation_id, created_at)
  WHERE ai_last_processed IS NULL;

-- GIN index for JSONB queries on ai_last_analysis
-- Enables fast feature-specific timestamp lookups
CREATE INDEX IF NOT EXISTS idx_conversations_ai_last_analysis
  ON conversations USING gin(ai_last_analysis);

-- Comments for documentation
COMMENT ON COLUMN messages.ai_last_processed IS 'Timestamp when message was last processed by any AI feature. NULL means never processed.';
COMMENT ON COLUMN conversations.ai_last_analysis IS 'Per-feature last analysis timestamps stored as JSONB. Format: {"feature-name": "ISO-8601-timestamp", ...}';

-- Note: No RLS policy changes needed - these columns are internal tracking only
-- The service role will update these via edge functions
