-- Migration: 20251024120001_avatars_reactions.sql
-- Description: Add message reactions table and avatars storage bucket

-- ============================================
-- PART 1: Message Reactions Table
-- ============================================

CREATE TABLE IF NOT EXISTS public.message_reactions (
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (emoji IN ('👍', '❤️', '😂', '😮', '😢', '😡')),
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id, emoji)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON public.message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON public.message_reactions(user_id);

-- RLS Policies for message_reactions
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Users can read reactions on messages in their conversations
DROP POLICY IF EXISTS "Users can view reactions in their conversations" ON public.message_reactions;
CREATE POLICY "Users can view reactions in their conversations" ON public.message_reactions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
      WHERE m.id = message_reactions.message_id
        AND cp.user_id = auth.uid()
    )
  );

-- Users can add reactions to messages in their conversations
DROP POLICY IF EXISTS "Users can add reactions" ON public.message_reactions;
CREATE POLICY "Users can add reactions" ON public.message_reactions
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
      WHERE m.id = message_reactions.message_id
        AND cp.user_id = auth.uid()
    )
  );

-- Users can delete their own reactions
DROP POLICY IF EXISTS "Users can delete their own reactions" ON public.message_reactions;
CREATE POLICY "Users can delete their own reactions" ON public.message_reactions
  FOR DELETE
  USING (user_id = auth.uid());

-- ============================================
-- PART 2: Storage Bucket for Avatars
-- ============================================

-- Create storage bucket (this is idempotent)
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for avatars bucket
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
CREATE POLICY "Avatar images are publicly accessible" ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
CREATE POLICY "Authenticated users can upload avatars" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars' AND
    auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Users can update their own avatars" ON storage.objects;
CREATE POLICY "Users can update their own avatars" ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars' AND
    auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Users can delete their own avatars" ON storage.objects;
CREATE POLICY "Users can delete their own avatars" ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars' AND
    auth.role() = 'authenticated'
  );

-- ============================================
-- PART 3: Enable Realtime for Reactions
-- ============================================

-- Enable realtime updates for message_reactions table
-- Add table to realtime publication if not already added
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'message_reactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
    END IF;
END $$;
