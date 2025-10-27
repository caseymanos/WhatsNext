-- Auto-parse new messages for AI insights
-- This trigger calls the parse-message-ai edge function for every new message inserted

-- Function to invoke parse-message-ai edge function
CREATE OR REPLACE FUNCTION trigger_parse_message_ai()
RETURNS TRIGGER AS $$
DECLARE
  function_url TEXT;
  service_role_key TEXT;
  request_body TEXT;
BEGIN
  -- Get Supabase URL and service role key from environment
  function_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/parse-message-ai';
  service_role_key := current_setting('app.settings.service_role_key', true);

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
  -- Use pg_net extension for async HTTP calls
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

-- Create trigger on messages INSERT
DROP TRIGGER IF EXISTS auto_parse_message_ai ON messages;
CREATE TRIGGER auto_parse_message_ai
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION trigger_parse_message_ai();

-- Add comment
COMMENT ON FUNCTION trigger_parse_message_ai() IS 'Automatically calls parse-message-ai edge function for new messages to extract AI insights';
COMMENT ON TRIGGER auto_parse_message_ai ON messages IS 'Triggers automatic AI parsing for newly inserted messages';
