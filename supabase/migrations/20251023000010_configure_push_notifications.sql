-- Migration: Configure Push Notification Settings
-- Creates a configuration table and updates trigger to use it
-- Created: 2025-10-23

-- Create a configuration table for push notifications
CREATE TABLE IF NOT EXISTS public.push_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS on config table (only admins can modify)
ALTER TABLE public.push_config ENABLE ROW LEVEL SECURITY;

-- Only service role can read/write config
DROP POLICY IF EXISTS "Service role can manage config" ON public.push_config;
CREATE POLICY "Service role can manage config"
  ON public.push_config
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Insert default configuration
INSERT INTO public.push_config (key, value) VALUES
  ('edge_function_url', 'https://wgptkitofarpdyhmmssx.supabase.co/functions/v1/send-notification'),
  ('service_role_key', 'PLACEHOLDER_SET_VIA_DASHBOARD')
ON CONFLICT (key) DO UPDATE SET updated_at = NOW();

-- Update the notification trigger function to use the config table
CREATE OR REPLACE FUNCTION notify_message_recipients()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  participant_record RECORD;
  sender_user RECORD;
  conversation_record RECORD;
  notification_title TEXT;
  notification_body TEXT;
  edge_function_url TEXT;
  service_role_key TEXT;
BEGIN
  -- Get configuration from config table
  SELECT value INTO edge_function_url
  FROM public.push_config
  WHERE key = 'edge_function_url';
  
  SELECT value INTO service_role_key
  FROM public.push_config
  WHERE key = 'service_role_key';
  
  -- Skip if not configured properly
  IF edge_function_url IS NULL OR service_role_key IS NULL OR service_role_key = 'PLACEHOLDER_SET_VIA_DASHBOARD' THEN
    RAISE NOTICE 'Push notifications not configured, skipping';
    RETURN NEW;
  END IF;

  -- Get sender information
  SELECT display_name, username, email INTO sender_user
  FROM users
  WHERE id = NEW.sender_id;

  -- Get conversation information
  SELECT name, is_group INTO conversation_record
  FROM conversations
  WHERE id = NEW.conversation_id;

  -- Build notification title
  IF conversation_record.is_group THEN
    notification_title := conversation_record.name;
  ELSE
    notification_title := COALESCE(sender_user.display_name, sender_user.username, sender_user.email, 'Someone');
  END IF;

  -- Build notification body
  IF conversation_record.is_group THEN
    notification_body := COALESCE(sender_user.display_name, sender_user.username, 'Someone') || ': ' || LEFT(NEW.content, 100);
  ELSE
    notification_body := LEFT(NEW.content, 100);
  END IF;

  -- Send notification to all participants except the sender
  FOR participant_record IN
    SELECT cp.user_id, u.push_token
    FROM conversation_participants cp
    JOIN users u ON u.id = cp.user_id
    WHERE cp.conversation_id = NEW.conversation_id
      AND cp.user_id != NEW.sender_id
      AND u.push_token IS NOT NULL
  LOOP
    -- Queue async HTTP request using pg_net
    PERFORM net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object(
        'userId', participant_record.user_id::text,
        'title', notification_title,
        'body', notification_body,
        'conversationId', NEW.conversation_id::text,
        'messageId', NEW.id::text,
        'senderId', NEW.sender_id::text,
        'senderName', COALESCE(sender_user.display_name, sender_user.username)
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;

-- Create a diagnostic function to check push notification configuration
CREATE OR REPLACE FUNCTION check_push_notification_config()
RETURNS TABLE (
  setting_name TEXT,
  setting_value TEXT,
  is_configured BOOLEAN
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    key as setting_name,
    CASE 
      WHEN key = 'service_role_key' AND value != 'PLACEHOLDER_SET_VIA_DASHBOARD' THEN 'SET (hidden)'
      WHEN key = 'service_role_key' THEN value
      ELSE value
    END as setting_value,
    (value IS NOT NULL AND value != 'PLACEHOLDER_SET_VIA_DASHBOARD')::BOOLEAN as is_configured
  FROM public.push_config
  WHERE key IN ('edge_function_url', 'service_role_key');
END;
$$;

COMMENT ON TABLE public.push_config IS 'Configuration settings for push notifications';
COMMENT ON FUNCTION check_push_notification_config() IS 'Diagnostic function to check if push notification configuration is set';
COMMENT ON FUNCTION notify_message_recipients() IS 'Sends push notifications to conversation participants when a new message is inserted (updated to use config table)';

-- Add helpful comments
COMMENT ON COLUMN push_config.key IS 'Configuration key (edge_function_url, service_role_key)';
COMMENT ON COLUMN push_config.value IS 'Configuration value';
