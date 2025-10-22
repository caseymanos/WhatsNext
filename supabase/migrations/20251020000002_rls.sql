-- Enable RLS and define policies for core tables

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.read_receipts ENABLE ROW LEVEL SECURITY;

-- users
DROP POLICY IF EXISTS users_select_public ON public.users;
CREATE POLICY users_select_public ON public.users
  FOR SELECT USING (true);

DROP POLICY IF EXISTS users_update_self ON public.users;
CREATE POLICY users_update_self ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- conversations
DROP POLICY IF EXISTS conv_select_member ON public.conversations;
CREATE POLICY conv_select_member ON public.conversations
  FOR SELECT USING (
    id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS conv_insert_any ON public.conversations;
CREATE POLICY conv_insert_any ON public.conversations
  FOR INSERT WITH CHECK (true);

-- conversation_participants
DROP POLICY IF EXISTS conv_part_select_member ON public.conversation_participants;
CREATE POLICY conv_part_select_member ON public.conversation_participants
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS conv_part_insert_by_member ON public.conversation_participants;
CREATE POLICY conv_part_insert_by_member ON public.conversation_participants
  FOR INSERT WITH CHECK (
    conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- messages
DROP POLICY IF EXISTS msg_select_member ON public.messages;
CREATE POLICY msg_select_member ON public.messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS msg_insert_member_sender ON public.messages;
CREATE POLICY msg_insert_member_sender ON public.messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND
    conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- typing_indicators
DROP POLICY IF EXISTS typing_select_member ON public.typing_indicators;
CREATE POLICY typing_select_member ON public.typing_indicators
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS typing_upsert_self ON public.typing_indicators;
CREATE POLICY typing_upsert_self ON public.typing_indicators
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS typing_update_self ON public.typing_indicators;
CREATE POLICY typing_update_self ON public.typing_indicators
  FOR UPDATE USING (user_id = auth.uid());

-- read_receipts
DROP POLICY IF EXISTS rr_select_member ON public.read_receipts;
CREATE POLICY rr_select_member ON public.read_receipts
  FOR SELECT USING (
    message_id IN (
      SELECT id FROM public.messages WHERE conversation_id IN (
        SELECT conversation_id FROM public.conversation_participants
        WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS rr_insert_self ON public.read_receipts;
CREATE POLICY rr_insert_self ON public.read_receipts
  FOR INSERT WITH CHECK (user_id = auth.uid());


