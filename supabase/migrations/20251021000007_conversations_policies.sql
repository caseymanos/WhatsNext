-- Conversations RLS: allow authenticated inserts and member updates

-- Ensure RLS is enabled (no-op if already enabled)
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- INSERT: any authenticated user may create a conversation record
DROP POLICY IF EXISTS conv_insert_any ON public.conversations;
DROP POLICY IF EXISTS conv_insert_authenticated ON public.conversations;
CREATE POLICY conv_insert_authenticated ON public.conversations
  FOR INSERT
  WITH CHECK ( auth.uid() IS NOT NULL );

-- UPDATE: only members of the conversation may update it (e.g., rename group)
DROP POLICY IF EXISTS conv_update_member ON public.conversations;
CREATE POLICY conv_update_member ON public.conversations
  FOR UPDATE
  USING ( public.is_conversation_member(id, auth.uid()) );


