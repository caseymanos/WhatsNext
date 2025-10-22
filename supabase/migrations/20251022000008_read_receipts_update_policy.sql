-- Add UPDATE policy for read_receipts to support upsert operations
-- This fixes duplicate key violations when marking messages as read multiple times

DROP POLICY IF EXISTS rr_update_self ON public.read_receipts;
CREATE POLICY rr_update_self ON public.read_receipts
  FOR UPDATE USING (user_id = auth.uid());

