-- Configure Realtime for messaging tables
-- This migration ensures that all necessary tables are properly configured for real-time updates

-- Ensure tables are in the supabase_realtime publication
-- This allows real-time events to be broadcast to subscribed clients
DO $$ 
BEGIN
    -- Add messages table to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;

    -- Add conversations table to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'conversations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
    END IF;

    -- Add read_receipts table to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'read_receipts'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.read_receipts;
    END IF;

    -- Add typing_indicators table to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'typing_indicators'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;
    END IF;
END $$;

-- Ensure authenticated users can receive realtime events
-- Grant SELECT permission required for realtime subscriptions
GRANT SELECT ON public.messages TO authenticated;
GRANT SELECT ON public.conversations TO authenticated;
GRANT SELECT ON public.read_receipts TO authenticated;
GRANT SELECT ON public.typing_indicators TO authenticated;

-- Grant usage on sequences if they exist
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Verify configuration
COMMENT ON TABLE public.messages IS 'Real-time enabled for message updates';
COMMENT ON TABLE public.conversations IS 'Real-time enabled for conversation updates';
COMMENT ON TABLE public.read_receipts IS 'Real-time enabled for read receipt updates';
COMMENT ON TABLE public.typing_indicators IS 'Real-time enabled for typing indicator updates';

