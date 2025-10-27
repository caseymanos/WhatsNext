-- Migration: Push Notification Trigger
-- Automatically sends push notifications when new messages are inserted
-- Created: 2025-10-20

-- Function to send push notification via edge function
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
BEGIN
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

  -- Get edge function URL from environment or use default
  -- In production, this should be set via Supabase dashboard secrets
  edge_function_url := current_setting('app.edge_function_url', true);
  IF edge_function_url IS NULL THEN
    edge_function_url := 'https://your-project.supabase.co/functions/v1/send-notification';
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
    -- Call edge function via HTTP POST
    -- Note: This requires the http extension to be enabled
    PERFORM
      net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
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

-- Create trigger on messages table
DROP TRIGGER IF EXISTS trigger_notify_message_recipients ON messages;

DROP TRIGGER IF EXISTS trigger_notify_message_recipients ON messages;
CREATE TRIGGER trigger_notify_message_recipients
  AFTER INSERT ON messages
  FOR EACH ROW
  WHEN (NEW.message_type = 'text')  -- Only trigger for text messages
  EXECUTE FUNCTION notify_message_recipients();

-- Add comment
COMMENT ON FUNCTION notify_message_recipients() IS 'Sends push notifications to conversation participants when a new message is inserted';
COMMENT ON TRIGGER trigger_notify_message_recipients ON messages IS 'Automatically sends push notifications for new text messages';

-- Note: To enable this trigger in production, you need to:
-- 1. Enable the http extension: CREATE EXTENSION IF NOT EXISTS http;
-- 2. Or use pg_net extension for async calls: CREATE EXTENSION IF NOT EXISTS pg_net;
-- 3. Set the edge_function_url: ALTER DATABASE postgres SET app.edge_function_url = 'https://your-project.supabase.co/functions/v1/send-notification';
-- 4. Set the service_role_key: ALTER DATABASE postgres SET app.service_role_key = 'your-service-role-key';

-- Alternative implementation using pg_net (async, recommended for production)
CREATE OR REPLACE FUNCTION notify_message_recipients_async()
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

  -- Get configuration from vault or settings
  edge_function_url := current_setting('app.edge_function_url', true);
  service_role_key := current_setting('app.service_role_key', true);

  -- Skip if not configured
  IF edge_function_url IS NULL OR service_role_key IS NULL THEN
    RAISE NOTICE 'Push notifications not configured, skipping';
    RETURN NEW;
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

-- To use the async version, replace the trigger:
-- DROP TRIGGER IF EXISTS trigger_notify_message_recipients ON messages;
-- CREATE TRIGGER trigger_notify_message_recipients
--   AFTER INSERT ON messages
--   FOR EACH ROW
--   WHEN (NEW.message_type = 'text')
--   EXECUTE FUNCTION notify_message_recipients_async();

