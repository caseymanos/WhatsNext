-- Fix auto-parse trigger by using a configuration table instead of database settings
-- This approach works without requiring superuser permissions

-- Create app_settings table to store configuration
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS but only allow system access (not user access)
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- Insert Supabase URL configuration
INSERT INTO app_settings (key, value, description)
VALUES (
  'supabase_url',
  'https://wgptkitofarpdyhmmssx.supabase.co',
  'Supabase project URL for API calls'
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  updated_at = NOW();

-- Note: Service role key must be added manually via SQL Editor for security
-- Run this command in the Supabase SQL Editor with your service role key:
--
-- INSERT INTO app_settings (key, value, description)
-- VALUES (
--   'service_role_key',
--   'your_service_role_key_here',
--   'Service role key for internal API calls'
-- )
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
--
-- To get your service role key:
-- 1. Go to: https://supabase.com/dashboard/project/wgptkitofarpdyhmmssx/settings/api
-- 2. Copy the "service_role" key (NOT the anon key)
-- 3. Run the INSERT command above in SQL Editor

-- Update trigger function to read from app_settings table
CREATE OR REPLACE FUNCTION trigger_parse_message_ai()
RETURNS TRIGGER AS $$
DECLARE
  function_url TEXT;
  service_role_key TEXT;
  request_body TEXT;
  supabase_url TEXT;
BEGIN
  -- Read configuration from app_settings table
  SELECT value INTO supabase_url
  FROM app_settings
  WHERE key = 'supabase_url';

  SELECT value INTO service_role_key
  FROM app_settings
  WHERE key = 'service_role_key';

  -- Skip if configuration is missing
  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RAISE WARNING 'Auto-parse configuration missing. Please configure app_settings table.';
    RETURN NEW;
  END IF;

  -- Build function URL
  function_url := supabase_url || '/functions/v1/parse-message-ai';

  -- Skip if message is a system message or too short
  IF NEW.message_type != 'text' OR LENGTH(NEW.content) < 10 THEN
    RETURN NEW;
  END IF;

  -- Build request body
  request_body := json_build_object(
    'messageId', NEW.id,
    'conversationId', NEW.conversation_id,
    'senderId', NEW.sender_id,
    'content', NEW.content
  )::text;

  -- Make async HTTP request to edge function (non-blocking)
  PERFORM net.http_post(
    url := function_url,
    headers := json_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_role_key
    )::jsonb,
    body := request_body::jsonb,
    timeout_milliseconds := 30000
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail the insert
    RAISE WARNING 'Failed to trigger parse-message-ai: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add helpful comments
COMMENT ON TABLE app_settings IS 'Application configuration settings for edge function triggers';
COMMENT ON COLUMN app_settings.key IS 'Configuration key (unique identifier)';
COMMENT ON COLUMN app_settings.value IS 'Configuration value';
COMMENT ON FUNCTION trigger_parse_message_ai() IS 'Automatically calls parse-message-ai edge function using app_settings configuration';
