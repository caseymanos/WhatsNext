-- Auto-detect conflicts when calendar events are added/modified
-- This trigger calls the detect-conflicts-agent edge function when events change

-- Function to invoke detect-conflicts-agent edge function
CREATE OR REPLACE FUNCTION trigger_detect_conflicts()
RETURNS TRIGGER AS $$
DECLARE
  function_url TEXT;
  service_role_key TEXT;
  request_body TEXT;
BEGIN
  -- Get Supabase URL and service role key from environment
  function_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/detect-conflicts-agent';
  service_role_key := current_setting('app.settings.service_role_key', true);

  -- Build request body
  request_body := json_build_object(
    'conversationId', NEW.conversation_id,
    'daysAhead', 14
  )::text;

  -- Make async HTTP request to edge function (non-blocking)
  -- This will detect conflicts for the conversation
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
    -- Log error but don't fail the insert/update
    RAISE WARNING 'Failed to trigger detect-conflicts-agent: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on calendar_events INSERT and UPDATE
DROP TRIGGER IF EXISTS auto_detect_conflicts ON calendar_events;
CREATE TRIGGER auto_detect_conflicts
  AFTER INSERT OR UPDATE ON calendar_events
  FOR EACH ROW
  EXECUTE FUNCTION trigger_detect_conflicts();

-- Add comment
COMMENT ON FUNCTION trigger_detect_conflicts() IS 'Automatically calls detect-conflicts-agent edge function when calendar events are added or modified';
COMMENT ON TRIGGER auto_detect_conflicts ON calendar_events IS 'Triggers automatic conflict detection when events change';
